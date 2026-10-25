local World = require "world"
local Player = require "player"

function lovr.load()
  World.load()
  Player.load()
end

function lovr.update(dt)
  local current_time = lovr.timer.getTime()
  World.update(dt, current_time)
  Player.update(dt)
end

function lovr.mousemoved(x, y, dx, dy)
  Player.mousemoved(x, y, dx, dy)
end

function lovr.draw(pass)
  local hx, hy, hz, yaw, pitch = Player.getData()
  local pose = lovr.math.newMat4():translate(hx, hy, hz):rotate(yaw, 0, 1, 0):rotate(pitch, 1, 0, 0)
  pass:setViewPose(1, pose)
  local current_time = lovr.timer.getTime()
  local water_size = World.getWaterSize()
  local half_bounds = water_size / 2
  local inside_water = math.abs(hx) <= half_bounds and math.abs(hz) <= half_bounds
  local wave_height = World.physical_water_height(hx, hz, current_time)
  local underwater = inside_water and (hy < wave_height)

  if underwater then
    lovr.graphics.setBackgroundColor(0.02, 0.10, 0.25)
  else
    lovr.graphics.setBackgroundColor(0x02b2f2)
  end

  World.draw(pass, current_time, {hx, hy, hz}, underwater)
end