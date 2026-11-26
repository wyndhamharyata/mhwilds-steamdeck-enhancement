-- Steam Deck Enhancement for Monster Hunter Wilds.
-- Rendering profile measured on Steam Deck. Only wildlife density is user-configurable.

local settings = json.load_file("SteamDeckEnhancement.json") or {}
if settings.KeepPercent == nil then settings.KeepPercent = 25 end
if settings.AnimalKeepPercent == nil then settings.AnimalKeepPercent = 25 end
local function saveSettings() json.dump_file("SteamDeckEnhancement.json", settings) end

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

local sceneManager = sdk.get_native_singleton("via.SceneManager")
local sceneManagerType = sdk.find_type_definition("via.SceneManager")
local stopwatch = sdk.find_type_definition("System.Diagnostics.Stopwatch"):get_method("GetTimestamp")
local function now() return stopwatch:call(nil) / 10000000 end
local function currentScene()
  return sdk.call_native_func(sceneManager, sceneManagerType, "get_CurrentScene()")
end

local state = { needsScan = true, cloudTurning = false, lastMove = 0, nextFog = 0, lastRenderer = 0,
  meshIndex = 1, sdfIndex = 1, grassIndex = 1, dirty = false, sdfDirty = false, grassDirty = false }
local foliageFlags = { "DrawShadowCast", "DrawFarCascadeShadowCast", "DrawSignedDistanceField", "DrawVoxelize", "DrawEnvmap" }
local enabledFoliagePasses = { DrawShadowCast = true, DrawFarCascadeShadowCast = false,
  DrawSignedDistanceField = true, DrawVoxelize = false, DrawEnvmap = false }

local postFx = { ready = false }
local function applyPostFx()
  if not postFx.ready then return end
  local t, p, ds = postFx.tone, postFx.post, postFx.display
  t:call("setVignetting", 2)
  t:call("setTemporalAA", 5)
  t:call("setTemporalAAAlgorithm", 1)
  t:call("setTemporalJitterScale", 0)
  t:call("set_Sharpness", 0.431)
  t:call("set_Contrast", 0.633)
  t:call("set_VignettingBrightness", 0.291)
  t:call("set_EV", 2.0)
  t:call("set_EnableLocalExposure", true)
  t:call("setLocalExposureType", 1)
  p:call("get_FilmGrain"):call("set_BlendRate", 0)
  ds:call("set_Gamma", 1.045)
  ds:call("set_OutputLowerLimit", -0.141)
  ds:call("set_OutputUpperLimit", 2.674)
  ds:call("set_GammaForOverlay", 1.179)
  ds:call("set_OutputLowerLimitForOverlay", -0.072)
  ds:call("set_OutputUpperLimitForOverlay", 0.805)
end

local function applyRendererProfile()
  local MR, MRt = sdk.get_native_singleton("via.render.MeshRenderer"), sdk.find_type_definition("via.render.MeshRenderer")
  local ST, STt = sdk.get_managed_singleton("via.speedtree.SpeedTreeMasterInstance"), sdk.find_type_definition("via.speedtree.SpeedTreeMasterInstance")
  local R, Rt = sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer")
  sdk.call_native_func(MR, MRt, "set_LodBias", 1)
  sdk.call_native_func(ST, STt, "set_LodBias", 3)
  sdk.call_native_func(ST, STt, "set_StreamingMeshMinimumLod", 5)
  sdk.call_native_func(R, Rt, "set_SmallObjectCullingRatio", 24.0)
  local L, Lt = sdk.get_managed_singleton("via.render.LightRenderer"), sdk.find_type_definition("via.render.LightRenderer")
  sdk.call_native_func(L, Lt, "set_ShadowResolution", SHADOW_RESOLUTION)
  sdk.call_native_func(L, Lt, "set_ShadowFilter", 0)
  local S, St = sdk.get_native_singleton("via.render.Sampler"), sdk.find_type_definition("via.render.Sampler")
  sdk.call_native_func(S, St, "set_Bias", 1.016)
  local G, Gt = sdk.get_native_singleton("via.render.GIPointCloudManager"), sdk.find_type_definition("via.render.GIPointCloudManager")
  sdk.call_native_func(G, Gt, "set_MinLod", 0)
  sdk.call_native_func(G, Gt, "set_LodBaseDistance", 8.0)
  local scene = currentScene()
  if scene then
    local probes = scene:call("findComponents(System.Type)", sdk.typeof("via.render.DynamicProbeGI"))
    for i = 0, probes:get_size() - 1 do
      local c = probes:get_element(i)
      c:call("set_VoxelResolution", 0)
      c:call("set_GIPRadianceVolumeStartLodNo", 5)
      c:call("set_GIPRadianceVolumeStartDistanceEnable", true)
      c:call("set_GIPRadianceVolumeStartDistance", 0.0)
      c:call("set_TransparentProbeRayNum", 0)
      c:call("set_VolumeNum", 7)
    end
  end
end

local function initPostFx()
  local ok, result = pcall(function()
    local cm = sdk.get_managed_singleton("app.CameraManager")
    local cam = cm and cm:call("get_PrimaryCamera")
    local go = cam and cam:call("get_GameObject")
    if not go then return false end
    postFx.tone = go:call("getComponent(System.Type)", sdk.typeof("via.render.ToneMapping"))
    postFx.post = go:call("getComponent(System.Type)", sdk.typeof("via.render.LDRPostProcess"))
    local gm = sdk.get_managed_singleton("app.GraphicsManager")
    postFx.display = gm and gm:call("get_DisplaySettings")
    if not (postFx.tone and postFx.post and postFx.display) then return false end
    applyRendererProfile()
    return true
  end)
  postFx.ready = ok and result == true
  if postFx.ready then applyPostFx() end
  return postFx.ready
end

local function isPlayer(go)
  local tr = go and go:call("get_Transform")
  local parent = tr and tr:call("get_Parent")
  while parent do
    local pgo = parent:call("get_GameObject")
    if pgo and pgo:call("get_Name") == "MasterPlayer" then return true end
    parent = parent:call("get_Parent")
  end
  return false
end

local function scanScene()
  local scene = currentScene()
  state.cloud, state.cloudSteps, state.fog = nil, nil, nil
  state.foliage, state.grass, state.meshes = {}, {}, {}
  if scene then
    local fogs = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Fog"))
    if fogs and fogs:get_size() > 0 then
      state.fog = fogs:get_element(0)
      state.fogStart, state.fogDensity = state.fog:call("get_StartDistance"), state.fog:call("get_Density")
      state.fog:call("set_StartDistance", FOG_START_DISTANCE)
      state.fog:call("set_Density", FOG_DENSITY)
    end
    local clouds = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Cloudscape2"))
    if clouds and clouds:get_size() > 0 then
      state.cloud = clouds:get_element(0)
      state.cloudSteps = state.cloud:call("get_CloudRaymarchNum")
      state.cloudTurning = false
    end
    local foliage = scene:call("findComponents(System.Type)", sdk.typeof("via.landscape.Foliage"))
    if foliage then
      for i = 0, foliage:get_size() - 1 do
        local c = foliage:get_element(i)
        local go = c:call("get_GameObject")
        local name = go:call("get_Name")
        local p = go:call("get_Transform"):call("get_Position")
        local m = { c = c, orig = {}, x = p.x, y = p.y, z = p.z, sdfDisabled = false,
          draw = c:call("get_DrawDefault"), grassHidden = false }
        for _, flag in ipairs(foliageFlags) do
          m.orig[flag] = c:call("get_" .. flag)
          c:call("set_" .. flag, enabledFoliagePasses[flag] and m.orig[flag] or false)
        end
        state.foliage[#state.foliage + 1] = m
        if name:match("^st101_a08_.*Grass") or name:match("^st101_a08_Inaho") then
          state.grass[#state.grass + 1] = m
        end
      end
    end
    local meshes = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Mesh"))
    if meshes then
      for i = 0, meshes:get_size() - 1 do
        local c = meshes:get_element(i)
        local go = c:call("get_GameObject")
        local name = go and go:call("get_Name") or ""
        local prefix = name:sub(1, 2)
        if (prefix == "sm" or prefix == "Gm" or prefix == "st" or prefix == "Em" or prefix == "Pr") and not isPlayer(go) then
          local p = go:call("get_Transform"):call("get_Position")
          local index = #state.meshes + 1
          local grass = name:find("Grass") ~= nil or name:find("Inaho") ~= nil
          local culled = not grass and index % 10 < 7
          local draw = c:call("get_DrawDefault")
          c:call("set_DrawDefault", draw and not culled)
          state.meshes[index] = { c = c, x = p.x, y = p.y, z = p.z,
            draw = draw, hidden = false, culled = culled }
        end
      end
    end
  end
  state.needsScan, state.dirty, state.sdfDirty, state.grassDirty = false, true, true, true
  state.meshIndex, state.sdfIndex, state.grassIndex = 1, 1, 1
  state.lastCamera, state.nextFog = nil, now() + 5
end

local function updateChunk(items, index, dirty, cp, radius, margin, flag, setting)
  if not dirty then return index, dirty end
  local hide2, show2 = radius * radius, (radius - margin) * (radius - margin)
  local last = math.min(index + 95, #items)
  for i = index, last do
    local m = items[i]
    local dx, dy, dz = m.x - cp.x, m.y - cp.y, m.z - cp.z
    local d2 = dx * dx + dy * dy + dz * dz
    local hidden = m[setting] and d2 > show2 or d2 > hide2
    if hidden ~= m[setting] then
      m[setting] = hidden
      if flag == "DrawDefault" then m.c:call("set_DrawDefault", m.draw and not hidden and not m.culled)
      else m.c:call("set_DrawSignedDistanceField", not hidden and m.orig.DrawSignedDistanceField or false) end
    end
  end
  return last + 1, last ~= #items
end

local function restoreScene()
  if state.cloud then state.cloud:call("set_CloudRaymarchNum", state.cloudSteps) end
  if state.fog then
    state.fog:call("set_StartDistance", state.fogStart)
    state.fog:call("set_Density", state.fogDensity)
  end
  for _, m in ipairs(state.foliage or {}) do
    for flag, original in pairs(m.orig) do m.c:call("set_" .. flag, original) end
  end
  for _, m in ipairs(state.meshes or {}) do m.c:call("set_DrawDefault", m.draw) m.hidden, m.culled = false, false end
  state.cloudTurning = false
end

re.on_application_entry("WaitForVblank", function()
  if state.needsScan then scanScene() end
  if not postFx.ready then initPostFx() end
  if t - state.lastRenderer >= 10 then applyRendererProfile() state.lastRenderer = t end
  if postFx.ready then
    postFx.tone:call("setVignetting", 2)
    postFx.tone:call("set_VignettingBrightness", 0.291)
  end
  local cam = sdk.get_primary_camera()
  if not cam then return end
  local t = now()
  local tr = cam:call("get_GameObject"):call("get_Transform")
  local q, cp = tr:call("get_Rotation"), tr:call("get_Position")
  local moving = false
  if state.q then
    local dot = math.abs(q.x * state.q.x + q.y * state.q.y + q.z * state.q.z + q.w * state.q.w)
    moving = 2 * math.acos(math.min(1, dot)) > 0.003
  end
  state.q = q
  if moving then state.lastMove = t end
  local turning = t - state.lastMove < RESTORE_DELAY
  if state.cloud and turning ~= state.cloudTurning then
    state.cloud:call("set_CloudRaymarchNum", turning and CLOUD_STEPS_WHILE_TURNING or state.cloudSteps)
    state.cloudTurning = turning
  end
  local p = state.lastCamera
  if not p or (cp.x - p.x)^2 + (cp.y - p.y)^2 + (cp.z - p.z)^2 > 4 then
    state.dirty, state.sdfDirty, state.grassDirty = true, true, true
    state.meshIndex, state.sdfIndex, state.grassIndex = 1, 1, 1
  end
  state.meshIndex, state.dirty = updateChunk(state.meshes, state.meshIndex, state.dirty, cp,
    DRAW_DISTANCE, 10, "DrawDefault", "hidden")
  state.sdfIndex, state.sdfDirty = updateChunk(state.foliage, state.sdfIndex, state.sdfDirty, cp,
    FOLIAGE_SDF_DISTANCE, 5, "DrawSignedDistanceField", "sdfDisabled")
  state.grassIndex, state.grassDirty = updateChunk(state.grass, state.grassIndex, state.grassDirty, cp,
    GRASS_CELL_DISTANCE, 10, "DrawDefault", "grassHidden")
  if state.meshIndex > #state.meshes and state.sdfIndex > #state.foliage and state.grassIndex > #state.grass then
    state.lastCamera = { x = cp.x, y = cp.y, z = cp.z }
  end
  if state.fog and t >= state.nextFog then
    state.fog:call("set_StartDistance", FOG_START_DISTANCE)
    state.fog:call("set_Density", FOG_DENSITY)
    state.nextFog = t + 5
  end
end)

-- Time-of-day lights only; monster and effect lights are not touched.
local TOD = { "^[Mm]orning", "^[Dd]ay_", "^[Ee]vening", "^[Nn]ight" }
local lights, trimmed, shadowOff = {}, {}, {}
local lightFrame = 0
local function isTod(name)
  for _, pattern in ipairs(TOD) do if name:find(pattern) then return true end end
  return false
end
local function restoreLights()
  for c in pairs(trimmed) do pcall(c.call, c, "set_Enabled", true) end
  for c in pairs(shadowOff) do pcall(c.call, c, "set_ShadowEnable", true) end
  trimmed, shadowOff, lights = {}, {}, {}
end
local function rescanLights()
  restoreLights()
  local scene = currentScene()
  if not scene then return end
  for _, typeName in ipairs({ "via.render.SpotLight", "via.render.PointLight" }) do
    local arr = scene:call("findComponents(System.Type)", sdk.typeof(typeName))
    for i = 0, arr:get_size() - 1 do
      local c = arr:get_element(i)
      local go = c:call("get_GameObject")
      local name = go and go:call("get_Name") or ""
      if isTod(name) then lights[#lights + 1] = { c = c, fill = name:find("_Fill") ~= nil } end
    end
  end
end
re.on_frame(function()
  lightFrame = lightFrame + 1
  if lightFrame % 600 == 1 then pcall(rescanLights)
  elseif lightFrame % 600 == 60 then
    for _, l in ipairs(lights) do
      local c = l.c
      local ok, intensity = pcall(c.call, c, "get_Intensity")
      if ok and intensity == 0 and not trimmed[c] and c:call("get_Enabled") then
        c:call("set_Enabled", false)
        trimmed[c] = true
      end
      if l.fill and not shadowOff[c] and c:call("get_ShadowEnable") then
        c:call("set_ShadowEnable", false)
        shadowOff[c] = true
      end
    end
  end
end)

-- Small monsters, wildlife and distant non-quest bosses share one enemy-update hook.
local enemyManager, missionManager, player, px, py, pz
local enemyFrame, decided, info = 0, {}, {}
local zakoAcc, animalAcc, lastStage = 0, 0, nil
local function keep(percent, which)
  if which == "animal" then
    animalAcc = animalAcc + percent
    if animalAcc >= 100 then animalAcc = animalAcc - 100 return true end
  else
    zakoAcc = zakoAcc + percent
    if zakoAcc >= 100 then zakoAcc = zakoAcc - 100 return true end
  end
  return false
end
re.on_frame(function()
  enemyFrame = enemyFrame + 1
  if enemyFrame % 300 == 1 then
    info, player = {}, nil
    local ok, go = pcall(function() return currentScene():call("findGameObject(System.String)", "MasterPlayer") end)
    player = ok and go or nil
    enemyManager = enemyManager or sdk.get_managed_singleton("app.EnemyManager")
    missionManager = missionManager or sdk.get_managed_singleton("app.MissionManager")
  end
  if player then
    local ok, p = pcall(function() return player:call("get_Transform"):call("get_Position") end)
    if ok and p then px, py, pz = p.x, p.y, p.z else player = nil end
  end
end)
sdk.hook(sdk.find_type_definition("app.EnemyCharacter"):get_method("update()"), function(args)
  if not (px and enemyManager and missionManager) then return end
  local stage = missionManager:getActiveStageType()
  if stage ~= lastStage then decided, info, zakoAcc, animalAcc, lastStage = {}, {}, 0, 0, stage end
  local addr = sdk.to_int64(args[2])
  local ch = sdk.to_managed_object(args[2])
  local ech = ch and ch:get_field("_Context")
  local ec = ech and ech:get_field("_Em")
  if not ec then return end
  if not decided[addr] then
    decided[addr] = true
    local zako, animal = ec:get_IsZako(), ec:get_IsAnimal()
    if zako or animal then
      local browser = ec:get_Browser()
      local key = browser and browser:get_ThisTargetAccessKey()
      if key and not missionManager:isQuestTarget(key) then
        local id = ec:get_EmID()
        local remove = zako and id ~= 38 and not keep(settings.KeepPercent, "zako")
        if animal and not (id and id >= 57 and id <= 77) then remove = not keep(settings.AnimalKeepPercent, "animal") end
        if remove then enemyManager:requestRemove(ech, 0, true) end
      end
    end
  end
  local i = info[addr]
  if i == nil then
    i = { boss = false, at = -1000 }
    info[addr] = i
    local key = ec:get_IsBoss() and ec:get_Browser() and ec:get_Browser():get_ThisTargetAccessKey()
    if key and not missionManager:isQuestTarget(key) then i.boss, i.ch = true, ch end
  end
  if not i.boss then return end
  if enemyFrame - i.at >= 30 then
    local ok, p = pcall(function() return i.ch:call("get_GameObject"):call("get_Transform"):call("get_Position") end)
    i.far = ok and p and ((p.x - px)^2 + (p.y - py)^2 + (p.z - pz)^2) > FAR_DISTANCE^2
    i.at = enemyFrame
  end
  if i.far and (enemyFrame + addr // 16) % FAR_UPDATE_EVERY ~= 0 then return sdk.PreHookResult.SKIP_ORIGINAL end
end, function(retval) return retval end)

local function thinEffects(obj)
  if not obj then return end
  local ok, players = pcall(function() return obj:call("getAllPlayers") end)
  if not ok or not players then return end
  local okItems, items = pcall(function() return players:get_field("_items") end)
  if not okItems or not items then return end
  for i = 0, #items - 1 do
    pcall(function()
      local q = items[i]:call("get_QualitySettings")
      if q then q:call("set_SpawnVolumeRatio", q:call("get_SpawnVolumeRatio") * EFFECT_DENSITY) end
    end)
  end
end
pcall(sdk.hook, sdk.find_type_definition("app.EPVExpertFootLandingCustom"):get_method("playEffect"), function() return sdk.PreHookResult.SKIP_ORIGINAL end)
pcall(sdk.hook, sdk.find_type_definition("via.effect.script.EPVStandard"):get_method("requestEffect"), nil, function(retval) thinEffects(sdk.to_managed_object(retval)) return retval end)
pcall(sdk.hook, sdk.find_type_definition("via.effect.script.CreatedEffectContainer"):get_method("getEPVDataElement"), function(args) thinEffects(sdk.to_managed_object(args[2])) end)

re.on_script_reset(function() pcall(restoreScene) pcall(restoreLights) end)
local cameraManager = sdk.find_type_definition("app.CameraManager")
local onLoad = cameraManager and cameraManager:get_method("onSceneLoadFadeIn")
if onLoad then pcall(sdk.hook, onLoad, function() state.needsScan = true postFx.ready = false end) end

re.on_draw_ui(function()
  if not imgui.tree_node("Steam Deck Performance") then return end
  local changed
  changed, settings.KeepPercent = imgui.slider_int("Small monsters kept (%)", settings.KeepPercent, 0, 100)
  if changed then decided, zakoAcc = {}, 0 saveSettings() end
  changed, settings.AnimalKeepPercent = imgui.slider_int("Wildlife kept (%)", settings.AnimalKeepPercent, 0, 100)
  if changed then decided, animalAcc = {}, 0 saveSettings() end
  imgui.tree_pop()
end)
