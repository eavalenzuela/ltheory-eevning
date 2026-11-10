--!strict
-- Self-test fixture: starts, prints and ends cleanly. bin/check expects
-- exit status 0.
local App = {}

function App.Initialize(self: any)
  print("selftest/pass: ok")
end

return App
