--!strict
-- The kinds of star, as settings for the star shaders (star.jsl and
-- starcorona.jsl): colours of the surface, how it boils, its spots, its
-- corona, and what leaps off its limb.
--
-- These are the star presets saved with zk_dev_tools' star designer
-- (zero_kelvin/data/stars), unchanged. 'bodyRadius' was the disc's size
-- on that tool's canvas and is not used here: a star's size is its own.

export type StarType = {
  id: string,
  name: string,
  [string]: any,
}

local types: { StarType } = {
  { id = "m_dwarf", name = "Red dwarf", bodyRadius = 0.405, limbDarken = 0.05, colorHot = { 0.95, 0.55, 0.3 },
    colorMid = { 0.78, 0.28, 0.16 }, colorCool = { 0.45, 0.1, 0.05 }, granulationScale = 11.5,
    granulationOctaves = 6, granulationStrength = 0.82, granulationSpeed = 0.4, spotDensity = 4.5, spotSize = 0.1,
    spotIntensity = 0.92, spotColor = { 0.2, 0.06, 0.03 }, coronaRadius = 1.65, coronaStrength = 1.6,
    coronaColor = { 0.95, 0.45, 0.3 }, coronaFalloff = 1.7, coronaNoiseScale = 3.5, coronaNoiseStrength = 0.4,
    coronaPulseRate = 0.22, coronaPulseAmp = 0.35, breatheRate = 0.09, breatheAmp = 0.22, flareDensity = 16.0,
    flareIntensity = 0.55, flareExtent = 0.45, flareSpeed = 0.0, flareColor = { 1.0, 0.6, 0.4 },
    prominenceDensity = 3.5, prominenceIntensity = 0.45, prominenceExtent = 1.1, prominenceSpeed = 0.0,
    prominenceBend = 0.35, prominenceColor = { 0.95, 0.25, 0.12 }, seed = { 10.0, 20.0, 30.0 } },
  { id = "k_type", name = "Orange dwarf", bodyRadius = 0.405, limbDarken = 0.05, colorHot = { 1.0, 0.78, 0.5 },
    colorMid = { 0.95, 0.55, 0.22 }, colorCool = { 0.68, 0.25, 0.1 }, granulationScale = 11.0,
    granulationOctaves = 6, granulationStrength = 0.78, granulationSpeed = 0.45, spotDensity = 3.5, spotSize = 0.085,
    spotIntensity = 0.8, spotColor = { 0.28, 0.14, 0.07 }, coronaRadius = 1.84, coronaStrength = 2.0,
    coronaColor = { 1.0, 0.65, 0.3 }, coronaFalloff = 1.6, coronaNoiseScale = 3.5, coronaNoiseStrength = 0.4,
    coronaPulseRate = 0.2, coronaPulseAmp = 0.3, breatheRate = 0.08, breatheAmp = 0.2, flareDensity = 14.0,
    flareIntensity = 0.5, flareExtent = 0.5, flareSpeed = 0.0, flareColor = { 1.0, 0.85, 0.55 },
    prominenceDensity = 3.0, prominenceIntensity = 0.4, prominenceExtent = 1.2, prominenceSpeed = 0.0,
    prominenceBend = 0.35, prominenceColor = { 0.95, 0.35, 0.18 }, seed = { 40.0, 50.0, 60.0 } },
  { id = "sol", name = "Yellow dwarf", bodyRadius = 0.405, limbDarken = 0.049, colorHot = { 1.0, 0.97, 0.82 },
    colorMid = { 1.0, 0.8, 0.35 }, colorCool = { 0.85, 0.35, 0.1 }, granulationScale = 11.337,
    granulationOctaves = 6, granulationStrength = 0.801, granulationSpeed = 0.481, spotDensity = 3.01,
    spotSize = 0.076, spotIntensity = 0.738, spotColor = { 0.3, 0.18, 0.1 }, coronaRadius = 2.001,
    coronaStrength = 2.403, coronaColor = { 1.0, 0.78, 0.4 }, coronaFalloff = 1.568, coronaNoiseScale = 3.627,
    coronaNoiseStrength = 0.4, coronaPulseRate = 0.2, coronaPulseAmp = 0.3, breatheRate = 0.08, breatheAmp = 0.2,
    flareDensity = 14.0, flareIntensity = 0.5, flareExtent = 0.5, flareSpeed = 0.0, flareColor = { 1.0, 0.95, 0.75 },
    prominenceDensity = 3.0, prominenceIntensity = 0.4, prominenceExtent = 1.2, prominenceSpeed = 0.0,
    prominenceBend = 0.35, prominenceColor = { 0.95, 0.45, 0.2 }, seed = { 0.0, 0.0, 0.0 } },
  { id = "f_type", name = "Yellow-white star", bodyRadius = 0.405, limbDarken = 0.05, colorHot = { 1.0, 1.0, 0.95 },
    colorMid = { 1.0, 0.95, 0.78 }, colorCool = { 0.88, 0.72, 0.42 }, granulationScale = 10.5,
    granulationOctaves = 6, granulationStrength = 0.72, granulationSpeed = 0.55, spotDensity = 2.5, spotSize = 0.065,
    spotIntensity = 0.5, spotColor = { 0.45, 0.36, 0.18 }, coronaRadius = 2.1, coronaStrength = 2.6,
    coronaColor = { 1.0, 0.95, 0.8 }, coronaFalloff = 1.5, coronaNoiseScale = 3.7, coronaNoiseStrength = 0.4,
    coronaPulseRate = 0.18, coronaPulseAmp = 0.28, breatheRate = 0.07, breatheAmp = 0.18, flareDensity = 12.0,
    flareIntensity = 0.45, flareExtent = 0.55, flareSpeed = 0.0, flareColor = { 1.0, 0.98, 0.85 },
    prominenceDensity = 2.8, prominenceIntensity = 0.38, prominenceExtent = 1.3, prominenceSpeed = 0.0,
    prominenceBend = 0.35, prominenceColor = { 1.0, 0.6, 0.35 }, seed = { 70.0, 80.0, 90.0 } },
  { id = "a_type", name = "White star", bodyRadius = 0.405, limbDarken = 0.05, colorHot = { 0.95, 0.97, 1.0 },
    colorMid = { 0.8, 0.88, 1.0 }, colorCool = { 0.5, 0.6, 0.88 }, granulationScale = 10.0, granulationOctaves = 6,
    granulationStrength = 0.65, granulationSpeed = 0.6, spotDensity = 2.0, spotSize = 0.055, spotIntensity = 0.3,
    spotColor = { 0.45, 0.5, 0.65 }, coronaRadius = 2.25, coronaStrength = 2.8, coronaColor = { 0.85, 0.92, 1.0 },
    coronaFalloff = 1.45, coronaNoiseScale = 3.8, coronaNoiseStrength = 0.4, coronaPulseRate = 0.16,
    coronaPulseAmp = 0.25, breatheRate = 0.06, breatheAmp = 0.16, flareDensity = 11.0, flareIntensity = 0.42,
    flareExtent = 0.6, flareSpeed = 0.0, flareColor = { 0.95, 0.95, 1.0 }, prominenceDensity = 2.5,
    prominenceIntensity = 0.35, prominenceExtent = 1.35, prominenceSpeed = 0.0, prominenceBend = 0.35,
    prominenceColor = { 0.65, 0.75, 1.0 }, seed = { 100.0, 110.0, 120.0 } },
}

local StarTypes = { list = types, byId = {} :: { [string]: StarType } }
for _, t in types do
  StarTypes.byId[t.id] = t
end

return StarTypes
