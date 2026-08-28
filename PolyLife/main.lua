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

local world
local terrain_size = 150
local water_size = 160

local function terrain_fn(x, z)
  local half = terrain_size / 2
  local seabed_depth = -8.0
  local falloff_start = 0.55
  local nx = math.abs(x) / half
  local nz = math.abs(z) / half
  local dist = math.max(nx, nz)
  local raw_y = 5 * (lovr.math.noise(x * 0.05, z * 0.05) - 0.5)

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

  if y > 7.0 then
    return 0.55, 0.55, 0.58, 1.0
  elseif y > 5.0 then
    return 0.45, 0.30, 0.18, 1.0
  elseif y > 0.4 then
    return 0.18, 0.55, 0.22, 1.0
  elseif y > -0.2 then
    return 0.45, 0.30, 0.18, 1.0
  elseif y > -2.0 then
    return 0.76, 0.70, 0.50, 1.0
  else
    return 0.15, 0.25, 0.30, 1.0
  end
end

local function get_wave_height(x, z, time)
  return math.sin(x * 0.5 + time) * 0.3 + math.cos(z * 0.4 + time * 0.8) * 0.3
end

local master_shader
local ground_mesh
local water_mesh
local box_colliders

function lovr.load()
  local world_bottom = -9
  world = lovr.physics.newWorld({
    allowSleep = false
  })
  world:setGravity(0, -9.81, 0)
  master_shader = lovr.graphics.newShader([[
    out vec3 worldPos;
    out vec4 vertColor;
    uniform float time;
    uniform float is_water;
    vec4 lovrmain() {
      vec3 pos = VertexPosition.xyz;
      
      if (is_water > 0.5) {
        pos.y += sin(pos.x * 0.5 + time) * 0.3 + cos(pos.z * 0.4 + time * 0.8) * 0.3;
      }
      worldPos = (Transform * vec4(pos, 1.0)).xyz;
      vertColor = VertexColor;
      return Projection * View * vec4(worldPos, 1.0);
    }
  ]], [[
    in vec3 worldPos;
    in vec4 vertColor;
    uniform float fogDensity;
    uniform vec3 cameraPos;
    vec4 lovrmain() {
      vec4 baseColor = Color * vertColor;
      if (fogDensity > 0.0) {
        float dist = distance(worldPos, cameraPos);
        float fogAmount = 1.0 - exp(-dist * fogDensity);
        fogAmount = clamp(fogAmount, 0.0, 1.0);
        vec3 fogColor = vec3(0.02, 0.12, 0.25);
        return vec4(mix(baseColor.rgb, fogColor, fogAmount), baseColor.a);
      }
      return baseColor;
    }
  ]])
  local vertex_format = {
    { 'VertexPosition', 'vec3' },
    { 'VertexColor', 'vec4' }
  }
  local raw_ground_vertices = grid(terrain_size, 100)
  local raw_water_vertices = grid(water_size, 120)
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
  local formatted_water_vertices = {}
  for vi = 1, #raw_water_vertices do
    local x, y, z = raw_water_vertices[vi][1], raw_water_vertices[vi][2], raw_water_vertices[vi][3]
    table.insert(formatted_water_vertices, {x, y, z, 1.0, 1.0, 1.0, 1.0})
  end
  ground_mesh = lovr.graphics.newMesh(vertex_format, ground_vertices)
  water_mesh = lovr.graphics.newMesh(vertex_format, formatted_water_vertices)
  world:newTerrainCollider(terrain_size, terrain_fn)
  box_colliders = {}
end

function lovr.update(dt)
  local current_time = lovr.timer.getTime()
  if lovr.timer.getTime() % 1 < dt then
    local collider = world:newBoxCollider(
      lovr.math.randomNormal(terrain_size / 10, 0),
      lovr.math.randomNormal(1, 20),
      lovr.math.randomNormal(terrain_size / 10, 0),
      1)
    collider:setMass(lovr.math.random(1, 10))
    table.insert(box_colliders, collider)
  end
  local fluid_density = 5.0
  local gravity = 9.81
  local box_size = 1.0
  local half_bounds = water_size / 2
  for _, collider in ipairs(box_colliders) do
    local x, y, z = collider:getPosition()
    local bottom = y - (box_size / 2)
    if math.abs(x) <= half_bounds and math.abs(z) <= half_bounds then
      local local_water_level = get_wave_height(x, y, current_time)
      if bottom < local_water_level then
        local submerged = math.min(1.0, (local_water_level - bottom) / box_size)
        local bouyant_force = submerged * (box_size^3) * fluid_density * gravity
        collider:applyForce(0, bouyant_force, 0)

        local vx, vy, vz = collider:getLinearVelocity()
        local drag = 2.0 * submerged
        collider:applyForce(-vx * drag, -vy * drag, -vz * drag)

        local ax, ay, az = collider:getAngularVelocity()
        collider:applyTorque(-ax * drag, -ay * drag, -az * drag)
      end
    end
  end
  world:update(dt)
end

function lovr.draw(pass)
  local hx, hy, hz = lovr.headset.getPosition()
  local current_time = lovr.timer.getTime()
  local half_bounds = water_size / 2
  local inside_water_borders = math.abs(hx) <= half_bounds and math.abs(hz) <= half_bounds
  local wave_height_at_camera = get_wave_height(hx, hz, current_time)
  local underwater = inside_water_borders and (hy < wave_height_at_camera)
  if underwater then
    lovr.graphics.setBackgroundColor(0.02, 0.10, 0.25)
  else
    lovr.graphics.setBackgroundColor(0x02b2f2)
  end
  pass:setShader(master_shader)
  pass:send('time', current_time)
  pass:send('cameraPos', {hx, hy, hz})
  pass:send('fogDensity', underwater and 0.15 or 0.0)

  pass:send('is_water', 0.0)
  for _, collider in ipairs(box_colliders) do
    local x, y, z, angle, ax, ay, az = collider:getPose()
    local mass = collider:getMass()
    if mass < 5.0 then
      pass:setColor(0.6, 0.4, 0.2)
    else
      pass:setColor(0.3, 0.3, 0.3)
    end
    pass:cube(x, y, z, 1, angle, ax, ay, az)
  end

  pass:setColor(1, 1, 1)
  pass:draw(ground_mesh)

  pass:send('is_water', 1.0)
  pass:setColor(0.04, 0.17, 0.72, 0.7)
  pass:draw(water_mesh)

  pass:setWireframe(true)
  pass:send('is_water', 0.0)
  pass:setColor(0x022e0e)
  pass:draw(ground_mesh)

  pass:send('is_water', 1.0)
  pass:setColor(0x01186e)
  pass:draw(water_mesh)
  pass:setWireframe(false)

  pass:setShader()
end