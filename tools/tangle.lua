-- tools/tangle.lua : pandoc Lua filter implementing tangle for blueprint.md.
-- usage: pandoc blueprint.md --lua-filter=tools/tangle.lua
-- Mirrors tools/tangle.py: path= (re)creates, append= appends, first path= wins a truncate.
local seen = {}

local function ensure_dir(path)
  local dir = path:match("^(.*)/[^/]+$")
  if dir then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null") end
end

function CodeBlock(el)
  local path = el.attributes.path
  local append = el.attributes.append
  local target = path or append
  if not target then return nil end
  local mode = (path and not seen[target]) and "w" or "a"
  seen[target] = true
  ensure_dir(target)
  local f = io.open(target, mode)
  f:write(el.text)
  if not el.text:match("\n$") then f:write("\n") end
  f:close()
  return nil
end

return { { CodeBlock = CodeBlock } }