local MC = require "marching_tables"

local chunk_size = 32
local chunk_height = 32
local voxel_data = {}

local function get_voxel_index(x, y, z)
  if x < 1 or x > chunk_size or y < 1 or y > chunk_height or z < 1 or z > chunk_size then
    return nil
  end
  return x * (y * chunk_size) + (z * chunk_size * chunk_height)
end

local function generate_chunk_data()
  for z = 1, chunk_size do
    for y = 1, chunk_height do
      for x = 1, chunk_size do
        local wx, wy, wz = x * 0.5, y * 0.5, z * 0.5
        local noise_val = lovr.math.noise(wx * 0.1, wy * 0.15, wz * 0.1) * 8.0
        local surface_level = 16.0
        local density = (surface_level - y) + noise_val
        local idx = get_voxel_index(x, y, z)
        voxel_data[idx] = density
      end
    end
  end
end

local function create_uniform_grid(size, subs)
  local step = size / (subs - 1)
  local half = size / 2
  local pts = {}
  for z = 1, subs do
    pts[z] = {}
    for x = 1, subs do
      pts[z][x] = {-half + (x - 1) * step, -half + (z - 1) * step}
    end
  end
  return pts
end

local function generate_water_vertices(size, subdivisions)
  local vertices = {}
  local pts = create_uniform_grid(size, subdivisions)
  for z = 1, subdivisions - 1 do
    for x = 1, subdivisions - 1 do
      local p00 = pts[z][x]
      local p01 = pts[z+1][x]
      local p10 = pts[z][x+1]
      local p11 = pts[z+1][x+1]

      table.insert(vertices, {p00[1], 0, p00[2]})
      table.insert(vertices, {p01[1], 0, p01[2]})
      table.insert(vertices, {p10[1], 0, p10[2]})
      table.insert(vertices, {p10[1], 0, p10[2]})
      table.insert(vertices, {p01[1], 0, p01[2]})
      table.insert(vertices, {p11[1], 0, p11[2]})
    end
  end
  return vertices
end

local world
local terrain_size = 150
local water_size = 160
local grid_subdivision = 90

local function raw_water_height(x, z, time)
  return math.sin(x * 0.5 + time) * 0.4 +
         math.cos(z * 0.4 + time * 0.8) * 0.4 +
         math.sin((x - z) * 1.2 + time * 1.5) * 0.15
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

  if y > 5.0 then
    return 0.85, 0.88, 0.90, 1.0
  elseif y > 3.0 then
    return 0.50, 0.52, 0.55, 1.0
  elseif y > 0.5 then
    return 0.35, 0.70, 0.30, 1.0
  elseif y > -1.0 then
    return 0.85, 0.80, 0.55, 1.0
  elseif y > -4.0 then
    return 0.70, 0.65, 0.45, 1.0
  else
    return 0.25, 0.45, 0.50, 1.0
  end
end

local master_shader
local water_mesh
local box_colliders

function lovr.load()
  local world_bottom = -9
  world = lovr.physics.newWorld({
    allowSleep = false
  })
  world:setGravity(0, -9.81, 0)
  generate_chunk_data()
  master_shader = lovr.graphics.newShader([[
    out vec3 worldPos;
    out vec4 vertColor;
    uniform float time;
    uniform float is_water;
    vec4 lovrmain() {
      vec3 pos = VertexPosition.xyz;
      if (is_water > 0.5) {
        float wave = sin(pos.x * 0.5 + time) * 0.4;
        wave += cos(pos.z * 0.4 + time * 0.8) * 0.4;
        wave += sin((pos.x - pos.z) * 1.2 + time * 1.5) * 0.15;
        pos.y += wave;
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
      if (is_water < 0.5) {
        vec3 lightX = mix(vec3(0.18, 0.22, 0.30), vec3(0.35, 0.30, 0.25), faceNormal.x * 0.5 + 0.5);
        vec3 lightY = mix(vec3(0.12, 0.12, 0.18), vec3(0.45, 0.50, 0.55), faceNormal.y * 0.5 + 0.5);
        vec3 lightZ = mix(vec3(0.15, 0.20, 0.28), vec3(0.32, 0.35, 0.28), faceNormal.z * 0.5 + 0.5);
        vec3 sunDir = normalize(vec3(0.8, 0.7, 0.4));
        float sunDot = dot(faceNormal, sunDir);
        float sunWrapped = pow(sunDot * 0.5 + 0.5, 2.0);
        vec3 sunLight = vec3(0.9, 0.85, 0.7) * sunWrapped * 0.5;
        vec3 totalLight = lightX + lightY + lightZ + sunLight;
        vec4 baseColor = vec4((Color.rgb * vertColor.rgb) * totalLight, Color.a * vertColor.a);
        if (fogDensity > 0.0) {
          float dist = distance(worldPos, cameraPos);
          float fogAmount = clamp(1.0 - exp(-dist * fogDensity), 0.0, 1.0);
          vec3 fogColor = vec3(0.02, 0.12, 0.25);
          return vec4(mix(baseColor.rgb, fogColor, fogAmount), baseColor.a);
        }
        return baseColor;
      }
      vec3 sunDir = normalize(vec3(0.6, 0.7, 0.4));
      float sunDiff = max(dot(faceNormal, sunDir), 0.0);
      vec3 fillDir = normalize(vec3(-0.6, -0.5, -0.6));
      float fillDiff = max(dot(faceNormal, fillDir), 0.0);
      float skyDiff = max(faceNormal.y, 0.0);
      float facetLight = (sunDiff * 0.55) + (fillDiff * 0.35) + (skyDiff * 0.25) + 0.15;
      vec3 waterBase = vec3(0.05, 0.45, 0.65) * facetLight;
      vec3 viewDir = normalize(cameraPos - worldPos);
      vec3 reflectDir = reflect(-sunDir, faceNormal);
      float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
      vec3 sunSpecular = vec3(0.8, 0.95, 1.0) * spec * 1.0;
      float fresnel = pow(1.0 - max(dot(viewDir, faceNormal), 0.0), 2.5);
      vec3 skyReflect = vec3(0.3, 0.6, 0.85) * fresnel * 0.4;
      vec4 finalWater = vec4(waterBase + sunSpecular + skyReflect, 0.55);
      if (fogDensity > 0.0) {
        float dist = distance(worldPos, cameraPos);
        float fogAmount = clamp(1.0 - exp(-dist * fogDensity), 0.0, 1.0);
        vec3 fogColor = vec3(0.02, 0.12, 0.25);
        return vec4(mix(finalWater.rgb, fogColor, fogAmount), finalWater.a);
      }
      return finalWater;
    }
  ]])
  local vertex_format = {
    { 'VertexPosition', 'vec3' },
    { 'VertexColor', 'vec4' }
  }
  local raw_water_vertices = generate_water_vertices(water_size, grid_subdivision)
  local formatted_water_vertices = {}
  for i = 1, #raw_water_vertices do
    local v = raw_water_vertices[i]
    table.insert(formatted_water_vertices, {v[1], v[2], v[3], 1.0, 1.0, 1.0, 1.0})
  end
  water_mesh = lovr.graphics.newMesh(vertex_format, formatted_water_vertices)
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
      pass:setColor(0.70, 0.45, 0.25)
    else
      pass:setColor(0.35, 0.35, 0.35)
    end
    pass:cube(x, y, z, 1, angle, ax, ay, az)
  end

  pass:setColor(1, 1, 1)

  pass:send('is_water', 1.0)
  pass:setColor(1, 1, 1, 0.55)
  pass:draw(water_mesh)

  pass:setShader()
end