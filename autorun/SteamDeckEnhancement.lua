-- Steam Deck Enhancement for Monster Hunter Wilds.
-- Rendering profile measured on Steam Deck. Only wildlife density is user-configurable.

local settings = json.load_file("SteamDeckEnhancement.json") or {}
if settings.KeepPercent == nil then settings.KeepPercent = 25 end
if settings.AnimalKeepPercent == nil then settings.AnimalKeepPercent = 25 end

local function saveSettings()
  json.dump_file("SteamDeckEnhancement.json", settings)
end

local DRAW_DISTANCE = 150.0
local FOLIAGE_SDF_DISTANCE = 60.0
local GRASS_CELL_DISTANCE = 100.0
local FOG_START_DISTANCE = 30.0
local FOG_DENSITY = 0.65
local CLOUD_STEPS_WHILE_TURNING = 32
local SHADOW_RESOLUTION = 218
local EFFECT_DENSITY = 0.465
local RESTORE_DELAY = 0.15
local FAR_DISTANCE = 100
local FAR_UPDATE_EVERY = 8

-- REFramework blocks io.open on DLLs, so a failed open means the DLL is loaded.
local ok, dll = pcall(io.open, "reframework/plugins/object_culling.dll", "rb")
local hasObjectCullingDll = not ok or dll ~= nil
if ok and dll then dll:close() end

local sceneManager = sdk.get_native_singleton("via.SceneManager")
local sceneManagerType = sdk.find_type_definition("via.SceneManager")
local stopwatch = sdk.find_type_definition("System.Diagnostics.Stopwatch"):get_method("GetTimestamp")

local function now()
  return stopwatch:call(nil) / 10000000
end

local function currentScene()
  return sdk.call_native_func(sceneManager, sceneManagerType, "get_CurrentScene()")
end

local state = {
  needsScan = true,
  cloudTurning = false,
  lastMove = 0,
  nextFog = 0,
  lastRenderer = 0,
  meshIndex = 1,
  sdfIndex = 1,
  grassIndex = 1,
  dirty = false,
  sdfDirty = false,
  grassDirty = false,
}

local foliageFlags = {
  "DrawShadowCast",
  "DrawFarCascadeShadowCast",
  "DrawSignedDistanceField",
  "DrawVoxelize",
  "DrawEnvmap",
}
local enabledFoliagePasses = {
  DrawShadowCast = true,
  DrawFarCascadeShadowCast = false,
  DrawSignedDistanceField = true,
  DrawVoxelize = false,
  DrawEnvmap = false,
}

local postFx = { ready = false }

local function applyPostFx()
  if not postFx.ready then return end

  postFx.tone:call("setVignetting", 2)
  postFx.tone:call("setTemporalAA", 5)
  postFx.tone:call("setTemporalAAAlgorithm", 1)
  postFx.tone:call("setTemporalJitterScale", 0)
  postFx.tone:call("set_Sharpness", 0.431)
  postFx.post:call("get_FilmGrain"):call("set_BlendRate", 0)
end

local function applyRendererProfile()
  local meshRenderer = sdk.get_native_singleton("via.render.MeshRenderer")
  local meshRendererType = sdk.find_type_definition("via.render.MeshRenderer")
  local speedTree = sdk.get_managed_singleton("via.speedtree.SpeedTreeMasterInstance")
  local speedTreeType = sdk.find_type_definition("via.speedtree.SpeedTreeMasterInstance")
  local renderer = sdk.get_native_singleton("via.render.Renderer")
  local rendererType = sdk.find_type_definition("via.render.Renderer")

  sdk.call_native_func(meshRenderer, meshRendererType, "set_LodBias", 1)
  sdk.call_native_func(speedTree, speedTreeType, "set_LodBias", 3)
  sdk.call_native_func(speedTree, speedTreeType, "set_StreamingMeshMinimumLod", 5)
  sdk.call_native_func(renderer, rendererType, "set_SmallObjectCullingRatio", 24.0)

  local lightRenderer = sdk.get_managed_singleton("via.render.LightRenderer")
  local lightRendererType = sdk.find_type_definition("via.render.LightRenderer")
  sdk.call_native_func(lightRenderer, lightRendererType, "set_ShadowResolution", SHADOW_RESOLUTION)
  sdk.call_native_func(lightRenderer, lightRendererType, "set_ShadowFilter", 0)

  local sampler = sdk.get_native_singleton("via.render.Sampler")
  local samplerType = sdk.find_type_definition("via.render.Sampler")
  sdk.call_native_func(sampler, samplerType, "set_Bias", 1.016)

  local giManager = sdk.get_native_singleton("via.render.GIPointCloudManager")
  local giManagerType = sdk.find_type_definition("via.render.GIPointCloudManager")
  sdk.call_native_func(giManager, giManagerType, "set_MinLod", 0)
  sdk.call_native_func(giManager, giManagerType, "set_LodBaseDistance", 8.0)

  local scene = currentScene()
  if not scene then return end

  local probes = scene:call("findComponents(System.Type)", sdk.typeof("via.render.DynamicProbeGI"))
  for i = 0, probes:get_size() - 1 do
    local probe = probes:get_element(i)
    probe:call("set_VoxelResolution", 0)
    probe:call("set_GIPRadianceVolumeStartLodNo", 5)
    probe:call("set_GIPRadianceVolumeStartDistanceEnable", true)
    probe:call("set_GIPRadianceVolumeStartDistance", 0.0)
    probe:call("set_TransparentProbeRayNum", 0)
    probe:call("set_VolumeNum", 7)
  end
end

local function initPostFx()
  local ok, result = pcall(function()
    local cameraManager = sdk.get_managed_singleton("app.CameraManager")
    local camera = cameraManager and cameraManager:call("get_PrimaryCamera")
    local gameObject = camera and camera:call("get_GameObject")
    if not gameObject then return false end

    postFx.tone = gameObject:call("getComponent(System.Type)", sdk.typeof("via.render.ToneMapping"))
    postFx.post = gameObject:call("getComponent(System.Type)", sdk.typeof("via.render.LDRPostProcess"))

    local graphicsManager = sdk.get_managed_singleton("app.GraphicsManager")
    postFx.display = graphicsManager and graphicsManager:call("get_DisplaySettings")
    if not (postFx.tone and postFx.post and postFx.display) then return false end

    applyRendererProfile()

    return true
  end)

  postFx.ready = ok and result == true
  if postFx.ready then applyPostFx() end

  return postFx.ready
end

local function isPlayer(gameObject)
  if not gameObject then return false end

  local transform = gameObject:call("get_Transform")
  local parent = transform and transform:call("get_Parent")
  while parent do
    local parentObject = parent:call("get_GameObject")
    if parentObject and parentObject:call("get_Name") == "MasterPlayer" then return true end
    parent = parent:call("get_Parent")
  end

  return false
end

local function scanFog(scene)
  local fogs = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Fog"))
  if not fogs or fogs:get_size() == 0 then return end

  state.fog = fogs:get_element(0)
  state.fogStart = state.fog:call("get_StartDistance")
  state.fogDensity = state.fog:call("get_Density")
  state.fog:call("set_StartDistance", FOG_START_DISTANCE)
  state.fog:call("set_Density", FOG_DENSITY)
end

local function scanClouds(scene)
  local clouds = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Cloudscape2"))
  if not clouds or clouds:get_size() == 0 then return end

  state.cloud = clouds:get_element(0)
  state.cloudSteps = state.cloud:call("get_CloudRaymarchNum")
  state.cloudTurning = false
end

local function scanFoliage(scene)
  local foliage = scene:call("findComponents(System.Type)", sdk.typeof("via.landscape.Foliage"))
  if not foliage then return end

  for i = 0, foliage:get_size() - 1 do
    local component = foliage:get_element(i)
    local gameObject = component:call("get_GameObject")
    local name = gameObject:call("get_Name")
    local position = gameObject:call("get_Transform"):call("get_Position")

    local entry = {
      component = component,
      original = {},
      x = position.x,
      y = position.y,
      z = position.z,
      sdfDisabled = false,
      draw = component:call("get_DrawDefault"),
      grassHidden = false,
    }

    for _, flag in ipairs(foliageFlags) do
      entry.original[flag] = component:call("get_" .. flag)
      component:call("set_" .. flag, enabledFoliagePasses[flag] and entry.original[flag] or false)
    end

    state.foliage[#state.foliage + 1] = entry
    if name:match("^st101_a08_.*Grass") or name:match("^st101_a08_Inaho") then
      state.grass[#state.grass + 1] = entry
    end
  end
end

local function scanMeshes(scene)
  if hasObjectCullingDll then return end

  local meshes = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Mesh"))
  if not meshes then return end

  for i = 0, meshes:get_size() - 1 do
    local component = meshes:get_element(i)
    local gameObject = component:call("get_GameObject")
    local name = gameObject and gameObject:call("get_Name") or ""
    local prefix = name:sub(1, 2)

    if (prefix == "sm" or prefix == "Gm" or prefix == "st" or prefix == "Pr") and not isPlayer(gameObject) then
      local position = gameObject:call("get_Transform"):call("get_Position")
      local index = #state.meshes + 1
      local isGrass = name:find("Grass") ~= nil or name:find("Inaho") ~= nil
      local isTent = name:sub(1, 5) == "Gm100"
      local culled = not isGrass and not isTent and index % 10 < 7
      local draw = isTent or component:call("get_DrawDefault")
      component:call("set_DrawDefault", draw and not culled)

      state.meshes[index] = {
        component = component,
        x = position.x,
        y = position.y,
        z = position.z,
        draw = draw,
        hidden = false,
        culled = culled,
      }
    end
  end
end

local function finishScan()
  state.needsScan = false
  state.dirty, state.sdfDirty, state.grassDirty = true, true, true
  state.meshIndex, state.sdfIndex, state.grassIndex = 1, 1, 1
  state.lastCamera, state.nextFog = nil, now() + 5
end

local function scanScene()
  state.cloud, state.cloudSteps, state.fog = nil, nil, nil
  state.foliage, state.grass, state.meshes = {}, {}, {}

  local scene = currentScene()
  if scene then
    scanFog(scene)
    scanClouds(scene)
    scanFoliage(scene)
    scanMeshes(scene)
  end

  finishScan()
end

local function distanceSquared(entry, point)
  local dx, dy, dz = entry.x - point.x, entry.y - point.y, entry.z - point.z
  return dx * dx + dy * dy + dz * dz
end

local function isHidden(entry, point, radius, margin, field)
  local distance = distanceSquared(entry, point)
  return entry[field] and distance > (radius - margin)^2 or distance > radius^2
end

local function updateMeshes(cameraPosition)
  if not state.dirty then return end

  local last = math.min(state.meshIndex + 95, #state.meshes)
  for index = state.meshIndex, last do
    local mesh = state.meshes[index]
    local hidden = isHidden(mesh, cameraPosition, DRAW_DISTANCE, 10, "hidden")
    if hidden ~= mesh.hidden then
      mesh.hidden = hidden
      mesh.component:call("set_DrawDefault", mesh.draw and not hidden and not mesh.culled)
    end
  end

  state.dirty = last ~= #state.meshes
  state.meshIndex = last + 1
end

local function updateFoliageSdf(cameraPosition)
  if not state.sdfDirty then return end

  local last = math.min(state.sdfIndex + 95, #state.foliage)
  for index = state.sdfIndex, last do
    local foliage = state.foliage[index]
    local disabled = isHidden(foliage, cameraPosition, FOLIAGE_SDF_DISTANCE, 5, "sdfDisabled")
    if disabled ~= foliage.sdfDisabled then
      foliage.sdfDisabled = disabled
      foliage.component:call("set_DrawSignedDistanceField", not disabled and foliage.original.DrawSignedDistanceField or false)
    end
  end

  state.sdfDirty = last ~= #state.foliage
  state.sdfIndex = last + 1
end

local function updateGrass(cameraPosition)
  if not state.grassDirty then return end

  local last = math.min(state.grassIndex + 95, #state.grass)
  for index = state.grassIndex, last do
    local patch = state.grass[index]
    local hidden = isHidden(patch, cameraPosition, GRASS_CELL_DISTANCE, 10, "grassHidden")
    if hidden ~= patch.grassHidden then
      patch.grassHidden = hidden
      patch.component:call("set_DrawDefault", patch.draw and not hidden)
    end
  end

  state.grassDirty = last ~= #state.grass
  state.grassIndex = last + 1
end

local function restoreScene()
  if state.cloud then state.cloud:call("set_CloudRaymarchNum", state.cloudSteps) end
  if state.fog then
    state.fog:call("set_StartDistance", state.fogStart)
    state.fog:call("set_Density", state.fogDensity)
  end

  for _, foliage in ipairs(state.foliage or {}) do
    for flag, original in pairs(foliage.original) do
      foliage.component:call("set_" .. flag, original)
    end
  end
  for _, mesh in ipairs(state.meshes or {}) do
    mesh.component:call("set_DrawDefault", mesh.draw)
    mesh.hidden, mesh.culled = false, false
  end

  state.cloudTurning = false
end

local function refreshRendererProfile(seconds)
  if seconds - state.lastRenderer < 10 then return end

  applyRendererProfile()
  state.lastRenderer = seconds
end

local function didCameraRotate(rotation)
  local previous = state.rotation
  state.rotation = rotation
  if not previous then return false end

  local dot = math.abs(rotation.x * previous.x + rotation.y * previous.y
    + rotation.z * previous.z + rotation.w * previous.w)

  return 2 * math.acos(math.min(1, dot)) > 0.003
end

local function updateCloudSteps(turning)
  if not state.cloud or turning == state.cloudTurning then return end

  state.cloud:call("set_CloudRaymarchNum", turning and CLOUD_STEPS_WHILE_TURNING or state.cloudSteps)
  state.cloudTurning = turning
end

local function markCameraMoved(position)
  local previous = state.lastCamera
  local moved = not previous or (position.x - previous.x)^2 + (position.y - previous.y)^2
    + (position.z - previous.z)^2 > 4
  if not moved then return end

  state.dirty, state.sdfDirty, state.grassDirty = true, true, true
  state.meshIndex, state.sdfIndex, state.grassIndex = 1, 1, 1
end

local function allChunksUpdated()
  return state.meshIndex > #state.meshes and state.sdfIndex > #state.foliage
    and state.grassIndex > #state.grass
end

local function refreshFog(seconds)
  if not state.fog or seconds < state.nextFog then return end

  state.fog:call("set_StartDistance", FOG_START_DISTANCE)
  state.fog:call("set_Density", FOG_DENSITY)
  state.nextFog = seconds + 5
end

re.on_application_entry("WaitForVblank", function()
  local seconds = now()

  if state.needsScan then scanScene() end
  if not postFx.ready then initPostFx() end
  refreshRendererProfile(seconds)
  if postFx.ready then postFx.tone:call("setVignetting", 2) end

  local camera = sdk.get_primary_camera()
  if not camera then return end

  local transform = camera:call("get_GameObject"):call("get_Transform")
  local rotation, position = transform:call("get_Rotation"), transform:call("get_Position")
  if didCameraRotate(rotation) then state.lastMove = seconds end

  local turning = seconds - state.lastMove < RESTORE_DELAY
  updateCloudSteps(turning)
  markCameraMoved(position)
  updateMeshes(position)
  updateFoliageSdf(position)
  updateGrass(position)

  if allChunksUpdated() then
    state.lastCamera = { x = position.x, y = position.y, z = position.z }
  end

  refreshFog(seconds)
end)

-- Time-of-day lights only. Monster and effect lights are not touched.
local timeOfDayPatterns = { "^[Mm]orning", "^[Dd]ay_", "^[Ee]vening", "^[Nn]ight" }
local timeOfDayLights, lightsDisabled, shadowsDisabled = {}, {}, {}
local lightFrame = 0

local function isTimeOfDayLight(name)
  for _, pattern in ipairs(timeOfDayPatterns) do
    if name:find(pattern) then return true end
  end

  return false
end

local function restoreLights()
  for light in pairs(lightsDisabled) do pcall(light.call, light, "set_Enabled", true) end
  for light in pairs(shadowsDisabled) do pcall(light.call, light, "set_ShadowEnable", true) end
  lightsDisabled, shadowsDisabled, timeOfDayLights = {}, {}, {}
end

local function scanLights()
  restoreLights()

  local scene = currentScene()
  if not scene then return end

  for _, typeName in ipairs({ "via.render.SpotLight", "via.render.PointLight" }) do
    local lights = scene:call("findComponents(System.Type)", sdk.typeof(typeName))
    for i = 0, lights:get_size() - 1 do
      local component = lights:get_element(i)
      local gameObject = component:call("get_GameObject")
      local name = gameObject and gameObject:call("get_Name") or ""
      if isTimeOfDayLight(name) then
        timeOfDayLights[#timeOfDayLights + 1] = {
          component = component,
          isFill = name:find("_Fill") ~= nil,
        }
      end
    end
  end
end

local function trimLights()
  for _, light in ipairs(timeOfDayLights) do
    local component = light.component
    local ok, intensity = pcall(component.call, component, "get_Intensity")
    if ok and intensity == 0 and not lightsDisabled[component] and component:call("get_Enabled") then
      component:call("set_Enabled", false)
      lightsDisabled[component] = true
    end
    if light.isFill and not shadowsDisabled[component] and component:call("get_ShadowEnable") then
      component:call("set_ShadowEnable", false)
      shadowsDisabled[component] = true
    end
  end
end

re.on_frame(function()
  lightFrame = lightFrame + 1
  if lightFrame % 600 == 1 then
    pcall(scanLights)
  elseif lightFrame % 600 == 60 then
    trimLights()
  end
end)

-- Small monsters, wildlife and distant non-quest bosses share one enemy-update hook.
local enemyManager, missionManager, player
local playerX, playerY, playerZ
local enemyFrameCount, lastStageType = 0, nil
local decidedEnemies, enemyInfo = {}, {}
local smallMonsterAccumulator, wildlifeAccumulator = 0, 0

local function keepSmallMonster(percent)
  smallMonsterAccumulator = smallMonsterAccumulator + percent
  if smallMonsterAccumulator >= 100 then
    smallMonsterAccumulator = smallMonsterAccumulator - 100

    return true
  end

  return false
end

local function keepWildlife(percent)
  wildlifeAccumulator = wildlifeAccumulator + percent
  if wildlifeAccumulator >= 100 then
    wildlifeAccumulator = wildlifeAccumulator - 100

    return true
  end

  return false
end

local function scanPlayer()
  enemyFrameCount = enemyFrameCount + 1
  if enemyFrameCount % 300 ~= 1 then return end

  enemyInfo, player = {}, nil
  local ok, gameObject = pcall(function()
    return currentScene():call("findGameObject(System.String)", "MasterPlayer")
  end)
  player = ok and gameObject or nil

  enemyManager = enemyManager or sdk.get_managed_singleton("app.EnemyManager")
  missionManager = missionManager or sdk.get_managed_singleton("app.MissionManager")
end

local function updatePlayerPosition()
  if not player then return end

  local ok, position = pcall(function()
    return player:call("get_Transform"):call("get_Position")
  end)
  if ok and position then
    playerX, playerY, playerZ = position.x, position.y, position.z
  else
    player = nil
  end
end

re.on_frame(function()
  scanPlayer()
  updatePlayerPosition()
end)

local function enemyContextFrom(args)
  local character = sdk.to_managed_object(args[2])
  local context = character and character:get_field("_Context")
  local enemy = context and context:get_field("_Em")

  return character, context, enemy
end

local function isQuestTarget(enemy)
  local browser = enemy:get_Browser()
  local key = browser and browser:get_ThisTargetAccessKey()

  return key ~= nil and missionManager:isQuestTarget(key)
end

local function resetEnemyDecisions(stageType)
  decidedEnemies, enemyInfo = {}, {}
  smallMonsterAccumulator, wildlifeAccumulator = 0, 0
  lastStageType = stageType
end

local function thinSmallMonster(enemy, context)
  local isSmallMonster = enemy:get_IsZako()
  local isWildlife = enemy:get_IsAnimal()
  if not isSmallMonster and not isWildlife then return end
  if isQuestTarget(enemy) then return end

  local identifier = enemy:get_EmID()
  local remove = false
  if isSmallMonster and identifier ~= 38 then
    remove = not keepSmallMonster(settings.KeepPercent)
  end
  if isWildlife and not (identifier and identifier >= 57 and identifier <= 77) then
    remove = not keepWildlife(settings.AnimalKeepPercent)
  end
  if remove then enemyManager:requestRemove(context, 0, true) end
end

local function trackBoss(enemy, character, address)
  local info = enemyInfo[address]
  if info then return info end

  info = { isBoss = false, checkedAt = -1000 }
  enemyInfo[address] = info
  if enemy:get_IsBoss() and not isQuestTarget(enemy) then
    info.isBoss = true
    info.character = character
  end

  return info
end

local function updateBossDistance(info)
  if enemyFrameCount - info.checkedAt < 30 then return end

  local ok, position = pcall(function()
    return info.character:call("get_GameObject"):call("get_Transform"):call("get_Position")
  end)
  local distance = (position and (position.x - playerX)^2 + (position.y - playerY)^2
    + (position.z - playerZ)^2) or 0
  info.isFar = ok and distance > FAR_DISTANCE^2
  info.checkedAt = enemyFrameCount
end

sdk.hook(sdk.find_type_definition("app.EnemyCharacter"):get_method("update()"), function(args)
  if not playerX or not enemyManager or not missionManager then return end

  local stageType = missionManager:getActiveStageType()
  if stageType ~= lastStageType then resetEnemyDecisions(stageType) end

  local address = sdk.to_int64(args[2])
  local character, context, enemy = enemyContextFrom(args)
  if not enemy then return end

  if not decidedEnemies[address] then
    decidedEnemies[address] = true
    thinSmallMonster(enemy, context)
  end

  local boss = trackBoss(enemy, character, address)
  if not boss.isBoss then return end

  updateBossDistance(boss)
  if boss.isFar and (enemyFrameCount + address // 16) % FAR_UPDATE_EVERY ~= 0 then

    return sdk.PreHookResult.SKIP_ORIGINAL
  end
end, function(retval) return retval end)

local function thinEffects(effectContainer)
  if hasObjectCullingDll or not effectContainer then return end

  local ok, players = pcall(function() return effectContainer:call("getAllPlayers") end)
  if not ok or not players then return end

  local found, items = pcall(function() return players:get_field("_items") end)
  if not found or not items then return end

  for i = 0, #items - 1 do
    pcall(function()
      local quality = items[i]:call("get_QualitySettings")
      if quality then
        quality:call("set_SpawnVolumeRatio", quality:call("get_SpawnVolumeRatio") * EFFECT_DENSITY)
      end
    end)
  end
end

pcall(sdk.hook, sdk.find_type_definition("app.EPVExpertFootLandingCustom"):get_method("playEffect"),
  function() return sdk.PreHookResult.SKIP_ORIGINAL end)
pcall(sdk.hook, sdk.find_type_definition("via.effect.script.EPVStandard"):get_method("requestEffect"),
  nil, function(retval)
    thinEffects(sdk.to_managed_object(retval))

    return retval
  end)
pcall(sdk.hook, sdk.find_type_definition("via.effect.script.CreatedEffectContainer"):get_method("getEPVDataElement"),
  function(args) thinEffects(sdk.to_managed_object(args[2])) end)

re.on_script_reset(function()
  pcall(restoreScene)
  pcall(restoreLights)
end)

local cameraManagerType = sdk.find_type_definition("app.CameraManager")
local onSceneLoad = cameraManagerType and cameraManagerType:get_method("onSceneLoadFadeIn")
if onSceneLoad then
  pcall(sdk.hook, onSceneLoad, function()
    state.needsScan = true
    postFx.ready = false
  end)
end

re.on_draw_ui(function()
  if not imgui.tree_node("Steam Deck Performance") then return end

  local changed
  changed, settings.KeepPercent = imgui.slider_int("Small monsters kept (%)", settings.KeepPercent, 0, 100)
  if changed then
    decidedEnemies, smallMonsterAccumulator = {}, 0
    saveSettings()
  end

  changed, settings.AnimalKeepPercent = imgui.slider_int("Wildlife kept (%)", settings.AnimalKeepPercent, 0, 100)
  if changed then
    decidedEnemies, wildlifeAccumulator = {}, 0
    saveSettings()
  end

  imgui.tree_pop()
end)
