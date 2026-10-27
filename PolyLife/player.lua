local World = require "world"
local Player = {}

local collider = nil
local speed = 6.0
local player_strength = 15.0
local yaw = 0.0
local pitch = 0.0

function Player.load()
    collider = World.createPlayerCollider(0, 22, 0)
    if lovr.system.setMouseMode then
        lovr.system.setMouseMode("relative")
    end
end

function Player.mousemoved(x, y, dx, dy)
    local sensitivity = 0.003
    yaw = yaw - dx * sensitivity
    pitch = pitch - dy * sensitivity
    pitch = math.max(-1.4, math.min(1.4, pitch))
end

function Player.update(dt)
    if not collider then return end
    local vz, vy, vz = collider:getLinearVelocity()
    local px, py, pz = collider:getPosition()

    local forward_x = -math.sin(yaw)
    local forward_z = -math.cos(yaw)
    local right_x = math.cos(yaw)
    local right_z = -math.sin(yaw)

    local dx, dz = 0, 0

    if lovr.system.isKeyDown('w', 'up') then dx = dx + forward_x; dz = dz + forward_z end
    if lovr.system.isKeyDown('s', 'down') then dx = dx - forward_x; dz = dz - forward_z end
    if lovr.system.isKeyDown('a', 'left') then dx = dx - right_x; dz = dz - right_z end
    if lovr.system.isKeyDown('d', 'right') then dx = dx + right_x; dz = dz + right_z end

    local len = math.sqrt(dx * dx + dz * dz)
    if len > 0 then
        dx, dz = dx / len, dz / len

        local speed_multiplier = World.getMovementMultiplier(px, py, pz, dx, dz, player_strength)
        dx, dz = dx * speed * speed_multiplier, dz * speed * speed_multiplier
    else
        dx, dz = 0, 0
    end

    if lovr.system.isKeyDown('space') then
        if World.isPlayerGrounded() then
            vy = 5.5
        end
    end

    if lovr.system.isKeyDown('escape') then
        lovr.system.setMouseMode("normal")
    end

    if lovr.system.isKeyDown('backspace') then
        lovr.system.setMouseMode("relative")
    end

    collider:setLinearVelocity(dx, vy, dz)
end

function Player.getData()
    if collider then
        local x, y, z = collider:getPosition()
        return x, y + 0.6, z, yaw, pitch
    end
    return 0, 15, 0, 0, 0
end

return Player