--!strict
-- Self-test fixture: raises a script error. bin/check expects a non-zero
-- exit status, which proves script errors are not swallowed.
local App = {}

function App.Initialize(self: any)
  error("planted script error")
end

return App
