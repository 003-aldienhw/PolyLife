local Player = {}

function Player.load()
    -- Inventory, stats, or tool here
end

function Player.update(dt)
    -- Handle movement input
end

function Player.getData()
    local hx, hy, hz = lovr.headset.getPosition()
    return hx, hy, hz
end

return Player