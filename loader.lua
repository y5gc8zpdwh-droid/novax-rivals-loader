local OWNER = "y5gc8zpdwh-droid"
local BRANCH = "main"
local MODULE_REPO = "novax-rivals-modules"
local HttpService = game:GetService("HttpService")

local function cacheToken()
  return tostring(math.floor(os.clock() * 1000000))
end

local function resolveModuleRef()
  local api = ("https://api.github.com/repos/%s/%s/git/ref/heads/%s?t=%s"):format(OWNER, MODULE_REPO, BRANCH, cacheToken())
  local ok, result = pcall(function()
    return game:HttpGet(api, true)
  end)
  if ok and type(result) == "string" and result ~= "" then
    local okJson, data = pcall(function()
      return HttpService:JSONDecode(result)
    end)
    local sha = okJson and type(data) == "table" and type(data.object) == "table" and data.object.sha
    if type(sha) == "string" and #sha >= 7 then
      return sha
    end
  end
  return BRANCH
end

local MODULE_REF = resolveModuleRef()
local MODULE_BASE = ("https://raw.githubusercontent.com/%s/%s/%s"):format(OWNER, MODULE_REPO, MODULE_REF)

local compiler = loadstring or load
if type(compiler) ~= "function" then
  error("NovaX loader: loadstring/load is not available")
end

local function fetch(path)
  path = tostring(path or ""):gsub("^/+", "")
  if path == "" then
    error("NovaX loader: empty path")
  end
  local url = MODULE_BASE .. "/" .. path .. "?t=" .. cacheToken()
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
  ModuleRef = MODULE_REF,
  ModuleRepo = MODULE_REPO,
  ModuleBase = MODULE_BASE,
  Manifest = manifest,
  Load = runSource,
})
