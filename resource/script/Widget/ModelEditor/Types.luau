--!strict
-- Data shared by the model editor's widgets (Luau port of
-- Widget/ModelEditor/Types.lts).

export type Options = { symmetryX: boolean, symmetryY: boolean, symmetryZ: boolean }
export type Piece = { center: vector, scale: vector, bevel: number, model: Model }
export type ModelT = { pieces: { Piece } }

return {}
