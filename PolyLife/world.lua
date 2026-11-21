local Chunk = require "chunk"
local Messages = require "messages"
local World = {}

local world
local voxel_scale = 3.0
local water_size = 280
local grid_subdivision = 120

local CHUNK_CELLS_XZ = 23
local CHUNK_WORLD_SIZE = CHUNK_CELLS_XZ * voxel_scale

local LOAD_RADIUS = 2
local UNLOAD_RADIUS = 3

local last_player_chunk_x = nil
local last_player_chunk_z = nil

local rebuild_queue = {}
local rebuild_queue_set = {}
local generated_chunks = {}
local generation_queue = {}
local generation_queue_count = 0

local CHUNKS_PER_FRAME = 1

local master_shader = nil
local water_mesh = nil
local box_colliders = {}
local player_collider = nil
local player_contact_boxes = {}

local function get_chunk_key(cx, cy, cz)
  return cx .. ":" .. cy .. ":" .. cz
end

local function queue_chunk(cx, cy, cz)
  local key = get_chunk_key(cx, cy, cz)

  if generated_chunks[key] or generation_queue[key] then
    return
  end

  generation_queue[key] = {cx = cx, cy = cy, cz = cz, key = key}
  generation_queue_count = generation_queue_count + 1
end

local function process_generation_queue()
  if not player_collider then return end

  local px, py, pz = player_collider:getPosition()
  local pcx = math.floor(px / CHUNK_WORLD_SIZE)
  local pcz = math.floor(pz / CHUNK_WORLD_SIZE)

  for _ = 1, CHUNKS_PER_FRAME do
    local best_request = nil
    local best_key = nil
    local best_distance = math.huge

    for key, request in pairs(generation_queue) do
      local dx = request.cx - pcx
      local dz = request.cz - pcz

      if math.abs(dx) > LOAD_RADIUS or math.abs(dz) > LOAD_RADIUS then
        generation_queue[key] = nil
        generation_queue_count = generation_queue_count - 1
      else
        local distance = dx * dx + dz * dz

        if distance < best_distance then
          best_distance = distance
          best_request = request
          best_key = key
        end
      end
    end

    if not best_request then
      break
    end

    if not best_key then
      break
    end

    generation_queue[best_key] = nil
    generation_queue_count = generation_queue_count - 1

    local chunk = Chunk.new(best_request.cx, best_request.cy, best_request.cz)
    chunk:generate()
    chunk:buildMesh(world)

    generated_chunks[best_key] = chunk
  end
end

local function unload_chunk(key)
  local chunk = generated_chunks[key]

  if not chunk then
    return
  end

  if chunk.collider then
    chunk.collider:destroy()
  end

  generated_chunks[key] = nil
end

local function update_chunk_streaming()
  if not player_collider then
    return
  end

  local px, py, pz = player_collider:getPosition()

  local player_chunk_x = math.floor(px / CHUNK_WORLD_SIZE)
  local player_chunk_z = math.floor(pz / CHUNK_WORLD_SIZE)

  if player_chunk_x == last_player_chunk_x and player_chunk_z == last_player_chunk_z then
    return
  end

  last_player_chunk_x = player_chunk_x
  last_player_chunk_z = player_chunk_z

  for cz = player_chunk_z - LOAD_RADIUS, player_chunk_z + LOAD_RADIUS do
    for cx = player_chunk_x - LOAD_RADIUS, player_chunk_x + LOAD_RADIUS do
      for cy = 0, 1 do
        queue_chunk(cx, cy, cz)
      end
    end
  end

  for key, chunk in pairs(generated_chunks) do
    local dx = chunk.cx - player_chunk_x
    local dz = chunk.cz - player_chunk_z

    if math.abs(dx) > UNLOAD_RADIUS or math.abs(dz) > UNLOAD_RADIUS then
      unload_chunk(key)
    end
  end
end

function World.isChunkReadyAt(x, z)
  local cx = math.floor(x / CHUNK_WORLD_SIZE)
  local cz = math.floor(z / CHUNK_WORLD_SIZE)

  for cy = 0, 1 do
    local key = get_chunk_key(cx, cy, cz)

    if not generated_chunks[key] then
      return false
    end
  end

  return true
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

function World.physical_water_height(x, z, time)
  return get_triangle_height(x, z, water_size, grid_subdivision, raw_water_height, time)
end

function World.load()
  world = lovr.physics.newWorld({
    allowSleep = false
  })

  world:setGravity(0, -9.81, 0)

  world:setCallbacks({
    contact = function (a, b, contact)
      if not player_collider then return end

      local other = nil

      if a == player_collider then
        other = b
      elseif b == player_collider then
        other = a
      end

      if other then
        for _, box in ipairs(box_colliders) do
          if box == other then
            player_contact_boxes[box] = true
            break
          end
        end
      end
    end
  })

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
        vec3 totalLight = lightX * 0.30 + lightY * 0.30 + lightZ * 0.30 + sunLight;
        totalLight = clamp(totalLight, 0.0, 1.0);
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
end

local function queue_chunk_rebuild(chunk)
  if rebuild_queue_set[chunk.key] then
    return
  end

  rebuild_queue_set[chunk.key] = chunk
  table.insert(rebuild_queue, chunk)
end

local function process_rebuild_queue()
  local chunks_per_frame = 1

  for _ = 1, chunks_per_frame do
    local chunk = table.remove(rebuild_queue, 1)

    if not chunk then
      break
    end

    if rebuild_queue_set[chunk.key] == chunk then
      rebuild_queue_set[chunk.key] = nil
    end

    if generated_chunks[chunk.key] == chunk then
      chunk:buildMesh(world)
    end
  end
end

local function modify_terrain_cube(cx, cy, cz, radius, amount)
  for _, chunk in pairs(generated_chunks) do
    local changed = chunk:editVoxel(cx, cy, cz, radius, amount)

    if changed then
      queue_chunk_rebuild(chunk)
    end
  end
end

function World.digTerrain(x, y, z, radius)
  modify_terrain_cube(x, y, z, radius, -3.0)
end

function World.addTerrain(x, y, z, radius)
  modify_terrain_cube(x, y, z, radius, 3.0)
end

function World.getTerrainTarget(ox, oy, oz, dx, dy, dz, max_distance)
  local target = nil

  local ex = ox + dx * max_distance
  local ey = oy + dy * max_distance
  local ez = oz + dz * max_distance

  world:raycast(ox, oy, oz, ex, ey, ez, nil, function(collider, shape, hx, hy, hz, nx, ny, nz)
    if collider == player_collider then
      return 1.0
    end

    for _, box in ipairs(box_colliders) do
      if collider == box then
        return 1.0
      end
    end

    target = {
      x = hx,
      y = hy,
      z = hz,
      nx = nx,
      ny = ny,
      nz = nz,
    }

    return 0.0
  end)

  return target
end

function World.canEditTerrain(x, y, z, radius)
  if player_collider then
    local px, py, pz = player_collider:getPosition()

    local dx = x - px
    local dy = y - py
    local dz = z - pz

    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    if distance < radius + 0.7 then
      return false
    end
  end

  for _, box in ipairs(box_colliders) do
    local bx, by, bz = box:getPosition()

    local dx = x - bx
    local dy = y - by
    local dz = z - bz

    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    if distance < radius + 0.9 then
      return false
    end
  end

  return true
end

function World.createPlayerCollider(x, y, z)
  local cx = math.floor(x / CHUNK_WORLD_SIZE)
  local cz = math.floor(z / CHUNK_WORLD_SIZE)

  for cy = 0, 1 do
    local key = get_chunk_key(cx, cy, cz)

    if not generated_chunks[key] then
      local chunk = Chunk.new(cx, cy, cz)
      chunk:generate()
      chunk:buildMesh(world)

      generated_chunks[key] = chunk
    end

    if generation_queue[key] then
      generation_queue[key] = nil
      generation_queue_count = generation_queue_count - 1
    end
  end

  player_collider = world:newCapsuleCollider(x, y, z, 0.4, 1.0)
  player_collider:setMass(75.0)

  return player_collider
end

function World.isPlayerGrounded()
  if not player_collider then return false end
  local x, y, z = player_collider:getPosition()
  local grounded = false
  world:raycast(x, y, z, x, y - 0.6, z, nil, function(collider, shape, hx, hy, hz, nx, ny, nz, tri, fraction)
    if collider == player_collider then
      return 1.0
    end
    if ny > 0.5 then
      grounded = true
      return 0.0
    end
    return 1.0
  end)

  return grounded
end

local function raycastTerrain(x, y, z, distance)
  local hit = nil

  world:raycast(x, y, z, x, y - distance, z, nil, function(collider, shape, hx, hy, hz, nx, ny, nz)
    if collider == player_collider then
      return 1.0
    end

    for _, box in ipairs(box_colliders) do
      if collider == box then
        return 1.0
      end
    end

    hit = {
      x = hx,
      y = hy,
      z = hz,
      nx = nx,
      ny = ny,
      nz = nz
    }

    return 0.0
  end)

  return hit
end

local function findBoxGround(x, y, z)
  local offsets = {
    {0, 0},
    {-0.4, -0.4},
    {0.4, -0.4},
    {-0.4, 0.4},
    {0.4, 0.4},
  }

  local heights = {}

  for _, offset in ipairs(offsets) do
    local hit = raycastTerrain(x + offset[1], y + 2.0, z + offset[2], 5.0)

    if not hit then
      return nil
    end

    if hit.ny < 0.85 then
      return nil
    end

    table.insert(heights, hit.y)
  end

  local min_height = heights[1]
  local max_height = heights[1]

  for i = 2, #heights do
    min_height = math.min(min_height, heights[i])
    max_height = math.max(max_height, heights[i])
  end

  if max_height - min_height > 0.25 then
    return nil
  end

  return heights[1]
end

function World.spawnBoxes(ox, oy, oz, dx, dy, dz)
  if not player_collider then return end

  local max_distance = 20.0
  local target = nil

  local ex = ox + dx * max_distance
  local ey = oy + dy * max_distance
  local ez = oz + dz * max_distance

  world:raycast(ox, oy, oz, ex, ey, ez, nil, function(collider, shape, hx, hy, hz, nx, ny, nz)
    if collider == player_collider then
      return 1.0
    end

    for _, box in ipairs(box_colliders) do
      if collider == box then
        return 1.0
      end
    end

    target = {
      x = hx,
      y = hy,
      z = hz,
    }

    return 0.0
  end)

  if not target then
    Messages.show("No terrain found!")
    return
  end

  local ground_y = findBoxGround(target.x, target.y, target.z)

  if not ground_y then
    Messages.show("Cannot spawn box here! Surface is not suitable.")
    return
  end

  local spawn_y = ground_y + 0.55

  local px, py, pz = player_collider:getPosition()

  local dxp = target.x - px
  local dzp = target.z - pz

  if dxp * dxp + dzp * dzp < 1.5 * 1.5 then
    Messages.show("Too close to player!")
    return
  end

  local collider = world:newBoxCollider(target.x, spawn_y, target.z, 1)
  local mass = lovr.math.random(1, 40)
  collider:setMass(mass)
  collider:setFriction(0.9)
  collider:setRestitution(0.0)
  collider:setLinearDamping(0.15)
  collider:setAngularDamping(0.5)
  table.insert(box_colliders, collider)
end

function World.getMovementMultiplier(dx, dz, strength)
  if not player_collider then return 1.0 end

  local multiplier = 1.0

  for box in pairs(player_contact_boxes) do
    local mass = box:getMass()
    local ratio = mass / math.max(strength, 1.0)
    local box_multiplier = math.max(0.25, 1.0 / (1.0 + ratio * 1.5))
    multiplier = math.min(multiplier, box_multiplier)
    box:applyForce(dx * 180.0, 0, dz * 180.0)
  end

  return multiplier
end

function World.update(dt, current_time)
  local fluid_density = 5.0
  local gravity = 9.81
  local box_size = 1.0
  local half_bounds = water_size / 2

  for _, collider in ipairs(box_colliders) do
    local x, y, z = collider:getPosition()
    local bottom = y - 0.5

    if math.abs(x) <= half_bounds and math.abs(z) <= half_bounds then
      local local_water_level = World.physical_water_height(x, z, current_time)

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

  if player_collider then
    local px, py, pz = player_collider:getPosition()
    local p_bottom = py - 0.9

    if math.abs(px) <= half_bounds and math.abs(pz) <= half_bounds then
        local water_lvl = World.physical_water_height(px, pz, current_time)

        if p_bottom < water_lvl then
            local submerged = math.min(1.0, (water_lvl - p_bottom) / 1.8)
            local bouyant_force = submerged * 75.0 * 1.2 * gravity
            player_collider:applyForce(0, bouyant_force, 0)

            if lovr.system.isKeyDown('space') then
                player_collider:applyForce(0, 450.0, 0)
            end

            local vx, vy, vz = player_collider:getLinearVelocity()
            local drag = 3.5 * submerged
            player_collider:applyForce(-vx * drag, -vy * drag, -vz * drag)
        end
    end
  end

  player_contact_boxes = {}
  process_rebuild_queue()
  update_chunk_streaming()
  process_generation_queue()
  world:update(dt)
end

function World.draw(pass, current_time, cameraPos, underwater, edit_target, editing_mode, edit_radius)
  pass:setShader(master_shader)
  pass:send('time', current_time)
  pass:send('cameraPos', cameraPos)
  pass:send('fogDensity', underwater and 0.15 or 0.0)
  pass:send('is_water', 0.0)

  for _, collider in ipairs(box_colliders) do
    local x, y, z, angle, ax, ay, az = collider:getPose()
    local mass = collider:getMass()

    if mass < 15.0 then
      pass:setColor(0.70, 0.45, 0.25)
    else
      pass:setColor(0.35, 0.35, 0.35)
    end
    pass:cube(x, y, z, 1, angle, ax, ay, az)
  end

  pass:setColor(1, 1, 1, 1)

  for _, chunk in pairs(generated_chunks) do
    if chunk.mesh then
      pass:draw(chunk.mesh)
    end
  end

  pass:send('is_water', 1.0)
  pass:setColor(1, 1, 1, 0.55)
  pass:draw(water_mesh)

  pass:setShader()

  if editing_mode and edit_target then
    local can_edit = World.canEditTerrain(edit_target.x, edit_target.y, edit_target.z, edit_radius)

    if can_edit then
      pass:setColor(0.2, 1.0, 0.3, 0.3)
    else
      pass:setColor(1.0, 0.1, 0.1, 0.3)
    end

    pass:cube(edit_target.x, edit_target.y, edit_target.z, edit_radius * 2)
    pass:setColor(1, 1, 1, 1)
  end
end

function World.getWaterSize() return water_size end

return World