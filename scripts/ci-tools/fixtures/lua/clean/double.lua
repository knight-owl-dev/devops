-- Formatted per .stylua.toml. Annotated with a builtin type, so it passes only
-- when lua-language-server loads its builtin library.

---@param n integer
---@return integer
local function double(n)
  return n * 2
end

print(double(2))
