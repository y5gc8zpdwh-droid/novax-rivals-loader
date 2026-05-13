local OWNER = "y5gc8zpdwh-droid"
local BRANCH = "main"
local MODULE_REPO = "novax-rivals-modules"
local MODULE_BASE = ("https://raw.githubusercontent.com/%s/%s/%s"):format(OWNER, MODULE_REPO, BRANCH)

local compiler = loadstring or load
if type(compiler) ~= "function" then
  error("NovaX loader: loadstring/load is not available")
end

local function fetch(path)
  path = tostring(path or ""):gsub("^/+", "")
  if path == "" then
    error("NovaX loader: empty path")
  end
  local url = MODULE_BASE .. "/" .. path .. "?t=" .. tostring(math.floor(os.clock() * 1000000))
  local ok, result = pcall(function()
    return game:HttpGet(url, true)
  end)
  if not ok or type(result) ~= "string" or result == "" then
    error("NovaX loader: failed to fetch " .. path .. " -> " .. tostring(result))
  end
  return result, url
end

local function runSource(path, ...)
  local source, url = fetch(path)
  source = source:gsub("^\239\187\191", "")
  local chunk, err = compiler(source, "@" .. url)
  if not chunk then
    error("NovaX loader: syntax error in " .. path .. " -> " .. tostring(err))
  end
  return chunk(...)
end

local manifest = runSource("manifest.lua")
if type(manifest) ~= "table" then
  error("NovaX loader: manifest.lua must return a table")
end

local entry = tostring(manifest.Entry or manifest.Bootstrap or "bootstrap/novax_xeno_optimized.lua")
return runSource(entry, {
  Owner = OWNER,
  Branch = BRANCH,
  ModuleRepo = MODULE_REPO,
  ModuleBase = MODULE_BASE,
  Manifest = manifest,
  Load = runSource,
})
