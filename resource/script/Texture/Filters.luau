--!strict
-- Image filters on the GPU (Luau port of Texture/Filters.lts). Each takes
-- its input texture last and returns a new HDR texture; the ...Out
-- variants render into a texture you pass instead. Vector parameters
-- also take a number, meaning that value in every channel.

local Filters = {}

type Vec = vector | number

local function vec3(v: Vec): vector
  return if type(v) == "number" then vector.create(v, v, v) else v
end

-- One shader instance per post shader, created on first use
local shaders: { [string]: ShaderInstance } = {}
local function shader(name: string): ShaderInstance
  local s = shaders[name]
  if not s then
    s = ShaderInstance_Create(Shader_Create("identity.jsl", `post/{name}.jsl`))
    shaders[name] = s
  end
  return s
end

local function like(texture: Texture): Texture
  return Texture2D_CreateHDR(texture:GetWidth(), texture:GetHeight())
end

local function rcpFrame(texture: Texture): vector
  return vector.create(1 / texture:GetWidth(), 1 / texture:GetHeight())
end

-- The blur and median kernels' radius in pixels
local function radius(variance: number): number
  return math.floor(2 * variance)
end

local function render(out: Texture, s: ShaderInstance): Texture
  out:GenerateFromShader(s)
  return out
end

function Filters.AddOut(aMult: number, bMult: number, a: Texture, b: Texture, out: Texture): Texture
  local s = shader("add")
  s:SetTexture2D("texture1", a)
  s:SetTexture2D("texture2", b)
  s:SetFloat("weight1", aMult)
  s:SetFloat("weight2", bMult)
  return render(out, s)
end

function Filters.Add(aMult: number, bMult: number, a: Texture, b: Texture): Texture
  return Filters.AddOut(aMult, bMult, a, b, like(a))
end

local function blurOut(variance: number, delta: vector, texture: Texture, out: Texture): Texture
  local s = shader("blur")
  s:SetTexture2D("texture", texture)
  s:SetVec2("delta", delta)
  s:SetInt("radius", radius(variance))
  s:SetFloat("variance", variance)
  return render(out, s)
end

function Filters.BlurHOut(variance: number, texture: Texture, out: Texture): Texture
  return blurOut(variance, vector.create(1 / out:GetWidth(), 0), texture, out)
end

function Filters.BlurH(variance: number, texture: Texture): Texture
  return Filters.BlurHOut(variance, texture, like(texture))
end

function Filters.BlurVOut(variance: number, texture: Texture, out: Texture): Texture
  return blurOut(variance, vector.create(0, 1 / out:GetHeight()), texture, out)
end

function Filters.BlurV(variance: number, texture: Texture): Texture
  return Filters.BlurVOut(variance, texture, like(texture))
end

function Filters.Blur(variance: number, texture: Texture): Texture
  return Filters.BlurH(variance, Filters.BlurV(variance, texture))
end

local function circleMinMax(isMin: boolean, variance: number, texture: Texture): Texture
  local s = shader("circleminmax")
  s:SetTexture2D("texture", texture)
  s:SetInt("mode", if isMin then 0 else 1)
  s:SetInt("radius", radius(variance))
  s:SetVec2("rcpFrame", rcpFrame(texture))
  s:SetFloat("variance", variance)
  return render(like(texture), s)
end

-- The largest value within the radius (a grayscale dilate)
function Filters.CircleMax(variance: number, texture: Texture): Texture
  return circleMinMax(false, variance, texture)
end

-- The smallest value within the radius (a grayscale erode)
function Filters.CircleMin(variance: number, texture: Texture): Texture
  return circleMinMax(true, variance, texture)
end

-- A per-channel Bezier tone curve through five control points
function Filters.ColorGradeOut(p1: vector, p2: vector, p3: vector, p4: vector, p5: vector, texture: Texture,
  out: Texture): Texture
  local s = shader("colorgradebezier")
  s:SetTexture2D("texture", texture)
  s:SetVec3("p1", p1)
  s:SetVec3("p2", p2)
  s:SetVec3("p3", p3)
  s:SetVec3("p4", p4)
  s:SetVec3("p5", p5)
  return render(out, s)
end

function Filters.ColorGrade(p1: vector, p2: vector, p3: vector, p4: vector, p5: vector, texture: Texture): Texture
  return Filters.ColorGradeOut(p1, p2, p3, p4, p5, texture, like(texture))
end

function Filters.EdgeDetectOut(texture: Texture, out: Texture): Texture
  local s = shader("edgedetect")
  s:SetTexture2D("texture", texture)
  s:SetVec2("rcpFrame", rcpFrame(texture))
  return render(out, s)
end

function Filters.EdgeDetect(texture: Texture): Texture
  return Filters.EdgeDetectOut(texture, like(texture))
end

function Filters.ExpMap(power: number, mult: number, texture: Texture): Texture
  local s = shader("expmap")
  s:SetTexture2D("texture", texture)
  s:SetFloat("power", power)
  s:SetFloat("mult", mult)
  return render(like(texture), s)
end

function Filters.GainOut(amount: number, texture: Texture, out: Texture): Texture
  return Filters.AddOut(amount, 0, texture, texture, out)
end

function Filters.Gain(amount: number, texture: Texture): Texture
  return Filters.GainOut(amount, texture, like(texture))
end

function Filters.LevelsOut(lower: Vec, upper: Vec, texture: Texture, out: Texture): Texture
  local s = shader("levels")
  s:SetTexture2D("texture", texture)
  s:SetVec3("lower", vec3(lower))
  s:SetVec3("upper", vec3(upper))
  return render(out, s)
end

function Filters.Levels(lower: Vec, upper: Vec, texture: Texture): Texture
  return Filters.LevelsOut(lower, upper, texture, like(texture))
end

-- constant + coefficient * value
function Filters.Linear(constant: Vec, coefficient: Vec, texture: Texture): Texture
  local s = shader("linear")
  s:SetTexture2D("texture", texture)
  s:SetVec3("constant", vec3(constant))
  s:SetVec3("mult", vec3(coefficient))
  return render(like(texture), s)
end

function Filters.Invert(texture: Texture): Texture
  return Filters.Linear(1, -1, texture)
end

function Filters.Median(variance: number, texture: Texture): Texture
  local s = shader("median")
  s:SetTexture2D("texture", texture)
  s:SetInt("radius", radius(variance))
  s:SetVec2("rcpFrame", rcpFrame(texture))
  s:SetFloat("variance", variance)
  return render(like(texture), s)
end

local function pair(name: string, a: Texture, b: Texture, out: Texture): Texture
  local s = shader(name)
  s:SetTexture2D("texture1", a)
  s:SetTexture2D("texture2", b)
  return render(out, s)
end

function Filters.Max(a: Texture, b: Texture): Texture
  return pair("max", a, b, like(a))
end

function Filters.Min(a: Texture, b: Texture): Texture
  return pair("min", a, b, like(a))
end

function Filters.MultiplyOut(a: Texture, b: Texture, out: Texture): Texture
  return pair("multiply", a, b, out)
end

function Filters.Multiply(a: Texture, b: Texture): Texture
  return Filters.MultiplyOut(a, b, like(a))
end

function Filters.PowerOut(power: Vec, texture: Texture, out: Texture): Texture
  local s = shader("power")
  s:SetTexture2D("texture", texture)
  s:SetVec3("power", vec3(power))
  return render(out, s)
end

function Filters.Power(power: Vec, texture: Texture): Texture
  return Filters.PowerOut(power, texture, like(texture))
end

-- Scaled by 'factor' with bicubic sampling
function Filters.Resample(factor: number, texture: Texture): Texture
  local s = shader("samplecubic")
  local out = Texture2D_CreateHDR(math.floor(factor * texture:GetWidth()), math.floor(factor * texture:GetHeight()))
  s:SetTexture2D("texture", texture)
  s:SetVec2("frame", vector.create(texture:GetWidth(), texture:GetHeight()))
  return render(out, s)
end

function Filters.SaturateOut(mult: number, texture: Texture, out: Texture): Texture
  local s = shader("saturate")
  s:SetTexture2D("texture", texture)
  s:SetFloat("mult", mult)
  return render(out, s)
end

function Filters.Saturate(mult: number, texture: Texture): Texture
  return Filters.SaturateOut(mult, texture, like(texture))
end

function Filters.VignetteOut(hardness: number, opacity: number, texture: Texture, out: Texture): Texture
  local s = shader("vignette")
  s:SetTexture2D("texture", texture)
  s:SetFloat("hardness", hardness)
  s:SetFloat("opacity", opacity)
  return render(out, s)
end

function Filters.Vignette(hardness: number, opacity: number, texture: Texture): Texture
  return Filters.VignetteOut(hardness, opacity, texture, like(texture))
end

-- A painterly look: downsample, erode, then grade
function Filters.Artistic(texture: Texture): Texture
  return Filters.ColorGrade(
    vector.create(0.00, 0.00, 0.00),
    vector.create(0.25, 0.25, 0.25),
    vector.create(0.50, 0.75, 0.50),
    vector.create(1.25, 1.00, 0.75),
    vector.create(2.00, 1.00, 1.00),
    Filters.CircleMin(4, Filters.Resample(1 / 8, texture)))
end

return Filters
