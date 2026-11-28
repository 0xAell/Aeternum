local _, addon = ...
local MapZoom = {}
addon.MapZoom = MapZoom

-- Interpolate in log scale so the motion feels the same at every zoom level.
-- A reversal starts at the displayed zoom instead of repaying queued wheel input.
function MapZoom.Queue(motion, current, delta, maximum)
    if delta == 0 then return false end
    local direction = delta > 0 and 1 or -1
    local base = motion.direction == direction and motion.target or current
    local logTarget = math.log(base) + delta * math.log(1.22)
    local target = logTarget <= 0 and 1 or (logTarget >= math.log(maximum) and maximum or math.exp(logTarget))
    if target == current then
        motion.target, motion.direction = nil, nil
        return false
    end
    motion.target, motion.direction = target, direction
    return true
end

function MapZoom.Advance(motion, current, elapsed)
    local target = motion.target
    if not target then return end
    local remaining = math.log(target / current)
    if math.abs(remaining) <= .0015 then
        motion.target, motion.direction = nil, nil
        return target
    end
    return current * math.exp(remaining * (1 - math.exp(-23 * elapsed)))
end
