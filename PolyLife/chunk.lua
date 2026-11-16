local Chunk = {}

local world_seed = 12345

local CHUNK_SIZE_X = 24
local CHUNK_SIZE_Y = 17
local CHUNK_SIZE_Z = 24
local voxel_scale = 3.0

local function get_voxel_index(x, y, z)
  if x < 1 or x > CHUNK_SIZE_X or y < 1 or y > CHUNK_SIZE_Y or z < 1 or z > CHUNK_SIZE_Z then
    return nil
  end

  return x + (y - 1) * CHUNK_SIZE_X + (z - 1) * CHUNK_SIZE_X * CHUNK_SIZE_Y
end

local function clamp01(v)
  return math.max(0.0, math.min(1.0, v))
end

local function smooth_step(t)
  t = clamp01(t)
  return t * t * (3.0 - 2.0 * t)
end

local function mix_color(a, b, t)
  t = smooth_step(t)

  return {
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
    a[3] + (b[3] - a[3]) * t
  }
end

function Chunk.get_terrain_color(x, y, z)
  local deep_rock = {0.30, 0.34, 0.36}
  local beach = {0.82, 0.69, 0.43}
  local grass = {0.20, 0.48, 0.20}
  local light_grass = {0.38, 0.62, 0.24}
  local high_grass = {0.55, 0.65, 0.31}
  local rock = {0.43, 0.42, 0.39}
  local pale_rock = {0.66, 0.64, 0.58}
  local color

  if y < 2.5 then
    color = mix_color(deep_rock, beach, (y + 2.0) / 4.5)
  elseif y < 4.5 then
    color = mix_color(beach, grass, (y - 2.5) / 2.0)
  elseif y < 8.0 then
    color = mix_color(grass, light_grass, (y - 4.5) / 3.5)
  elseif y < 11.0 then
    color = mix_color(light_grass, high_grass, (y - 8.0) / 3.0)
  elseif y < 15.0 then
    color = mix_color(high_grass, rock, (y - 11.0) / 4.0)
  else
    color = mix_color(rock, pale_rock, (y - 15.0) / 6.0)
  end

  local variation = (lovr.math.noise(x * 0.12, z * 0.12) - 0.5) * 0.12
  local shade = 1.0 + variation

  return clamp01(color[1] * shade), clamp01(color[2] * shade), clamp01(color[3] * shade)
end

function Chunk.vertex_interp(p1, p2, val1, val2)
  if math.abs(val1) < 0.00001 then return p1 end
  if math.abs(val2) < 0.00001 then return p2 end
  if math.abs(val1 - val2) < 0.00001 then return p1 end

  local mu = (0.0 - val1) / (val2 - val1)
  mu = math.max(0.0, math.min(1.0, mu))

  return {
    p1[1] + mu * (p2[1] - p1[1]),
    p1[2] + mu * (p2[2] - p1[2]),
    p1[3] + mu * (p2[3] - p1[3]),
  }
end

local function seeded_noise(x, z, scale, offset)
  return lovr.math.noise(x * scale + world_seed + offset, z * scale - world_seed - offset)
end

function Chunk:generate()
  local island_scale = 0.016
  local broad_scale = 0.015
  local medium_scale = 0.04
  local detail_scale = 0.08

  for z = 1, CHUNK_SIZE_Z do
    for y = 1, CHUNK_SIZE_Y do
      for x = 1, CHUNK_SIZE_X do
        local global_x = self.cx * 23 + (x - 1)
        local global_y = self.cy * 16 + (y - 1)
        local global_z = self.cz * 23 + (z - 1)

        local wx = global_x * voxel_scale
        local wy = (global_y - 16) * voxel_scale
        local wz = global_z * voxel_scale

        local island_noise = seeded_noise(wx, wz, island_scale, 0) * 0.75 + seeded_noise(wx, wz, island_scale * 2.1, 200) * 0.25
        local sea_level_noise = 0.42
        local beach_slope_width = 0.18
        local dist_from_coast = island_noise - sea_level_noise
        local coast_t = clamp01((dist_from_coast + beach_slope_width) / (beach_slope_width * 2.0))
        local beach_ramp = smooth_step(coast_t)
        local broad_hills = (seeded_noise(wx, wz, broad_scale, 100) - 0.5) * 8.0
        local medium_hills = (seeded_noise(wx, wz, medium_scale, 300) - 0.5) * 2.5
        local small_detail = (seeded_noise(wx, wz, detail_scale, 400) - 0.5) * 0.4
        local hill_mask = smooth_step(clamp01((coast_t - 0.5) / 0.5))
        local surface_hills = (broad_hills + medium_hills + small_detail) * hill_mask
        local deep_seabed = -4.0
        local max_land_height = 6.0
        local terrain_height = deep_seabed + (max_land_height - deep_seabed) * beach_ramp + surface_hills

        local density = terrain_height - wy
        local idx = get_voxel_index(x, y, z)

        if idx then self.voxel_data[idx] = density end
      end
    end
  end
end

function Chunk.new(cx, cy, cz)
  local self = {}

  self.cx = cx
  self.cy = cy
  self.cz = cz

  self.voxel_data = {}

  self.mesh = nil
  self.physics_mesh = nil
  self.collider = nil

  return self
end

return Chunk