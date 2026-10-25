--!strict
-- The UI palette (Luau port of Colors.lts). Colors are vectors (r, g, b),
-- accepted wherever the engine takes a Color.

return {
  Bad = vector.create(1.0, 0.1, 0.1),
  Good = vector.create(0.25, 1.0, 0.25),
  Friendly = vector.create(0.25, 1.0, 0.25),
  Hostile = vector.create(1.0, 0.1, 0.01),
  Primary = vector.create(0.2, 0.7, 1.0),
  Secondary = vector.create(1.0, 0.3, 0.1),
  White = vector.create(1.0, 1.0, 1.0),
  DGray = vector.create(0.25, 0.25, 0.25),
  Gray = vector.create(0.5, 0.5, 0.5),
}
