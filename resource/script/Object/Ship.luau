--!strict
-- Called by the engine for each new ship (Luau port of Object/Ship.lts):
-- an engine sound that follows its speed.

return {
  Init = function(ship: Object)
    local engine: Sound? = nil
    ship:AddScript({
      Update = function(_, self: Object): boolean
        local thrust = engine or Sound_PlayLooped("thruster/loop1.ogg", self, vector.create(0, 0, 0), 0, math.sqrt(self:GetRadius()))
        if not engine then
          thrust:RandomizePosition()
          engine = thrust
        end
        local output = self:GetSpeed() / 1000
        thrust:SetVolume(0.5 * math.clamp(output, 0, 1))
        thrust:SetPitch(1)
        return true
      end,
    })
  end,
}
