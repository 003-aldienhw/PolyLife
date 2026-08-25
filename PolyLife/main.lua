local function grid(size, subdivisions)
  local ground_vertices = {}
  local step = size / (subdivisions - 1)
  local half = size / 2
  for z = -half, half - step + 0.001, step do
    for x = -half, half - step + 0.001, step do
      table.insert(ground_vertices, {x, 0, z, "top"})
      table.insert(ground_vertices, {x, 0, z + step, "top"})
      table.insert(ground_vertices, {x + step, 0, z, "top"})
      table.insert(ground_vertices, {x, 0, z + step, "top"})
      table.insert(ground_vertices, {x + step, 0, z + step, "top"})
      table.insert(ground_vertices, {x + step, 0, z, "top"})
    end
  end
  local function add_walls(x1, z1, x2, z2, label)
    table.insert(ground_vertices, {x1, 0, z1, label})
    table.insert(ground_vertices, {x1, 0, z1, "bottom"})
    table.insert(ground_vertices, {x2, 0, z2, label})
    table.insert(ground_vertices, {x1, 0, z1, "bottom"})
    table.insert(ground_vertices, {x2, 0, z2, "bottom"})
    table.insert(ground_vertices, {x2, 0, z2, label})
  end
  for i = -half, half - step + 0.001, step do
    add_walls(i, -half, i + step, -half, "edge_z_min")
    add_walls(i, half, i + step, half, "edge_z_min")
    add_walls(-half, i, -half, i + step, "edge_x_min")
    add_walls(half, i, half, i + step, "edge_x_min")
  end
  for z = -half, half - step + 0.001, step do
    for x = -half, half - step + 0.001, step do
      table.insert(ground_vertices, {x, 0, z, "bottom"})
      table.insert(ground_vertices, {x, 0, z + step, "bottom"})
      table.insert(ground_vertices, {x + step, 0, z, "bottom"})
      table.insert(ground_vertices, {x, 0, z + step, "bottom"})
      table.insert(ground_vertices, {x + step, 0, z + step, "bottom"})
      table.insert(ground_vertices, {x + step, 0, z, "bottom"})
    end
  end
  local water_vertices = {}
  local w_step = size / (subdivisions - 1)
  for z = -half, half - w_step + 0.001, w_step do
    for x = -half, half - w_step + 0.001, w_step do
      table.insert(water_vertices, {x, 0, z, "water"})
      table.insert(water_vertices, {x, 0, z + step, "water"})
      table.insert(water_vertices, {x + step, 0, z, "water"})
      table.insert(water_vertices, {x, 0, z + step, "water"})
      table.insert(water_vertices, {x + step, 0, z + step, "water"})
      table.insert(water_vertices, {x + step, 0, z, "water"})
    end
  end
  return ground_vertices, water_vertices
end

local function terrain_fn(x, z)
  return 10 * (lovr.math.noise(x * 0.05, z * 0.05) - 0.5)
end

function lovr.load()
  terrain_size = 100
  water_size = 200
  thickness = -5
  world = lovr.physics.newWorld(0, -9.81, 0, false)
  lovr.graphics.setBackgroundColor(0x02b2f2)
  local ground_vertices = grid(terrain_size, 100)
  local _, water_vertices = grid(water_size, 120)
  for vi = 1, #ground_vertices do
    local x,y,z,tag = ground_vertices[vi][1], ground_vertices[vi][2], ground_vertices[vi][3], ground_vertices[vi][4]
    if tag == "top" or tag:sub(1,5) == "edge_" then
      ground_vertices[vi][2] = terrain_fn(x, z)
    end
    if tag == "bottom" then
      ground_vertices[vi][2] = thickness
    end
    ground_vertices[vi][4] = nil
  end
  for vi = 1, #water_vertices do
    water_vertices[vi][4] = nil
  end
  ground_mesh = lovr.graphics.newMesh(ground_vertices)
  water_mesh = lovr.graphics.newMesh(water_vertices)
  world:newTerrainCollider(terrain_size, terrain_fn)
  box_colliders = {}
end

function lovr.update(dt)
  if lovr.timer.getTime() % 1 < dt then
    local collider = world:newBoxCollider(
      lovr.math.randomNormal(terrain_size / 10, 0),
      lovr.math.randomNormal(1, 20),
      lovr.math.randomNormal(terrain_size / 10, 0),
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