local Chunk = {}

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

return Chunk