local wezterm = require 'wezterm'
local dotfiles = assert(os.getenv 'MU88_DOTFILES', 'MU88_DOTFILES is required')
local config = wezterm.config_builder()
local dispatch = dofile(dotfiles .. '/WezTerm/lib/profile-dispatch.lua')
local loader = dofile(dotfiles .. '/WezTerm/json-profile-loader.lua')
local sources_loaded, data = pcall(loader.load, wezterm)
if not sources_loaded then
  wezterm.log_error('Profile sources could not be loaded')
  data = {}
end

local globals = data.globals or {}
local profiles = data.profiles or { list = data }
local by_name, by_guid = {}, {}
local choices = {}
local windows = wezterm.target_triple:find('windows', 1, true) ~= nil
local producer
if windows then
  local ok, module = pcall(dofile, dotfiles .. '/WezTerm/lib/taskbar-progress.lua')
  if ok then producer = module else wezterm.log_error('Unable to load the taskbar helper') end
end

-- Necessary for Bitwarden SSH agent
config.mux_enable_ssh_agent = false

local function display_name(profile)
  if profile.icon and profile.icon ~= '' then return profile.icon .. ' ' .. profile.name end
  return profile.name
end

local function menu_label(profile)
  local icon = profile.icon or ''
  return icon .. string.rep(' ', math.max(0, 2 - wezterm.column_width(icon))) .. ' ' .. profile.name
end

local command_for = dispatch.command_for

local function remember_profile(pane, profile)
  if pane and profile then
    wezterm.GLOBAL['wezterm_profile_pane_' .. tostring(pane:pane_id())] = profile.guid
  end
end

config.launch_menu = {}
for _, profile in ipairs(profiles.list or {}) do
  by_name[profile.name] = profile
  by_guid[profile.guid] = profile
  table.insert(choices, { id = profile.name, label = menu_label(profile) })
  local command = command_for(profile)
  command.label = menu_label(profile)
  table.insert(config.launch_menu, command)
end

config.exec_domains = dispatch.domains(wezterm, by_guid, wezterm.GLOBAL, globals)
local default_profile = by_guid[globals.defaultProfile]
config.default_prog = default_profile and default_profile.args or { 'pwsh', '-NoLogo' }
config.default_cwd = default_profile and default_profile.startingDirectory or os.getenv 'LOCAL_DEV_DIR'
config.set_environment_variables = {}
for name, value in pairs(globals.environment or {}) do config.set_environment_variables[name] = value end
config.set_environment_variables.WEZTERM_STARTUP_PROFILES = ''

config.font = wezterm.font 'FiraCode NF'
config.font_size = 11
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 48
config.status_update_interval = 150
local window_opacity = globals.windowOpacity or 1
config.window_background_opacity = window_opacity
config.colors = { background = '#101014' }
config.background = {
  {
    source = { Color = '#101014' },
    opacity = window_opacity,
    width = '100%', height = '100%',
  },
  {
    source = { File = globals.backgroundImage or dotfiles .. '/WindowsTerminal/Background.JPG' },
    opacity = (globals.backgroundImageOpacity or 0.2) * window_opacity,
    width = '100%', height = '100%',
  },
}

local select_profile = wezterm.action.InputSelector {
  title = 'Launch profile',
  choices = choices,
  action = wezterm.action_callback(function(window, _, name)
    if not name or not by_name[name] then return end
    local ok = pcall(function()
      local _, pane = window:mux_window():spawn_tab(command_for(by_name[name]))
      remember_profile(pane, by_name[name])
    end)
    if not ok then wezterm.log_error('Unable to launch the selected profile') end
  end),
}
local spawn_default
if default_profile then
  spawn_default = wezterm.action_callback(function(window)
    local ok = pcall(function()
      local _, pane = window:mux_window():spawn_tab(command_for(default_profile))
      remember_profile(pane, default_profile)
    end)
    if not ok then wezterm.log_error('Unable to launch the default profile') end
  end)
end

local function split_profile(pane, profile, direction)
  local ok = pcall(function()
    local command = command_for(profile)
    command.direction = direction
    command.domain = dispatch.split_domain(pane)
    local new_pane = pane:split(command)
    remember_profile(new_pane, profile)
    new_pane:activate()
  end)
  if not ok then wezterm.log_error('Unable to split the selected profile') end
end

local function split_action(direction)
  return wezterm.action_callback(function(window, pane)
    local guid = wezterm.GLOBAL['wezterm_profile_pane_' .. tostring(pane:pane_id())]
    local profile = by_guid[guid]
    if profile then
      split_profile(pane, profile, direction)
      return
    end

    window:perform_action(wezterm.action.InputSelector {
      title = 'Assign profile to this pane and open split',
      choices = choices,
      action = wezterm.action_callback(function(_, _, name)
        if name and by_name[name] then
          remember_profile(pane, by_name[name])
          split_profile(pane, by_name[name], direction)
        end
      end),
    }, pane)
  end)
end

config.keys = {
  { key = ' ', mods = 'CTRL|SHIFT', action = select_profile },
  { key = 'd', mods = 'CTRL|SHIFT', action = split_action('Right') },
  { key = 'e', mods = 'CTRL|SHIFT', action = split_action('Bottom') },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentTab { confirm = false } },
}
if spawn_default then
  table.insert(config.keys, { key = 't', mods = 'CTRL|SHIFT', action = spawn_default })
end

wezterm.on('new-tab-button-click', function(window, pane, button)
  if button == 'Left' and spawn_default then
    window:perform_action(spawn_default, pane)
    return false
  end
  if button == 'Right' then
    local ok = pcall(function() window:perform_action(select_profile, pane) end)
    if not ok then wezterm.log_error('Unable to open the profile selector') end
    return false
  end
end)

wezterm.add_to_config_reload_watch_list(dotfiles .. '/WezTerm/wezterm.lua')
wezterm.add_to_config_reload_watch_list(dotfiles .. '/WezTerm/json-profile-loader.lua')
wezterm.add_to_config_reload_watch_list(dotfiles .. '/WezTerm/lib/profile-dispatch.lua')
wezterm.on('gui-startup', function(command)
  local function abort_startup(message)
    wezterm.log_error(message)
    os.exit(1)
  end
  if not sources_loaded then abort_startup('Profile sources could not be loaded') end
  local dispatch_ok, profile_command, requested_profile = pcall(dispatch.startup_command, command, by_guid, globals)
  if not dispatch_ok then abort_startup('Invalid profile startup request') end
  local entries
  if profile_command then
    entries = { { command = profile_command, profile = requested_profile } }
  else
    local raw = os.getenv 'WEZTERM_STARTUP_PROFILES'
    local initial_command = {}
    for key, value in pairs(command or {}) do initial_command[key] = value end
    local initial_environment = {}
    for name, value in pairs(initial_command.set_environment_variables or {}) do initial_environment[name] = value end
    initial_environment.WEZTERM_STARTUP_PROFILES = ''
    initial_command.set_environment_variables = initial_environment
    if not command and default_profile then initial_command = command_for(default_profile) end
    entries = { { command = initial_command, profile = not command and default_profile or nil } }
    if raw and raw ~= '' and not command then
      local valid, selectors = pcall(loader.parse_array, wezterm, raw, 'Invalid startup profile list')
      if not valid then abort_startup('Invalid startup profile list') end
      local resolved = {}
      for _, selector in ipairs(selectors) do
        if type(selector) ~= 'string' or selector == '' then abort_startup('Invalid startup profile list') end
        local profile = dispatch.resolve_profile(selector, by_name, by_guid)
        if not profile then abort_startup('Startup profile not found') end
        table.insert(resolved, profile)
      end
      entries = {}
      for _, profile in ipairs(resolved) do table.insert(entries, { command = command_for(profile), profile = profile }) end
      table.insert(entries, {
        command = default_profile and command_for(default_profile) or { set_environment_variables = { WEZTERM_STARTUP_PROFILES = '' } },
        profile = default_profile,
      })
    end
  end
  local tab, pane, window = wezterm.mux.spawn_window(entries[1].command)
  remember_profile(pane, entries[1].profile)
  if producer then
    local ok, started = pcall(function() return producer.start(wezterm, dotfiles, window:window_id()) end)
    if not ok or not started then wezterm.log_error('Unable to start the taskbar helper') end
  end
  for index = 2, #entries do
    tab, pane = window:spawn_tab(entries[index].command)
    remember_profile(pane, entries[index].profile)
  end
  window:gui_window():maximize()
end)

local frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
wezterm.on('update-status', function(window)
  local busy, supported = false, true
  local ok = pcall(function()
    for _, tab in ipairs(window:mux_window():tabs()) do
      for _, pane in ipairs(tab:panes()) do
        local read_ok, progress = pcall(function() return pane:get_progress() end)
        if not read_ok or not (progress == 'None' or progress == 'Indeterminate'
          or type(progress) == 'table' and (progress.Percentage ~= nil or progress.Error ~= nil)) then
          supported = false
        elseif progress == 'Indeterminate' then
          busy = true
        end
      end
    end
  end)
  if not ok then supported = false end
  if producer then
    local update_ok = pcall(function()
      local count_ok, count = pcall(function() return #wezterm.gui.gui_windows() end)
      if not count_ok then count = 0 end
      producer.update(wezterm, window:mux_window():window_id(), count, busy, supported)
    end)
    if not update_ok then wezterm.log_error('Unable to update the taskbar helper') end
  end
  if busy then wezterm.GLOBAL.progress_frame = (wezterm.GLOBAL.progress_frame or 0) % #frames + 1 end
  local status = busy and string.rep(' ', wezterm.GLOBAL.progress_frame % 2 + 1) or ''
  local status_ok = pcall(function() window:set_right_status(status) end)
  if not status_ok then wezterm.log_error('Unable to update the window status') end
end)

local function tab_title(tab)
  local pane = tab.active_pane
  local profile = by_guid[wezterm.GLOBAL['wezterm_profile_pane_' .. tostring(pane.pane_id)]]
  local title = tab.tab_title and tab.tab_title ~= '' and tab.tab_title or nil
  local profile_name = false
  if not title and profile and profile.suppressApplicationTitle then
    title = profile.tabTitle and profile.tabTitle ~= '' and profile.tabTitle or profile.name
    profile_name = title == profile.name
  end
  title = title or pane.title
  if not title or title == '' then
    title = profile and (profile.tabTitle and profile.tabTitle ~= '' and profile.tabTitle or profile.name) or ''
    profile_name = profile ~= nil and title == profile.name
  end
  return title, profile, profile_name
end

wezterm.on('format-window-title', function(tab)
  local title, profile, profile_name = tab_title(tab)
  if profile_name then
    return profile.name
  end
  return title
end)

wezterm.on('format-tab-title', function(tab)
  local title, profile = tab_title(tab)
  if profile and title == profile.name then title = display_name(profile) end
  if profile and profile.icon and profile.icon ~= '' and title:sub(1, #profile.icon) ~= profile.icon then
    title = profile.icon .. ' ' .. title
  end
  local pane = tab.active_pane
  for _, tab_pane in ipairs(tab.panes or { pane }) do
    if tab_pane.progress == 'Indeterminate' then
      return frames[wezterm.GLOBAL.progress_frame or 1] .. ' ' .. title
    end
  end
  return title
end)

return config
