--!strict
-- Prints the primes below 1000 and exits (Luau port of App/prime.lts).

local function isPrime(n: number): boolean
  for i = 2, n - 1 do
    if n % i == 0 then
      return false
    end
  end
  return true
end

return {
  Initialize = function()
    for i = 2, 999 do
      if isPrime(i) then
        print(i)
      end
    end
  end,
}
