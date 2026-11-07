local World = require "world"
local Player = {}

local collider = nil
local current_speed = 6.0
local sprint_speed = 12.0
local player_strength = 5.0
local yaw = 0.0
local pitch = 0.0

local editing_mode = false
local edit_target = nil
local edit_radius = 3.0
local edit_distance = 20.0

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

local function update_edit_target()
    if not editing_mode then
        edit_target = nil
        return
    end

    if collider then
        local x, y, z = collider:getPosition()

        y = y + 0.6

        local dir_x = -math.sin(yaw) * math.cos(pitch)
        local dir_y = math.sin(pitch)
        local dir_z = -math.cos(yaw) * math.cos(pitch)

        edit_target = World.getTerrainTarget(x, y, z, dir_x, dir_y, dir_z, edit_distance)
    end
end

function Player.update(dt)
    if not collider then return end
    local vx, vy, vz = collider:getLinearVelocity()
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

    local sprinting = lovr.system.isKeyDown('lshift')
    local speed = sprinting and sprint_speed or current_speed

    local len = math.sqrt(dx * dx + dz * dz)
    if len > 0 then
        dx, dz = dx / len, dz / len

        local multiplier = World.getMovementMultiplier(dx, dz, player_strength)
        dx, dz = dx * speed * multiplier, dz * speed * multiplier
    end

    local smoothing = 12.0
    local alpha = 1.0 - math.exp(-smoothing * dt)

    vx = vx + (dx - vx) * alpha
    vz = vz + (dz - vz) * alpha

    if World.isPlayerGrounded() then
        if lovr.system.isKeyDown('space') then
            vy = 5.5
        end
    end

    if lovr.system.isKeyDown('escape') then
        lovr.system.setMouseMode("normal")
    end

    if lovr.system.isKeyDown('backspace') then
        lovr.system.setMouseMode("relative")
    end

    collider:setLinearVelocity(vx, vy, vz)
    update_edit_target()
end

function Player.keypressed(key)
    if key == 'e' then
        editing_mode = not editing_mode
        edit_target = nil
    end
end

function Player.mousepressed(x, y, button)
    if not editing_mode or not edit_target then
        return
    end

    local tx = edit_target.x
    local ty = edit_target.y
    local tz = edit_target.z

    if not World.canEditTerrain(tx, ty, tz, edit_radius) then
        print("Cannot edit terrain near an object!")
        return
    end

    if button == 1 then
        World.digTerrain(tx, ty, tz, edit_radius)
    elseif button == 2 then
        World.addTerrain(tx, ty, tz, edit_radius)
    end
end

function Player.getEditData()
    return edit_target, editing_mode, edit_radius
end

function Player.getData()
    if collider then
        local x, y, z = collider:getPosition()
        return x, y + 0.6, z, yaw, pitch
    end
    return 0, 15, 0, 0, 0
end

return Player