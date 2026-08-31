local function generate_terrain_vertices(size, subdivisions)
  local vertices = {}
  local step = size / (subdivisions - 1)
  local half = size / 2
  for z = -half, half - step + 0.001, step do
    for x = -half, half - step + 0.001, step do
      table.insert(vertices, {x, 0, z, "top"})
      table.insert(vertices, {x, 0, z + step, "top"})
      table.insert(vertices, {x + step, 0, z, "top"})
      table.insert(vertices, {x, 0, z + step, "top"})
      table.insert(vertices, {x + step, 0, z + step, "top"})
      table.insert(vertices, {x + step, 0, z, "top"})
    end
  end
  local function add_walls(x1, z1, x2, z2, label)
    table.insert(vertices, {x1, 0, z1, label})
    table.insert(vertices, {x1, 0, z1, "bottom"})
    table.insert(vertices, {x2, 0, z2, label})
    table.insert(vertices, {x1, 0, z1, "bottom"})
    table.insert(vertices, {x2, 0, z2, "bottom"})
    table.insert(vertices, {x2, 0, z2, label})
  end
  for i = -half, half - step + 0.001, step do
    add_walls(i, -half, i + step, -half, "edge_z_min")
    add_walls(i, half, i + step, half, "edge_z_min")
    add_walls(-half, i, -half, i + step, "edge_x_min")
    add_walls(half, i, half, i + step, "edge_x_min")
  end
  for z = -half, half - step + 0.001, step do
    for x = -half, half - step + 0.001, step do
      table.insert(vertices, {x, 0, z, "bottom"})
      table.insert(vertices, {x, 0, z + step, "bottom"})
      table.insert(vertices, {x + step, 0, z, "bottom"})
      table.insert(vertices, {x, 0, z + step, "bottom"})
      table.insert(vertices, {x + step, 0, z + step, "bottom"})
      table.insert(vertices, {x + step, 0, z, "bottom"})
    end
  end
  return vertices
end

local function generate_water_vertices(size, subdivisions)
  local vertices = {}
  local w_step = size / (subdivisions - 1)
  local half = size / 2
  for z = -half, half - w_step + 0.001, w_step do
    for x = -half, half - w_step + 0.001, w_step do
      table.insert(vertices, {x, 0, z})
      table.insert(vertices, {x, 0, z + w_step})
      table.insert(vertices, {x + w_step, 0, z})
      table.insert(vertices, {x, 0, z + w_step})
      table.insert(vertices, {x + w_step, 0, z + w_step})
      table.insert(vertices, {x + w_step, 0, z})
    end
  end
  return vertices
end

local world
local terrain_size = 150
local water_size = 160
local grid_subdivision = 40

local function raw_terrain_fn(x, z)
  local half = terrain_size / 2
  local seabed_depth = -8.0
  local falloff_start = 0.55
  local dist = math.max(math.abs(x) / half, math.abs(z) / half)
  local raw_y = 5 * (lovr.math.noise(x * 0.05, z * 0.05) - 0.5)

  if dist > falloff_start then
    local t = math.min(1.0, math.max(0.0, (dist - falloff_start) / (1.0 - falloff_start)))
    local smooth_t = t * t * (3 - 2 * t)
    return raw_y * (1 - smooth_t) + seabed_depth * smooth_t
  end
  return raw_y
end

local function raw_water_height(x, z, time)
  return math.sin(x * 0.5 + time) * 0.3 + math.cos(z * 0.4 + time * 0.8) * 0.3
end

local function get_triangle_height(x, z, size, subs, height_fn, time)
  local half = size / 2
  local step = size / (subs - 1)
  local lx = math.max(0, math.min((x + half) / step, subs - 1))
  local lz = math.max(0, math.min((z + half) / step, subs - 1))
  local x0, z0 = math.floor(lx), math.floor(lz)
  if x0 >= subs - 1 then
    x0 = subs - 2
  end
  if z0 >= subs -1 then
    z0 = subs - 2
  end

  local u, v = lx - x0, lz - z0
  local px0, pz0 = -half + x0 * step, -half + z0 * step
  local px1, pz1 = -half + (x0 + 1) * step, -half + (z0 + 1) * step
  local h00 = height_fn(px0, pz0, time)
  local h10 = height_fn(px1, pz0, time)
  local h01 = height_fn(px0, pz1, time)
  local h11 = height_fn(px1, pz1, time)
  
  if u + v <= 1.0 then
    return h00 + (h10 - h00) * u + (h01 - h00) * v
  else
    return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
  end
end

local function physical_water_height(x, z, time)
  return get_triangle_height(x, z, water_size, grid_subdivision, raw_water_height, time)
end

local function get_terrain_color(y, tag)
  if tag == "bottom" then
    return 0.12, 0.12, 0.15, 1.0
  elseif tag and tag:sub(1,5) == "edge_" then
    return 0.25, 0.22, 0.20, 1.0
  end

  if y > 6.0 then
    return 0.85, 0.88, 0.90, 1.0
  elseif y > 4.0 then
    return 0.50, 0.52, 0.55, 1.0
  elseif y > 0.5 then
    return 0.25, 0.65, 0.30, 1.0
  elseif y > -0.5 then
    return 0.80, 0.75, 0.55, 1.0
  elseif y > -3.0 then
    return 0.70, 0.65, 0.45, 1.0
  else
    return 0.30, 0.45, 0.55, 1.0
  end
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
    uniform float is_water;
    vec4 lovrmain() {
      vec3 dx = dFdx(worldPos);
      vec3 dy = dFdy(worldPos);
      vec3 faceNormal = normalize(cross(dx, dy));
      vec3 sunDirection = normalize(vec3(0.6, 1.0, 0.4));
      float diffuse = max(dot(faceNormal, sunDirection), 0.0);
      float light = 0.2 + (diffuse * 0.8);
      vec4 baseColor = vec4((Color.rgb * vertColor.rgb) * light, Color.a * vertColor.a);
      if (is_water > 0.5) {
        vec3 viewDir = normalize(cameraPos - worldPos);
        vec3 reflectDir = reflect(-sunDirection, faceNormal);
        float spec = pow(max(dot(viewDir, reflectDir), 0.0), 48.0);
        baseColor.rgb += vec3(0.7, 0.9, 1.0) * spec * 1.2;
        baseColor.a = 0.85;
      }
      if (fogDensity > 0.0) {
        float dist = distance(worldPos, cameraPos);
        float fogAmount = clamp(1.0 - exp(-dist * fogDensity), 0.0, 1.0);
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
  local raw_ground_vertices = generate_terrain_vertices(terrain_size, grid_subdivision)
  local raw_water_vertices = generate_water_vertices(water_size, grid_subdivision)
  local ground_vertices = {}
  for i = 1, #raw_ground_vertices, 3 do
    local v1 = raw_ground_vertices[i]
    local v2 = raw_ground_vertices[i + 1]
    local v3 = raw_ground_vertices[i + 2]

    local function get_y(v)
      if v[4] == "top" or (v[4] and v[4]:sub(1,5) == "edge_") then
        return raw_terrain_fn(v[1], v[3])
      elseif v[4] == "bottom" then
        return world_bottom
      end
      return 0
    end

    local y1, y2, y3 = get_y(v1), get_y(v2), get_y(v3)
    local avg_y = (y1+ y2 + y3) / 3.0
    local r, g, b, a = get_terrain_color(avg_y, v1[4])

    table.insert(ground_vertices, {v1[1], y1, v1[3], r, g, b, a})
    table.insert(ground_vertices, {v2[1], y2, v2[3], r, g, b, a})
    table.insert(ground_vertices, {v3[1], y3, v3[3], r, g, b, a})
  end
  local formatted_water_vertices = {}
  for i = 1, #raw_water_vertices do
    local v = raw_water_vertices[i]
    table.insert(formatted_water_vertices, {v[1], v[2], v[3], 1.0, 1.0, 1.0, 1.0})
  end
  ground_mesh = lovr.graphics.newMesh(vertex_format, ground_vertices)
  water_mesh = lovr.graphics.newMesh(vertex_format, formatted_water_vertices)
  world:newMeshCollider(ground_mesh)
  box_colliders = {}
end

function lovr.update(dt)
  local current_time = lovr.timer.getTime()
  if current_time % 1 < dt then
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
      local local_water_level = physical_water_height(x, z, current_time)
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
  local inside_water = math.abs(hx) <= half_bounds and math.abs(hz) <= half_bounds
  local wave_height = physical_water_height(hx, hz, current_time)
  local underwater = inside_water and (hy < wave_height)
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
  pass:setColor(0.06, 0.25, 0.8, 0.8)
  pass:draw(water_mesh)

  pass:setShader()
end