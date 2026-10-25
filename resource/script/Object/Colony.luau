--!strict
-- Called by the engine for each new colony (Luau port of Object/Colony.lts):
-- it slowly produces its goods.

return {
  Init = function(colony: Object)
    local goods = { Item_ProductionLabType(1, 5081, 1, 1, 1) }
    local tick = 0
    colony:AddScript({
      Update = function(_, self: Object): boolean
        tick += 1
        local rng = RNG_MTG(tick)
        for _, item in goods do
          if rng:Float() < 0.01 then
            self:AddItem(item, 1)
          end
        end
        return true
      end,
    })
  end,
}
