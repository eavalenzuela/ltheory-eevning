--!strict
-- The random streams moved to the Core; the prototype still asks for them
-- here.
local Rng = require("@lt/Core/Kernel/Rng")

export type Rng = Rng.Rng

return Rng
