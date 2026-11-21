local MC = require "marching_tables"
local Chunk = {}

local world_seed = 12345

local CHUNK_SIZE_X = 24
local CHUNK_SIZE_Y = 17
local CHUNK_SIZE_Z = 24
local CHUNK_CELLS_X = 23
local CHUNK_CELLS_Y = 16
local CHUNK_CELLS_Z = 23
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
        local global_x = self.cx * CHUNK_CELLS_X + (x - 1)
        local global_y = self.cy * CHUNK_CELLS_Y + (y - 1)
        local global_z = self.cz * CHUNK_CELLS_Z + (z - 1)

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
  setmetatable(self, { __index = Chunk})

  self.cx = cx
  self.cy = cy
  self.cz = cz
  self.key = cx .. ":" .. cy .. ":" .. cz

  self.voxel_data = {}

  self.mesh = nil
  self.physics_mesh = nil
  self.collider = nil

  return self
end

function Chunk:editVoxel(center_x, center_y, center_z, radius, amount)
  local changed = false

  for z = 1, CHUNK_SIZE_Z do
    for y = 1, CHUNK_SIZE_Y do
      for x = 1, CHUNK_SIZE_X do
        local global_x = self.cx * CHUNK_CELLS_X + (x - 1)
        local global_y = self.cy * CHUNK_CELLS_Y + (y - 1)
        local global_z = self.cz * CHUNK_CELLS_Z + (z - 1)

        local wx = global_x * voxel_scale
        local wy = (global_y - 16) * voxel_scale
        local wz = global_z * voxel_scale

        if math.abs(wx - center_x) <= radius
        and math.abs(wy - center_y) <= radius
        and math.abs(wz - center_z) <= radius then
          local idx = get_voxel_index(x, y, z)

          if idx then self.voxel_data[idx] = self.voxel_data[idx] + amount end

          changed = true
        end
      end
    end
  end

  return changed
end

function Chunk:buildMesh(physics_world)
  local render_vertices = {}
  local physics_vertices = {}

  local corner_offsets = {
    {0, 0, 0},
    {1, 0, 0},
    {1, 0, 1},
    {0, 0, 1},
    {0, 1, 0},
    {1, 1, 0},
    {1, 1, 1},
    {0, 1, 1}
  }

  for z = 1, CHUNK_CELLS_Z do
    for y = 1, CHUNK_CELLS_Y do
      for x = 1, CHUNK_CELLS_X do
        local densities = {}
        local positions = {}

        for i = 1, 8 do
          local vx = x + corner_offsets[i][1]
          local vy = y + corner_offsets[i][2]
          local vz = z + corner_offsets[i][3]

          local idx = get_voxel_index(vx, vy, vz)
          assert(idx, "Invalid voxel index")
          densities[i] = self.voxel_data[idx]

          local global_x = self.cx * CHUNK_CELLS_X + (vx - 1)
          local global_y = self.cy * CHUNK_CELLS_Y + (vy - 1)
          local global_z = self.cz * CHUNK_CELLS_Z + (vz - 1)

          positions[i] = {
            global_x * voxel_scale,
            (global_y - 16) * voxel_scale,
            global_z * voxel_scale
          }
        end

        local cube_index = 0
        if densities[1] > 0 then cube_index = cube_index + 1 end
        if densities[2] > 0 then cube_index = cube_index + 2 end
        if densities[3] > 0 then cube_index = cube_index + 4 end
        if densities[4] > 0 then cube_index = cube_index + 8 end
        if densities[5] > 0 then cube_index = cube_index + 16 end
        if densities[6] > 0 then cube_index = cube_index + 32 end
        if densities[7] > 0 then cube_index = cube_index + 64 end
        if densities[8] > 0 then cube_index = cube_index + 128 end

        if cube_index ~= 0 and cube_index ~= 255 then
          local tris = MC.tri_table[cube_index + 1]

          if tris then
            local edge_vertices = {}

            for e = 0, 11 do
              local edge_info = MC.edge_to_vertices[e]

              if edge_info then
                local c1 = edge_info[1] + 1
                local c2 = edge_info[2] + 1
                edge_vertices[e] = Chunk.vertex_interp(positions[c1], positions[c2], densities[c1], densities[c2])
              end
            end

            for i = 1, #tris, 3 do
              local e1 = tris[i]

              if e1 == -1 or not e1 then break end
              local e2 = tris[i + 1]
              local e3 = tris[i + 2]
              local pt1 = edge_vertices[e1]
              local pt2 = edge_vertices[e2]
              local pt3 = edge_vertices[e3]

              if pt1 and pt2 and pt3 then
                table.insert(physics_vertices, pt1)
                table.insert(physics_vertices, pt2)
                table.insert(physics_vertices, pt3)

                local avg_x = (pt1[1] + pt2[1] + pt3[1]) / 3.0
                local avg_y = (pt1[2] + pt2[2] + pt3[2]) / 3.0
                local avg_z = (pt1[3] + pt2[3] + pt3[3]) / 3.0
                local r, g, b = Chunk.get_terrain_color(avg_x, avg_y, avg_z)

                for _, pt in ipairs({pt1, pt3, pt2}) do
                  table.insert(render_vertices, {pt[1], pt[2], pt[3], r, g, b, 1.0})
                end
              end
            end
          end
        end
      end
    end
  end

  local new_ground_mesh = nil
  local new_physics_mesh = nil
  local new_ground_collider = nil

  if #render_vertices > 0 then
    local color_format = {
      { 'VertexPosition', 'vec3' },
      { 'VertexColor', 'vec4' }
    }

    local pos_format = {
      { 'VertexPosition', 'vec3' }
    }

    new_ground_mesh = lovr.graphics.newMesh(color_format, render_vertices)
    new_physics_mesh = lovr.graphics.newMesh(pos_format, physics_vertices)
    new_ground_collider = physics_world:newMeshCollider(new_physics_mesh)
  end

  local old_collider = self.collider

  self.mesh = new_ground_mesh
  self.physics_mesh = new_physics_mesh
  self.collider = new_ground_collider

  if old_collider then
    old_collider:destroy()
  end
end

return Chunk