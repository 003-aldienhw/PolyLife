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
      table.insert(water_vertices, {x, 0, z})
      table.insert(water_vertices, {x, 0, z + w_step})
      table.insert(water_vertices, {x + w_step, 0, z})
      table.insert(water_vertices, {x, 0, z + w_step})
      table.insert(water_vertices, {x + w_step, 0, z + w_step})
      table.insert(water_vertices, {x + w_step, 0, z})
    end
  end
  return ground_vertices, water_vertices
end

terrain_size = 150
water_size = 200

local function terrain_fn(x, z)
  local half = terrain_size / 2
  local seabed_depth = -8.0
  local falloff_start = 0.55
  local nx = math.abs(x) / half
  local nz = math.abs(z) / half
  local dist = math.max(nx, nz)
  local raw_y = 10 * (lovr.math.noise(x * 0.05, z * 0.05) - 0.5)

  if dist > falloff_start then
    local t = (dist - falloff_start) / (1.0 - falloff_start)
    t = math.min(1.0, math.max(0.0, t))
    local smooth_t = t * t * (3 - 2 * t)
    return raw_y * (1 - smooth_t) + seabed_depth * smooth_t
  end
  return raw_y
end

local function get_terrain_color(y, tag)
  if tag == "bottom" then
    return 0.12, 0.12, 0.15, 1.0
  elseif tag and tag:sub(1,5) == "edge_" then
    return 0.20, 0.20, 0.22, 1.0
  end

  if y > 2.5 then
    return 0.55, 0.55, 0.58, 1.0
  elseif y > 0.4 then
    return 0.45, 0.30, 0.18, 1.0
  elseif y > -0.2 then
    return 0.18, 0.55, 0.22, 1.0
  elseif y > -2.0 then
    return 0.76, 0.70, 0.50, 1.0
  else
    return 0.15, 0.25, 0.30, 1.0
  end
end

function lovr.load()
  world_bottom = -12
  world = lovr.physics.newWorld(0, -9.81, 0, false)
  lovr.graphics.setBackgroundColor(0x02b2f2)
  local vertex_format = {
    { 'VertexPosition', 'vec3' },
    { 'VertexColor', 'vec4' }
  }
  local raw_ground_vertices = grid(terrain_size, 100)
  local water_vertices = grid(water_size, 120)
  local ground_vertices = {}
  for vi = 1, #raw_ground_vertices do
    local x,y,z,tag = raw_ground_vertices[vi][1], raw_ground_vertices[vi][2], raw_ground_vertices[vi][3], raw_ground_vertices[vi][4]
    if tag == "top" or (tag and tag:sub(1,5) == "edge_") then
      y = terrain_fn(x, z)
    elseif tag == "bottom" then
      y = world_bottom
    end
    local r, g, b, a = get_terrain_color(y, tag)
    table.insert(ground_vertices, {x, y, z, r, g, b, a})
  end
  for vi = 1, #water_vertices do
    water_vertices[vi][4] = nil
  end
  ground_mesh = lovr.graphics.newMesh(vertex_format, ground_vertices)
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

  pass:setColor(1, 1, 1)
  pass:draw(ground_mesh)

  pass:setColor(0x062cb8)
  pass:draw(water_mesh)

  pass:setWireframe(true)
  pass:setColor(0x022e0e)
  pass:draw(ground_mesh)
  pass:setColor(0x01186e)
  pass:draw(water_mesh)
  pass:setWireframe(false)
end