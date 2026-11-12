local M = {}
M.sentinel = 'C:\\<wezterm-profile-dispatch>'
M.default_domain = 'profile-default'

local function guid_key(value)
  assert(type(value) == 'string' and value:match('^%{%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x%}$'), 'Invalid profile GUID')
  return value:lower()
end

local function exact_args(args, expected)
  if type(args) ~= 'table' or #args ~= expected then return false end
  local count = 0
  for index in pairs(args) do
    if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > expected then return false end
    count = count + 1
  end
  return count == expected
end

function M.domain_name(guid)
  return 'profile-' .. guid_key(guid)
end

function M.resolve_profile(selector, by_name, by_guid)
  if type(selector) ~= 'string' or selector == '' then return nil end
  local candidate = selector
  if selector:sub(1, 1) ~= '{' or selector:sub(-1) ~= '}' then candidate = '{' .. selector .. '}' end
  local valid, key = pcall(guid_key, candidate)
  return valid and by_guid[key] or by_name[selector]
end

function M.command_for(profile, cwd)
  assert(type(profile) == 'table' and type(profile.args) == 'table' and #profile.args > 0, 'Invalid profile command')
  assert(cwd == nil or type(cwd) == 'string' and cwd ~= '', 'Invalid cwd override')
  assert(profile.startingDirectory == nil or type(profile.startingDirectory) == 'string', 'Invalid starting directory')
  assert(profile.environment == nil or type(profile.environment) == 'table', 'Invalid profile environment')
  local args, environment = {}, {}
  for index, value in ipairs(profile.args) do
    assert(type(value) == 'string' and (index ~= 1 or value ~= ''), 'Invalid profile argument')
    args[index] = value
  end
  for name, value in pairs(profile.environment or {}) do
    assert(type(name) == 'string' and type(value) == 'string', 'Invalid profile environment entry')
    assert(name:upper() ~= 'WEZTERM_PANE', 'Profile cannot set pane identity')
    if name:upper() ~= 'WEZTERM_STARTUP_PROFILES' then environment[name] = value end
  end
  environment.WEZTERM_STARTUP_PROFILES = ''
  return { args = args, cwd = cwd or profile.startingDirectory, set_environment_variables = environment }
end

local function default_key(globals)
  assert(type(globals) == 'table' and globals.defaultProfile ~= nil, 'Default profile is not configured')
  return guid_key(globals.defaultProfile)
end

local function fixup_for(profiles, resolve_key, metadata)
  return function(request)
    assert(type(request) == 'table' and exact_args(request.args, 1)
      and request.args[1] == M.sentinel, 'Refusing unexpected exec-domain command')
    local key = resolve_key()
    local profile = profiles[key]
    assert(profile, 'Unknown profile')
    assert(request.cwd == nil or type(request.cwd) == 'string' and request.cwd ~= '', 'Invalid cwd override')
    assert(request.set_environment_variables == nil or type(request.set_environment_variables) == 'table', 'Invalid request environment')
    local incoming = request.set_environment_variables or {}
    local pane_id = incoming.WEZTERM_PANE
    assert(type(pane_id) == 'string' and pane_id:match('^%d+$'), 'Missing or invalid pane identity')
    local result = M.command_for(profile, request.cwd)
    for name, value in pairs(incoming) do
      assert(type(name) == 'string' and type(value) == 'string', 'Invalid request environment entry')
      local upper = name:upper()
      if upper ~= 'WEZTERM_PANE' and upper ~= 'WEZTERM_STARTUP_PROFILES' then
        local conflicts = false
        for existing in pairs(result.set_environment_variables) do
          if existing:upper() == upper then conflicts = true; break end
        end
        if not conflicts then result.set_environment_variables[name] = value end
      end
    end
    result.set_environment_variables.WEZTERM_PANE = pane_id
    request.args, request.cwd, request.set_environment_variables = result.args, result.cwd, result.set_environment_variables
    metadata['wezterm_profile_pane_' .. pane_id] = key
    return request
  end
end

function M.fixup(profiles, guid, metadata)
  local key = guid_key(guid)
  return fixup_for(profiles, function() return key end, metadata)
end

function M.domains(wezterm, profiles, metadata, globals)
  local domains = {}
  for guid in pairs(profiles) do
    local captured_guid = guid_key(guid)
    local fixup = M.fixup(profiles, captured_guid, metadata)
    domains[#domains + 1] = wezterm.exec_domain(M.domain_name(captured_guid), fixup)
  end
  local fixup = fixup_for(profiles, function() return default_key(globals) end, metadata)
  domains[#domains + 1] = wezterm.exec_domain(M.default_domain, fixup)
  return domains
end

function M.startup_command(command, profiles, globals)
  if type(command) ~= 'table' or type(command.args) ~= 'table' or command.args[1] ~= M.sentinel then return nil end
  assert(exact_args(command.args, 2), 'Invalid startup sentinel arguments')
  local key = command.args[2] == 'default' and default_key(globals) or guid_key(command.args[2])
  local profile = profiles[key]
  assert(profile, 'Unknown profile')
  assert(command.domain == nil or command.domain == 'DefaultDomain', 'Explicit startup domain is unsupported')
  assert(command.position == nil and command.label == nil, 'Additional startup options are unsupported')
  assert(command.set_environment_variables == nil or type(command.set_environment_variables) == 'table', 'Invalid startup environment')
  -- The builder can include its full inherited environment. Do not copy it
  -- into the profile command: only the profile may set explicit variables.
  return M.command_for(profile, command.cwd), profile
end

function M.split_domain(pane)
  local domain = pane:get_domain_name()
  if domain == M.default_domain then return 'DefaultDomain' end
  local suffix = type(domain) == 'string' and domain:match('^profile%-(%b{})$')
  if suffix then
    local valid, normalized = pcall(guid_key, suffix)
    if valid and suffix == normalized then return 'DefaultDomain' end
  end
  return nil
end

return M
