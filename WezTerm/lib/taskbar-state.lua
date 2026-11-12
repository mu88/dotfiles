local M = {}

function M.classify(window_count, busy, supported)
  if window_count ~= 1 or type(busy) ~= 'boolean' or supported ~= true then
    return 'disabled'
  end
  return busy and 'busy' or 'idle'
end

function M.should_publish(state, previous_state, now, previous_time)
  if state ~= previous_state or previous_time == nil then return true end
  return now < previous_time or now - previous_time >= 2
end

return M
