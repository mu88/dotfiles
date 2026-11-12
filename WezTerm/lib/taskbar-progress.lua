local M = {}
local state_policy

local function record(token, sequence, state)
  local encoded_state = state == 'busy' and 'busy____' or state == 'idle' and 'idle____' or state
  return string.format('%s|%019d|%s|END', token, sequence, encoded_state)
end

local function report_error(wezterm, message)
  pcall(wezterm.log_error, message)
end

function M.start(wezterm, dotfiles, window_id)
  local ok, started = pcall(function()
    if not wezterm.target_triple:find('windows', 1, true) then return false end
    if type(window_id) ~= 'number' or window_id < 0 or window_id % 1 ~= 0 then return false end

    local pid = wezterm.procinfo.pid()
    if type(pid) ~= 'number' or pid <= 0 then return false end
    local existing = wezterm.GLOBAL.taskbar_progress
    if existing and existing.pid == pid then return existing.window_id == window_id end

    local temp = os.getenv 'TMP'
    if not temp or temp == '' then temp = os.getenv 'TEMP' end
    if not temp or temp == '' then return false end
    temp = temp:gsub('\\', '/'):gsub('/+$', '')
    local now = os.time()
    local token = string.format('%08x%08x%08x%08x', pid % 0x100000000, now % 0x100000000,
      math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    local path = temp .. '/wezterm-taskbar-' .. token .. '.txt'

    local existing_file = io.open(path, 'rb')
    if existing_file then existing_file:close(); return false end

    wezterm.background_child_process {
      'pwsh', '-NoLogo', '-NoProfile', '-File', dotfiles .. '/WezTerm/TaskbarProgress.ps1',
      '-GuiPid', tostring(pid), '-StateFile', path, '-Token', token,
    }
    wezterm.GLOBAL.taskbar_progress = {
      pid = pid, window_id = window_id, token = token, path = path, dotfiles = dotfiles, sequence = 0,
    }
    return true
  end)
  if not ok then report_error(wezterm, 'Unable to start the taskbar helper') end
  return ok and started or false
end

function M.update(wezterm, window_id, window_count, busy, supported)
  local ok, updated = pcall(function()
    local control = wezterm.GLOBAL.taskbar_progress
    if not control or control.window_id ~= window_id then return false end

    if not state_policy then
      state_policy = dofile(control.dotfiles .. '/WezTerm/lib/taskbar-state.lua')
    end
    local state = state_policy.classify(window_count, busy, supported)
    local now = os.time()
    if not state_policy.should_publish(state, control.last_state, now, control.last_time) then return false end

    local file = io.open(control.path, 'r+b')
    if not file then return false end
    local read_ok, current = pcall(file.read, file, 129)
    local expected = record(control.token, control.sequence, control.last_state or 'disabled')
    if not read_ok or current ~= expected then pcall(file.close, file); return false end
    local seek_ok, position = pcall(file.seek, file, 'set', 0)
    if not seek_ok or position ~= 0 then pcall(file.close, file); return false end
    local sequence = control.sequence + 1
    local write_ok, wrote = pcall(file.write, file, record(control.token, sequence, state))
    local close_ok, closed = pcall(file.close, file)
    if not write_ok or not wrote or not close_ok or not closed then return false end

    control.sequence = sequence
    control.last_state = state
    control.last_time = now
    wezterm.GLOBAL.taskbar_progress = control
    return true
  end)
  if not ok then report_error(wezterm, 'Unable to update the taskbar helper') end
  return ok and updated or false
end

return M
