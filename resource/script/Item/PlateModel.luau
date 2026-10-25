--!strict
-- Builds a metal model from plate-mesh boxes and attractor warps, for the
-- item generators.

export type Plate = { center: vector, scale: vector, bevel: number }
export type Attractor = { point: vector, strength: number }

return {
  Build = function(quality: number, plates: { Plate }, attractors: { Attractor }?): Model
    local mesh = PlateMesh_Create(quality)
    for _, plate in plates do
      mesh:Add(plate.center, plate.scale, vector.create(0, 0, 0), plate.bevel)
    end
    if attractors then
      for _, attractor in attractors do
        mesh:Add(Warp_AttractorPoint(attractor.point, attractor.strength))
      end
    end
    local built = mesh:GetMesh()
    Mesh_ComputeOcclusion(built)
    local model = Model_Create()
    model:Add(built, Material_Metal())
    return model
  end,
}
