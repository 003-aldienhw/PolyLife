local function grid(size, subdivisions)
  local vertices = {}
  local step = size / (subdivisions - 1)
  for z = -size / 2, size / 2, step do
    for x = -size / 2, size / 2, step do
      table.insert(vertices, {x, 0, z})
      table.insert(vertices, {x, 0, z + step})
      table.insert(vertices, {x + step, 0, z})
      table.insert(vertices, {x, 0, z + step})
      table.insert(vertices, {x + step, 0, z + step})
      table.insert(vertices, {x + step, 0, z})
    end
  end
  local water_vertices = {}
  local step = size / (subdivisions - 1)
  for z = -size / 2, size / 2, step do
    for x = -size / 2, size / 2, step do
      table.insert(water_vertices, {x, 0, z})
      table.insert(water_vertices, {x, 0, z + step})
      table.insert(water_vertices, {x + step, 0, z})
      table.insert(water_vertices, {x, 0, z + step})
      table.insert(water_vertices, {x + step, 0, z + step})
      table.insert(water_vertices, {x + step, 0, z})
    end
  end
  return vertices, water_vertices
end

local function terrain_fn(x, z)
  return 10 * (lovr.math.noise(x * 0.05, z * 0.05) - 0.5)
end

function lovr.load()
  size = 200
  world = lovr.physics.newWorld(0, -9.81, 0, false)
  lovr.graphics.setBackgroundColor(0x02b2f2)
  local vertices, water_vertices = grid(size, 100)
  for vi = 1, #vertices do
    local x,y,z = unpack(vertices[vi])
    vertices[vi][2] = terrain_fn(x, z)
  end
  ground_mesh = lovr.graphics.newMesh(vertices)
  water_mesh = lovr.graphics.newMesh(water_vertices)
  world:newTerrainCollider(size, terrain_fn)
  box_colliders = {}
end

function lovr.update(dt)
  if lovr.timer.getTime() % 1 < dt then
    local collider = world:newBoxCollider(
      lovr.math.randomNormal(size / 10, 0),
      lovr.math.randomNormal(1, 20),
      lovr.math.randomNormal(size / 10, 0),
      1)
    table.insert(box_colliders, collider)
  end
  world:update(dt)
end

function lovr.draw(pass)
  pass:setColor(0x32a852)
  for _, collider in ipairs(box_colliders) do
    local x, y, z, angle, ax, ay, az = collider:getPose()
    pass:cube(x, y, z, 1, angle, ax, ay, az)
  end

  pass:setColor(0x029c1e)
  pass:draw(ground_mesh)

  pass:setColor(0x062cb8)
  pass:draw(water_mesh)

  pass:setWireframe(true)
  pass:setColor(0x022e0e)
  pass:draw(ground_mesh)
  pass:setColor(0x01186e)
  pass:draw(water_mesh)
end