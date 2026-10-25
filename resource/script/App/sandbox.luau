--!strict
-- Prints the current time and date and exits (Luau port of
-- App/sandbox.lts, a scratchpad for news-style event text).

-- X was created in Y, during the Varxastian War, to give the ships
-- of Varxst a marginal advantage over the Preems.
--
-- On X, a ship belonging to faction Y was attacked and destroyed by
-- Z pirates in Zone W.  It is believed that the ship was carrying
-- approximately 1,000,000 cr worth of Valerite ore at the time.
--
-- [on date] [object description] [event description] [in location].
-- [additional details on object]

return {
  Initialize = function()
    local time = Time_Current()
    print(`{time.hour}:{time.minute}:{time.second} {time.month}/{time.day}/{time.year}`)
  end,
}
