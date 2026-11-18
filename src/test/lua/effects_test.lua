local callbacks = {}
local function event()
    local handlers = {}
    return {
        Add = function(fn) handlers[fn] = true end,
        Remove = function(fn) handlers[fn] = nil end,
        fire = function(...) for fn in pairs(handlers) do fn(...) end end,
        count = function() local n = 0; for _ in pairs(handlers) do n = n + 1 end; return n end,
    }
end
Events = {}
for _, name in ipairs({ "OnObjectAdded", "OnObjectAboutToBeRemoved", "LoadGridsquare", "OnTick",
        "OnTickEvenPaused", "OnMainMenuEnter" }) do Events[name] = event() end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end,
        contains = function(_, item) for _, value in ipairs(values) do if value == item then return true end end; return false end }
end
local squares, snapshot = {}, nil
local now, active, steamEnabled, visible = 1000, true, true, true
local playerX = 0
local player = { getX = function() return playerX end, getY = function() return 0 end,
    getZ = function() return 0 end, getPlayerNum = function() return 0 end }
function getSpecificPlayer() return player end
function getTimestampMs() return now end
function isServer() return false end
local cell = { getGridSquare = function(_, x, y, z) return squares[x .. ":" .. y .. ":" .. z] end }
function getCell() return cell end
Viewpoint = { Addons = { ["maeiro.bath-shower-effects"] = { ShowerBridge = {
    isActive = function() return active end, update = function(value) snapshot = value end,
} } } }
local iso = {
    getSpritesTable = function(kind, facing) return kind == "ShowerWater" and { "water" .. facing } or nil end,
    getShowerObjectOnSquare = function(sq) return sq.shower end,
    getObjectFacing = function(obj) return obj.facing end,
    isBathObject = function(obj) return obj.isBath == true end,
    getFullyBathObject = function(obj) return obj.faucet, obj.tub end,
    getTfcBaseOnBathObject = function(obj) return obj.tfc end,
}
package.preload.TABAS_Iso = function() return iso end
package.preload.TABAS_GameTimes = function() return { getMultiplier = function() return 1 end } end
package.preload.TABAS_Utils = function() return { ModOptionsValue = function() return steamEnabled end } end
package.preload["TubFluidContainer/TABAS_TubFluidContainerSystemUtils"] = function()
    return { Filled_HalfLow = 0.30, HotWaterTemp = 40 }
end
local saltColors = {}
package.preload.TABAS_BathSaltDefs = function()
    return { getDisplayColor = function(salt) return saltColors[salt] end }
end
local function addSquare(x, name, facing)
    local objects = {}
    local sq = { getX = function() return x end, getY = function() return 0 end, getZ = function() return 0 end,
        getSpecialObjects = function() return list(objects) end, getObjects = function() return list({}) end,
        isCouldSee = function() return visible end,
        getLightLevel = function() return 0.5 end, shower = { facing = facing or "S" } }
    local obj = { getName = function() return name end, getSquare = function() return sq end,
        getSprite = function() return { getName = function() return "waterspriteS" end } end,
        getAlpha = function() return 0.4 end,
        getAttachedAnimSprite = function() return list({ { getAlpha = function() return 0.8 end } }) end }
    objects[1] = obj
    squares[x .. ":0:0"] = sq
    return sq, obj, objects
end
local function publish()
    now = now + 100
    Events.OnTickEvenPaused.fire()
end
local function check(condition, message) assert(condition, message) end

dofile(arg[1])
local sq, water, objects = addSquare(0, "ShowerWater")
publish()
for _ = 1, 30 do publish() end
check(#snapshot == 1 and snapshot[1].water == 1 and snapshot[1].steam == 0,
    "startup scan finds water without inventing steam")
local lateAlpha = 0.9
local lateSteam = { getName = function() return "ShowerSteam" end, getSquare = function() return sq end,
    getAlpha = function() return lateAlpha end, getAttachedAnimSprite = function() return list({}) end }
objects[2] = lateSteam
publish()
check(#snapshot == 1 and snapshot[1].water == 1 and snapshot[1].steam == 0.9,
    "delayed AddSpecialObject steam is discovered without an object-added event")
local frozen = snapshot.clock
publish()
check(snapshot.clock == frozen, "paused heartbeat does not animate")
Events.OnTick.fire()
publish()
check(snapshot.clock > frozen, "simulation tick animates")
local _, steam = addSquare(1, "ShowerSteam")
Events.OnObjectAdded.fire(steam)
publish()
check(#snapshot == 2 and snapshot[1].steam == 0.8, "steam uses body and puff transparency")
steamEnabled = false
publish()
check(#snapshot == 1, "disabled steam does not occupy a render slot")
check(snapshot[1].steam == 0 and snapshot[1].water == 1, "disabled steam keeps water visible")
steamEnabled = true
visible = false
publish()
check(#snapshot == 0, "unseen squares do not leak effects")
visible = true
for x = 2, 7 do local _, obj = addSquare(x, "ShowerWater", "W"); Events.OnObjectAdded.fire(obj) end
publish()
check(#snapshot == 4 and snapshot[1].x <= 3.5, "only four nearest showers are selected")
Events.OnObjectAboutToBeRemoved.fire(water)
table.remove(objects, 1)
publish()
check(not ViewpointBathShowerEffectsClient.objects[water], "removed object released")
local fading
for _, entry in ipairs(snapshot) do if entry.x == 0.5 then fading = entry end end
check(fading and fading.water == 0 and fading.steam == 0.9, "steam remains during water-off dissipation")
lateAlpha = 0
publish()
for _, entry in ipairs(snapshot) do check(entry.x ~= 0.5, "fully faded steam releases its render slot") end
table.remove(objects, 1)
publish()
check(not ViewpointBathShowerEffectsClient.objects[lateSteam], "silent steam removal is detected")
local old = steam
squares["1:0:0"] = nil
publish()
check(not ViewpointBathShowerEffectsClient.objects[old], "unloaded square reference released")
local _, invalid = addSquare(0, "ShowerWater", nil)
invalid.getSprite = function() return { getName = function() return "blank" end } end
Events.OnObjectAdded.fire(invalid)
publish()
for _, entry in ipairs(snapshot) do check(entry.x ~= 0.5, "blank water sprites are not rendered") end
active = false
publish()
active = true
playerX = 50
local _, distant = addSquare(50, "ShowerWater", "E")
for _ = 1, 30 do publish() end
check(#snapshot == 1 and snapshot[1].x == 50.5 and snapshot[1].facing == 3, "reactivation rescans at new position")
dofile(arg[1])
check(Events.OnTick.count() == 1 and Events.OnTickEvenPaused.count() == 1, "Lua reload replaces handlers")
Events.OnMainMenuEnter.fire()
check(#snapshot == 0, "menu entry clears shader state")
print("PASS: TABAS discovery, pause, opacity, visibility, nearest-four cap, unloading, reactivation, reload, cleanup")

local function addTub(x, y, facing, offsetX, offsetY)
    local data = { amount = 175, capacity = 200, temperature = 40, dirty = 0, filling = false }
    local tfc = {
        getAmount = function() return data.amount end, getCapacity = function() return data.capacity end,
        getWaterTemperature = function() return data.temperature end,
        getWaterData = function(_, key)
            if key == "dirtyLevel" then return data.dirty end
            if key == "colors" then return data.colors end
            if key == "bathSalt" then return data.salt end
            error("Unexpected water data key: " .. tostring(key))
        end,
        getActivatedData = function() return { activate = data.filling, state = "fill", phase = data.phase } end,
    }
    local function half(sx, sy)
        local objects = {}
        local sq = { getX = function() return sx end, getY = function() return sy end,
            getZ = function() return 0 end, getObjects = function() return list(objects) end,
            getSpecialObjects = function() return list({}) end, isCouldSee = function() return visible end,
            getLightLevel = function() return 0.6 end }
        local obj = { isBath = true, facing = facing, tfc = tfc, getSquare = function() return sq end,
            getName = function() return "Bathtub" end }
        objects[1] = obj
        squares[sx .. ":" .. sy .. ":0"] = sq
        return obj, objects
    end
    local faucet, mainObjects = half(x, y)
    local tub, linkedObjects = half(x + offsetX, y + offsetY)
    faucet.faucet, faucet.tub, tub.faucet, tub.tub = faucet, tub, faucet, tub
    Events.LoadGridsquare.fire(faucet:getSquare())
    Events.LoadGridsquare.fire(tub:getSquare())
    return data, faucet, tub, mainObjects, linkedObjects
end

playerX = 0
squares = {}
local tubData, faucet, tub, mainObjects, linkedObjects = addTub(0, 0, "S", 0, 1)
publish()
check(#snapshot == 1 and snapshot[1].kind == 1 and snapshot[1].water == 0.875,
    "two normal tile objects produce one bathtub with its actual water level")
check(snapshot[1].x == 0.5 and snapshot[1].y == 1 and snapshot[1].steam > 0,
    "hot water is centered between the two halves and produces steam")
check(snapshot[1].color == nil, "plain water preserves the existing shader color without a TABAS tint")
for index, salt in ipairs({ "Lavender", "Citrus", "Floral", "Forest", "Herb", "Rose", "CustomSalt" }) do
    saltColors[salt] = { r = index / 10, g = 0.25, b = 0.8 }
    tubData.salt = salt
    publish()
    check(snapshot[1].color.r == index / 10 and snapshot[1].color.g == 0.25 and snapshot[1].color.b == 0.8,
        "salt color is resolved through TABAS definitions: " .. salt)
end
tubData.colors, tubData.dirty = { r = 0.15, g = 0.05, b = 0.1, a = 0.5 }, 30
publish()
check(snapshot[1].color.r == 0.15 and snapshot[1].color.g == 0.05 and snapshot[1].color.b == 0.1,
    "final replicated color takes precedence and is not dirtied a second time")
tubData.colors = nil
publish()
check(snapshot[1].color.r == 0.35 and snapshot[1].color.g == 0.32 and snapshot[1].color.b == 0.21,
    "salt fallback retains the existing dirt effect while waiting for final color replication")
tubData.dirty = 0
tubData.colors = { r = 0, g = 0, b = 0 }
publish()
check(snapshot[1].color.r == 0 and snapshot[1].color.g == 0 and snapshot[1].color.b == 0,
    "a genuine black tint is distinguished from an absent color")
for _, bad in ipairs({ { r = 0 / 0, g = 0, b = 0 }, { r = 2, g = 0, b = 0 }, { r = 0 }, false, "bad" }) do
    tubData.colors = bad
    publish()
    check(snapshot[1].color.r == saltColors.CustomSalt.r, "malformed final color falls back to salt definitions")
end
tubData.colors, tubData.salt = nil, "UnknownSalt"
publish()
check(snapshot[1].color == nil, "unknown salt leaves normal water visible")
tubData.salt = nil
tubData.amount, tubData.filling, tubData.temperature = 25, true, 22
publish()
check(snapshot[1].water == 0.125 and snapshot[1].steam == 0 and snapshot[1].filling == 1,
    "cold filling water updates level and spout without inventing steam")
tubData.phase = "runout"
publish()
check(snapshot[1].filling == 0, "runout phase does not invent running tap water")
tubData.phase = nil
tubData.amount, tubData.temperature = 60, 50
publish()
check(snapshot[1].steam == 0, "TABAS steam requires more than 30 percent water")
tubData.amount, tubData.dirty = 80, 15
steamEnabled = false
publish()
check(snapshot[1].steam > 0 and snapshot[1].dirty == 0.5,
    "tub steam follows TABAS temperature rules independently of the shower-only option")
tubData.amount, tubData.filling = 40, false
publish()
check(snapshot[1].water == 0.2 and snapshot[1].filling == 0 and snapshot[1].steam == 0,
    "draining lowers water and stops the spout and low-level steam")
for _, value in ipairs({ 0, -1, 0 / 0, math.huge }) do
    tubData.capacity = value
    publish()
    check(#snapshot == 0, "invalid fluid capacity is rejected")
end
tubData.capacity, tubData.amount = 200, 0
publish()
check(#snapshot == 0, "empty bathtub leaves no water or steam")
tubData.amount = 200
visible = false
publish()
check(#snapshot == 0, "bathtubs in unseen squares are not rendered")
visible = true
table.remove(linkedObjects, 1)
publish()
check(#snapshot == 0, "missing linked half does not leave a full-size water plane")
linkedObjects[1] = tub
publish()
check(#snapshot == 1, "replicated linked half can become available later")
squares["0:1:0"] = nil
publish()
check(#snapshot == 0 and not ViewpointBathShowerEffectsClient.tubs[tub], "unloaded tub half is released")
for _, test in ipairs({ {"S", 0, 1, 0}, {"W", -1, 0, 1}, {"N", 0, -1, 2}, {"E", 1, 0, 3} }) do
    squares = {}
    Events.OnMainMenuEnter.fire()
    local data = addTub(0, 0, test[1], test[2], test[3])
    publish()
    check(#snapshot == 1 and snapshot[1].facing == test[4], "all four tub orientations are recognized")
    check(snapshot[1].x == (1 + test[2]) / 2 and snapshot[1].y == (1 + test[3]) / 2,
        "all orientations are centered on actual paired squares")
end
local _, shower = addSquare(2, "ShowerWater")
Events.OnObjectAdded.fire(shower)
publish()
local kinds = {}
for _, entry in ipairs(snapshot) do kinds[entry.kind or 0] = true end
check(kinds[0] and kinds[1], "showers and bathtubs share the same bounded snapshot")
addTub(4, 0, "S", 0, 1)
addTub(6, 0, "S", 0, 1)
local _, extraShower = addSquare(3, "ShowerWater")
Events.OnObjectAdded.fire(extraShower)
publish()
check(#snapshot == 4, "mixed showers and bathtubs obey one shared four-effect limit")
for _, entry in ipairs(snapshot) do check(entry.x < 6, "distant bath cannot displace closer effects") end
print("PASS: bathtub fill/drain, heat, salt colors, replicated stains, paired tiles, all facings, invalid data, visibility and unload/reload")
