-- NovaX Entry Loader
-- Role: cleanup existing NovaX instance, then hand off to bootstrap.lua.

local OWNER = "y5gc8zpdwh-droid"
local BRANCH = "main"
local MONOREPO_REPO = "novax-rivals-modules"
local MONOREPO_PREFIX = "prepared-repos"
local USE_MONOREPO_REPOS = true

local REPOS = {
  Loader = "novax-loader",
  UI = "novax-ui",
  GUI = "novax-gui",

  CombatLoader = "novax-combat-loader",
  VisualLoader = "novax-visual-loader",
  MovementLoader = "novax-movement-loader",
  MiscLoader = "novax-misc-loader",
  FeatureLoader = "novax-feature-loader",

  AimLock = "novax-aimlock",
  TriggerBot = "novax-triggerbot",
  SilentAim = "novax-silentaim",

  ESP = "novax-esp",
  FOV = "novax-fov",
  FullBright = "novax-fullbright",
  NoFog = "novax-nofog",
  FPSUnlocker = "novax-fps-unlocker",
  FPSBoost = "novax-fpsboost",

  Speed = "novax-speed",
  Fly = "novax-fly",
  NoClip = "novax-noclip",
  InfJump = "novax-infjump",
  AntiVoid = "novax-antivoid",
  BunnyHop = "novax-bunnyhop",

  Configs = "novax-configs",
  NameChanger = "novax-name-changer",
  Teleport = "novax-teleport",
  BeggerFarm = "novax-beggerfarm",
  Backstab = "novax-backstab",
  NamesOrbit = "novax-names-orbit",
  AntiHit = "novax-antihit",
  ControlSpoof = "novax-control-spoof",
}

local globals = (getgenv and getgenv()) or nil
local BOOT_ID = ("nx-%d-%d"):format(math.floor(os.clock() * 1000000), math.random(100000, 999999999))

local function clearGlobalBootState()
  if not globals then
    return
  end

  globals.NX_XENO = nil
  globals.NX_XENO_LOADING = nil
  globals.NX_CLEANUP = nil
  globals.NX_GUI_READY = nil
  globals.NX_UI_WINDOW = nil
  globals.NX_UI_GUI = nil
  globals.NX_UI_ROOT = nil
  globals.NX_RUNTIME = nil
  globals.NX_BOOT_STAGE = nil
  globals.NX_BOOT_ERROR = nil
  globals.NX_BOOT_ID = nil
end

local function destroyGui(gui)
  if typeof(gui) == "Instance" and gui.Parent then
    pcall(function()
      gui:Destroy()
    end)
  end
end

local function isBootActive()
  return not globals or globals.NX_BOOT_ID == BOOT_ID
end

local function assertBootActive()
  if not isBootActive() then
    error("NovaX loader stopped: newer execution is active", 0)
  end
end

local reloadCount = globals and (tonumber(globals.NX_RELOAD_COUNT) or 0) or 0
if globals and (globals.NX_XENO == true or globals.NX_XENO_LOADING == true or type(globals.NX_CLEANUP) == "function") then
  local oldGui = globals.NX_UI_GUI
  if type(globals.NX_CLEANUP) == "function" then
    pcall(globals.NX_CLEANUP)
  end
  destroyGui(oldGui)
  clearGlobalBootState()
  task.wait(0.08)
end

if globals then
  globals.NX_BOOT_ID = BOOT_ID
  globals.NX_RELOAD_COUNT = reloadCount + 1
  globals.NX_XENO_LOADING = true
  globals.NX_BOOT_STAGE = "entry"
  globals.NX_BOOT_ERROR = nil
end

local HttpService = game:GetService("HttpService")
local compiler = loadstring or load
if type(compiler) ~= "function" then
  error("NovaX loader: loadstring/load is not available")
end

local repoRefs = {}
local moduleCache = {}
local nilResult = {}

local function cacheToken()
  return BOOT_ID .. "-" .. tostring(math.floor(os.clock() * 1000000))
end

local function resolveRepoRef(repo)
  assertBootActive()
  repo = tostring(repo or "")
  if repo == "" then
    error("NovaX loader: empty repo")
  end
  if repoRefs[repo] then
    return repoRefs[repo]
  end

  local api = ("https://api.github.com/repos/%s/%s/git/ref/heads/%s?t=%s"):format(OWNER, repo, BRANCH, cacheToken())
  local ok, result = pcall(function()
    return game:HttpGet(api, true)
  end)
  if ok and type(result) == "string" and result ~= "" then
    local okJson, data = pcall(function()
      return HttpService:JSONDecode(result)
    end)
    local sha = okJson and type(data) == "table" and type(data.object) == "table" and data.object.sha
    if type(sha) == "string" and #sha >= 7 then
      repoRefs[repo] = sha
      return sha
    end
  end

  repoRefs[repo] = BRANCH
  return BRANCH
end

local function normalizeLocalPath(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function getLocalRepoRoots()
  local roots = {}
  local seen = {}
  local function add(path)
    local normalized = normalizeLocalPath(path)
    if normalized ~= "" and not seen[normalized] then
      seen[normalized] = true
      roots[#roots + 1] = normalized
    end
  end

  if globals then
    add(globals.NX_LOCAL_REPO_ROOT)
    local workspaceRoot = normalizeLocalPath(globals.NX_LOCAL_WORKSPACE_ROOT)
    if workspaceRoot ~= "" then
      add(workspaceRoot .. "/github_push_workspace")
    end
  end

  add("github_push_workspace")
  add("./github_push_workspace")
  add("C:/Users/User/OneDrive/Neuer Ordner 1/github_push_workspace")
  return roots
end

local function fetchLocalRepo(repo, path)
  if type(readfile) ~= "function" then
    return nil, nil
  end

  for _, root in ipairs(getLocalRepoRoots()) do
    local filePath = root .. "/" .. repo .. "/" .. path
    local shouldRead = true
    if type(isfile) == "function" then
      local okFile, exists = pcall(isfile, filePath)
      shouldRead = okFile and exists == true
    end
    if shouldRead then
      local okRead, source = pcall(readfile, filePath)
      if okRead and type(source) == "string" and source ~= "" then
        return source, filePath
      end
    end
  end

  return nil, nil
end

local function fetchRemotePath(repo, path, ref)
  local base = ("https://raw.githubusercontent.com/%s/%s/%s"):format(OWNER, repo, ref or BRANCH)
  local lastErr, lastUrl = nil, nil

  for attempt = 1, 3 do
    assertBootActive()
    local url = base .. "/" .. path .. "?t=" .. cacheToken() .. "&a=" .. tostring(attempt)
    lastUrl = url
    local ok, result = pcall(function()
      return game:HttpGet(url, true)
    end)
    if ok and type(result) == "string" and result ~= "" and not result:match("^404:%s*Not Found") then
      return result, url
    end
    lastErr = result
    task.wait(0.12 * attempt)
  end

  return nil, lastUrl, lastErr
end

local function fetchMonorepoRepo(repo, path)
  local monorepoPath = MONOREPO_PREFIX .. "/" .. repo .. "/" .. path
  local ref = resolveRepoRef(MONOREPO_REPO)
  return fetchRemotePath(MONOREPO_REPO, monorepoPath, ref)
end

local function fetchRepo(repo, path)
  assertBootActive()
  repo = tostring(repo or "")
  path = tostring(path or "init.lua"):gsub("^/+", "")
  if repo == "" or path == "" then
    error("NovaX loader: invalid fetch target")
  end

  local localSource, localPath = fetchLocalRepo(repo, path)
  if localSource then
    return localSource, localPath
  end

  if USE_MONOREPO_REPOS then
    local monorepoSource, monorepoUrl, monorepoErr = fetchMonorepoRepo(repo, path)
    if monorepoSource then
      return monorepoSource, monorepoUrl
    end
    error("NovaX loader: failed to fetch " .. repo .. "/" .. path .. " from monorepo -> " .. tostring(monorepoErr))
  end

  local ref = resolveRepoRef(repo)
  local source, url, err = fetchRemotePath(repo, path, ref)
  if source then
    return source, url
  end

  error("NovaX loader: failed to fetch " .. repo .. "/" .. path .. " from " .. tostring(url) .. " -> " .. tostring(err))
end

local function runRepo(repo, path, ...)
  assertBootActive()
  repo = tostring(repo or "")
  path = tostring(path or "init.lua"):gsub("^/+", "")
  local cacheKey = repo .. "/" .. path
  local cached = moduleCache[cacheKey]
  if cached ~= nil then
    assertBootActive()
    if cached == nilResult then
      return nil
    end
    return cached
  end

  local source, url = fetchRepo(repo, path)
  assertBootActive()
  source = source:gsub("^\239\187\191", "")
  local chunk, err = compiler(source, "@" .. url)
  if not chunk then
    error("NovaX loader: syntax error in " .. repo .. "/" .. tostring(path) .. " -> " .. tostring(err))
  end
  assertBootActive()
  local result = chunk(...)
  assertBootActive()
  moduleCache[cacheKey] = result == nil and nilResult or result
  return result
end

local ctx = {
  Owner = OWNER,
  Branch = BRANCH,
  BootId = BOOT_ID,
  Monorepo = MONOREPO_REPO,
  MonorepoPrefix = MONOREPO_PREFIX,
  Repos = REPOS,
  LoadRepo = runRepo,
  FetchRepo = fetchRepo,
  IsBootActive = isBootActive,
  AssertBootActive = assertBootActive,
}

assertBootActive()
return runRepo(REPOS.Loader, "bootstrap.lua", ctx)
