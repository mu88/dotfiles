local M = {}

local function parse_json(wezterm, contents, message)
  local quoted, escaped = false, false
  for index = 1, #contents do
    local character = contents:sub(index, index)
    if quoted then
      if escaped then escaped = false
      elseif character == '\\' then escaped = true
      elseif character == '"' then quoted = false end
    elseif character == '"' then quoted = true
    elseif contents:sub(index, index + 3) == 'null' then error(message) end
  end
  local ok, value = pcall(wezterm.json_parse, contents)
  assert(ok, message)
  return value
end

function M.parse_array(wezterm, contents, message)
  local entries = parse_json(wezterm, contents, message)
  assert(type(entries) == 'table' and contents:match('^%s*%['), message)
  return entries
end

-- Preserve JSON container types, including empty arrays and objects, which Lua
-- otherwise represents identically. The JSON parser has already validated syntax.
local function typed_json(wezterm, contents, message)
  local value = parse_json(wezterm, contents, message)
  local position = 1

  local function whitespace()
    while contents:sub(position, position):match('%s') do position = position + 1 end
  end

  local function string_end()
    position = position + 1
    while true do
      local character = contents:sub(position, position)
      position = position + 1
      if character == '\\' then position = position + 1
      elseif character == '"' then return end
    end
  end

  local read_value
  read_value = function()
    whitespace()
    local character = contents:sub(position, position)
    if character == '{' then
      position = position + 1
      local fields = {}
      whitespace()
      while contents:sub(position, position) ~= '}' do
        local start = position
        string_end()
        local key_json = contents:sub(start, position - 1)
        local keys = parse_json(wezterm, '[' .. key_json .. ']', message)
        local key = keys[1]
        whitespace()
        position = position + 1
        fields[key] = read_value()
        whitespace()
        if contents:sub(position, position) == ',' then position = position + 1; whitespace() end
      end
      position = position + 1
      return { kind = 'object', value = fields }
    elseif character == '[' then
      position = position + 1
      local items = {}
      whitespace()
      while contents:sub(position, position) ~= ']' do
        items[#items + 1] = read_value()
        whitespace()
        if contents:sub(position, position) == ',' then position = position + 1; whitespace() end
      end
      position = position + 1
      return { kind = 'array', value = items }
    elseif character == '"' then
      string_end()
    else
      while not contents:sub(position, position):match('[%s,%]}]') and position <= #contents do
        position = position + 1
      end
    end
    return { kind = 'scalar' }
  end

  local function bind(node, parsed)
    if node.kind == 'scalar' then
      node.value = parsed
    else
      assert(type(parsed) == 'table', message)
      for key, child in pairs(node.value) do bind(child, parsed[key]) end
    end
  end

  local root = read_value()
  bind(root, value)
  return root
end

local function object()
  return { kind = 'object', value = {} }
end

local function merge(base, override)
  if base.kind ~= 'object' or override.kind ~= 'object' then return override end
  local fields = {}
  for key, value in pairs(base.value) do fields[key] = value end
  for key, value in pairs(override.value) do
    fields[key] = fields[key] and merge(fields[key], value) or value
  end
  return { kind = 'object', value = fields }
end

local function plain(node)
  if node.kind == 'scalar' then return node.value end
  local result = {}
  for key, value in pairs(node.value) do result[key] = plain(value) end
  return result
end

local function require_object(node, message)
  assert(node and node.kind == 'object', message)
end

local function validate_environment(node)
  if not node then return end
  require_object(node, 'Environment must be an object')
  for _, value in pairs(node.value) do
    assert(value.kind == 'scalar' and type(value.value) == 'string', 'Environment values must be strings')
  end
end

local function optional_type(fields, name, expected)
  local value = fields[name]
  assert(not value or (value.kind == 'scalar' and type(value.value) == expected), 'Invalid profile or global field type')
end

local function normalize_guid(value)
  if type(value) ~= 'string' then return nil end
  if value:sub(1, 1) == '{' and value:sub(-1) == '}' then value = value:sub(2, -2) end
  if not value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') then return nil end
  return '{' .. value:lower() .. '}'
end

local function expand_path(path)
  return (path:gsub('%${([%a_][%w_]*)}', function(name)
    local value = os.getenv(name)
    assert(value and value ~= '', 'Missing environment variable')
    return value
  end))
end

local function validate_profile(node)
  require_object(node, 'Profile must be an object')
  local fields = node.value
  for _, name in ipairs({ 'guid', 'name' }) do
    local value = fields[name]
    assert(value and value.kind == 'scalar' and type(value.value) == 'string' and value.value ~= '', 'A profile requires a GUID and name')
  end
  local args = fields.args
  assert(args and args.kind == 'array' and #args.value > 0, 'A profile requires a command')
  for index, argument in ipairs(args.value) do
    assert(argument.kind == 'scalar' and type(argument.value) == 'string' and (index ~= 1 or argument.value ~= ''), 'Profile arguments must be strings and the command must not be empty')
  end
  for _, name in ipairs({ 'startingDirectory', 'icon', 'tabTitle' }) do optional_type(fields, name, 'string') end
  optional_type(fields, 'suppressApplicationTitle', 'boolean')
  validate_environment(fields.environment)
  local profile = plain(node)
  if profile.startingDirectory then profile.startingDirectory = expand_path(profile.startingDirectory) end
  return profile
end

function M.load(wezterm)
  local globals, defaults = object(), object()
  local profiles, indices = {}, {}
  local sources = os.getenv 'WEZTERM_JSON_PROFILE_SOURCES'
  if sources and sources ~= '' then
    assert(not sources:match('^;') and not sources:match(';$') and not sources:find(';;', 1, true), 'Invalid profile source list')
    for path in sources:gmatch('[^;]+') do
      local file = assert(io.open(path, 'rb'), 'Could not open profile source')
      local contents = file:read('*a')
      file:close()
      local source = typed_json(wezterm, contents, 'Invalid JSON profile source')
      require_object(source, 'Profile source must be an object')
      wezterm.add_to_config_reload_watch_list(path)
      local fields = source.value
      if fields.globals then
        require_object(fields.globals, 'Globals must be an object')
        globals = merge(globals, fields.globals)
      end
      if fields.profiles then
        require_object(fields.profiles, 'Profiles must be an object')
        local section = fields.profiles.value
        if section.defaults then
          require_object(section.defaults, 'Profile defaults must be an object')
          defaults = merge(defaults, section.defaults)
        end
        if section.list then
          assert(section.list.kind == 'array', 'Profile list must be an array')
          local source_guids = {}
          for _, profile in ipairs(section.list.value) do
            require_object(profile, 'Profile must be an object')
            local guid = profile.value.guid
            local id = guid and guid.kind == 'scalar' and normalize_guid(guid.value)
            assert(id, 'A profile requires a valid GUID')
            guid.value = id
            assert(not source_guids[id], 'Profile GUIDs must be unique within a source')
            source_guids[id] = true
            local index = indices[id]
            if index then
              profiles[index] = merge(profiles[index], profile)
            else
              profiles[#profiles + 1] = profile
              indices[id] = #profiles
            end
          end
        end
      end
    end
  end

  validate_environment(globals.value.environment)
  optional_type(globals.value, 'defaultProfile', 'string')
  optional_type(globals.value, 'backgroundImage', 'string')
  optional_type(globals.value, 'backgroundImageOpacity', 'number')
  optional_type(globals.value, 'windowOpacity', 'number')
  for _, name in ipairs({ 'backgroundImageOpacity', 'windowOpacity' }) do
    local value = globals.value[name]
    assert(not value or (value.value >= 0 and value.value <= 1), 'Opacity must be between 0 and 1')
  end
  local result = { globals = plain(globals), profiles = { defaults = plain(defaults), list = {} } }
  if result.globals.defaultProfile then
    result.globals.defaultProfile = normalize_guid(result.globals.defaultProfile)
    assert(result.globals.defaultProfile and indices[result.globals.defaultProfile], 'Default profile must identify an existing profile')
  end
  if result.globals.backgroundImage then result.globals.backgroundImage = expand_path(result.globals.backgroundImage) end
  local names = {}
  for _, profile in ipairs(profiles) do
    local resolved = validate_profile(merge(defaults, profile))
    assert(not names[resolved.name], 'Profile names must be unique')
    names[resolved.name] = true
    table.insert(result.profiles.list, resolved)
  end
  return result
end

return M
