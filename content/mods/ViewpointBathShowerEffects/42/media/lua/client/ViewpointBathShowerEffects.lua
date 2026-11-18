if isServer() then return end

local TABAS_Iso = require("TABAS_Iso")
local TABAS_GameTimes = require("TABAS_GameTimes")
local TABAS_Utils = require("TABAS_Utils")
local TFC_Utils = require("TubFluidContainer/TABAS_TubFluidContainerSystemUtils")
local BathSaltDefs = require("TABAS_BathSaltDefs")
local ADDON_ID = "maeiro.bath-shower-effects"
local RADIUS = 16
local LIMIT = 4
local FACING = { S = 0, W = 1, N = 2, E = 3 }
local TUB_DIRECTION = { S = { 0, 1 }, W = { -1, 0 }, N = { 0, -1 }, E = { 1, 0 } }
local waterSprites = {}
for facing in pairs(FACING) do
    for _, name in ipairs(TABAS_Iso.getSpritesTable("ShowerWater", "sprite" .. facing) or {}) do
        waterSprites[name] = true
    end
end
local previous = ViewpointBathShowerEffectsClient
if previous then
    Events.OnObjectAdded.Remove(previous.add)
    Events.OnObjectAboutToBeRemoved.Remove(previous.remove)
    Events.LoadGridsquare.Remove(previous.loadSquare)
    Events.OnTick.Remove(previous.tick)
    Events.OnTickEvenPaused.Remove(previous.publish)
    Events.OnMainMenuEnter.Remove(previous.clear)
end

local client = { objects = {}, tubs = {}, selected = {}, clock = 0, lastPublish = 0 }
ViewpointBathShowerEffectsClient = client

local function bridge()
    local addon = Viewpoint and Viewpoint.Addons and Viewpoint.Addons[ADDON_ID]
    return addon and addon.ShowerBridge
end

function client.add(object)
    if object and (object:getName() == "ShowerWater" or object:getName() == "ShowerSteam") then
        client.objects[object] = true
    elseif object and TABAS_Iso.isBathObject(object) then
        client.tubs[object] = true
    end
end

function client.remove(object)
    client.objects[object] = nil
    client.tubs[object] = nil
end

function client.loadSquare(square)
    if not square then return end
    local objects = square:getSpecialObjects()
    for i = 0, objects:size() - 1 do client.add(objects:get(i)) end
    objects = square:getObjects()
    for i = 0, objects:size() - 1 do client.add(objects:get(i)) end
end

function client.clear()
    client.objects = {}
    client.tubs = {}
    client.selected = {}
    client.scan = nil
    client.scanCenter = nil
    client.clock = 0
    client.wasActive = false
    local api = bridge()
    if api and api.isActive() then api.update({ clock = 0 }) end
end

function client.tick()
    client.clock = (client.clock + math.max(0, TABAS_GameTimes.getMultiplier() or 0) / 30) % 100000
end

local function beginScan(player)
    client.scanCenter = { x = player:getX(), y = player:getY(), z = player:getZ() }
    client.scan = {
        x = math.floor(player:getX()) - RADIUS,
        y = math.floor(player:getY()) - RADIUS,
        z = math.floor(player:getZ()) - 1,
        index = 0,
    }
end

local function scanLoadedSquares()
    local scan = client.scan
    local cell = getCell()
    if not scan or not cell then return end
    local side = RADIUS * 2 + 1
    local total = side * side * 3
    for _ = 1, 128 do
        if scan.index >= total then client.scan = nil; return end
        local index = scan.index
        client.loadSquare(cell:getGridSquare(scan.x + index % side,
            scan.y + math.floor(index / side) % side, scan.z + math.floor(index / (side * side))))
        scan.index = index + 1
    end
end

local function steamAlpha(object, playerNum)
    local alpha = object:getAlpha(playerNum)
    local puffs = object:getAttachedAnimSprite()
    if puffs then
        for i = 0, puffs:size() - 1 do alpha = math.max(alpha, puffs:get(i):getAlpha()) end
    end
    return math.max(0, math.min(1, alpha))
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function loadedObject(object, cell)
    local square = object and object:getSquare()
    return square and cell:getGridSquare(square:getX(), square:getY(), square:getZ()) == square
        and square:getObjects():contains(object)
end

local function validColor(color)
    return type(color) == "table" and finite(color.r) and finite(color.g) and finite(color.b)
        and color.r >= 0 and color.r <= 1 and color.g >= 0 and color.g <= 1 and color.b >= 0 and color.b <= 1
end

local function waterColor(tfc, dirt)
    -- TABAS synchronizes the final tint, including salt and stains, on its water object.
    local color = tfc:getWaterData("colors")
    if validColor(color) then return { r = color.r, g = color.g, b = color.b } end
    local salt = tfc:getWaterData("bathSalt")
    color = type(salt) == "string" and BathSaltDefs.getDisplayColor(salt) or nil
    if not validColor(color) then return nil end
    return { r = color.r * (1 - dirt) + 0.35 * dirt,
        g = color.g * (1 - dirt) + 0.32 * dirt, b = color.b * (1 - dirt) + 0.21 * dirt }
end

local function collectTubs(player, cell, candidates)
    local seen = {}
    local playerNum = player:getPlayerNum()
    for object in pairs(client.tubs) do
        if not loadedObject(object, cell) then
            client.tubs[object] = nil
        else
            local square = object:getSquare()
            local dx, dy = square:getX() + 0.5 - player:getX(), square:getY() + 0.5 - player:getY()
            if dx * dx + dy * dy > (RADIUS * 2) ^ 2 then client.tubs[object] = nil end
            if dx * dx + dy * dy <= RADIUS * RADIUS and math.abs(square:getZ() - player:getZ()) < 1
                    and square:isCouldSee(playerNum) then
                local faucet, tub = TABAS_Iso.getFullyBathObject(object)
                if faucet and tub and not seen[faucet] and loadedObject(faucet, cell) and loadedObject(tub, cell) then
                    seen[faucet] = true
                    local main, linked = faucet:getSquare(), tub:getSquare()
                    local facing = TABAS_Iso.getObjectFacing(faucet)
                    local direction = TUB_DIRECTION[facing]
                    if direction and linked:getX() - main:getX() == direction[1]
                            and linked:getY() - main:getY() == direction[2] and linked:getZ() == main:getZ() then
                        local tfc = TABAS_Iso.getTfcBaseOnBathObject(faucet)
                        local amount, capacity = tfc and tfc:getAmount(), tfc and tfc:getCapacity()
                        local temperature = tfc and tfc:getWaterTemperature()
                        if finite(amount) and finite(capacity) and finite(temperature) and capacity > 0 and amount > 0 then
                            local ratio = math.min(1, amount / capacity)
                            local x, y = (main:getX() + linked:getX() + 1) / 2, (main:getY() + linked:getY() + 1) / 2
                            local dirty = tfc:getWaterData("dirtyLevel") or 0
                            if not finite(dirty) then dirty = 0 end
                            dirty = math.max(0, math.min(1, dirty / 30))
                            local activated = tfc:getActivatedData()
                            candidates[#candidates + 1] = {
                                x = x, y = y, z = main:getZ(), facing = FACING[facing], kind = 1,
                                water = ratio, steam = ratio > TFC_Utils.Filled_HalfLow and temperature >= TFC_Utils.HotWaterTemp
                                    and math.max(0.3, math.min(1, (temperature - 30) / 25)) or 0,
                                filling = activated and activated.activate and activated.state == "fill"
                                    and activated.phase ~= "runout" and 1 or 0,
                                dirty = dirty, color = waterColor(tfc, dirty),
                                light = math.max(0, math.min(1, square:getLightLevel(playerNum))), square = main,
                                score = (x - player:getX()) ^ 2 + (y - player:getY()) ^ 2 - (client.selected[main] and 1 or 0),
                            }
                        end
                    end
                end
            end
        end
    end
end

function client.publish()
    local api = bridge()
    local player = getSpecificPlayer(0)
    local cell = getCell()
    if not api or not api.isActive() or not player or not cell then
        client.wasActive = false
        return
    end
    if not client.wasActive then beginScan(player); client.wasActive = true end
    local center = client.scanCenter
    if center and ((center.x - player:getX()) ^ 2 + (center.y - player:getY()) ^ 2 > 64
            or math.floor(center.z) ~= math.floor(player:getZ())) then beginScan(player) end
    scanLoadedSquares()
    local now = getTimestampMs()
    if now - client.lastPublish < 100 then return end
    client.lastPublish = now

    local squares = {}
    local candidates = {}
    local playerNum = player:getPlayerNum()
    local steamEnabled = TABAS_Utils.ModOptionsValue("EnabledShowerSteamAnim") ~= false
    local effectSquares = {}
    for object in pairs(client.objects) do
        local square = object:getSquare()
        if square and cell:getGridSquare(square:getX(), square:getY(), square:getZ()) == square then
            effectSquares[square] = true
        end
    end
    -- TABAS adds delayed steam with AddSpecialObject, which does not emit OnObjectAdded.
    for square in pairs(effectSquares) do client.loadSquare(square) end
    for object in pairs(client.objects) do
        local square = object:getSquare()
        if not square or not square:getSpecialObjects():contains(object)
                or cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then
            client.objects[object] = nil
        else
            local dx, dy = square:getX() + 0.5 - player:getX(), square:getY() + 0.5 - player:getY()
            if dx * dx + dy * dy > (RADIUS * 2) ^ 2 then client.objects[object] = nil end
            if dx * dx + dy * dy <= RADIUS * RADIUS and math.abs(square:getZ() - player:getZ()) < 1
                    and square:isCouldSee(playerNum) then
                local entry = squares[square]
                if not entry then
                    local shower = TABAS_Iso.getShowerObjectOnSquare(square, true)
                    local facing = shower and TABAS_Iso.getObjectFacing(shower)
                    if FACING[facing] then
                        entry = { x = square:getX() + 0.5, y = square:getY() + 0.5, z = square:getZ(),
                            facing = FACING[facing], water = 0, steam = 0,
                            light = math.max(0, math.min(1, square:getLightLevel(playerNum))), square = square,
                            score = dx * dx + dy * dy - (client.selected[square] and 1 or 0) }
                        squares[square] = entry
                        candidates[#candidates + 1] = entry
                    end
                end
                if entry then
                    if object:getName() == "ShowerWater" then
                        local sprite = object:getSprite()
                        local name = sprite and sprite:getName() or ""
                        if waterSprites[name] then entry.water = 1 end
                    elseif steamEnabled then
                        entry.steam = math.max(entry.steam, steamAlpha(object, playerNum))
                    end
                end
            end
        end
    end
    for i = #candidates, 1, -1 do
        if candidates[i].water == 0 and candidates[i].steam == 0 then table.remove(candidates, i) end
    end
    collectTubs(player, cell, candidates)
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    client.selected = {}
    local snapshot = { clock = client.clock }
    for i = math.min(LIMIT, #candidates), 1, -1 do
        local entry = candidates[i]
        if entry.water > 0 or entry.steam > 0 then
            client.selected[entry.square] = true
            snapshot[#snapshot + 1] = entry
        end
    end
    api.update(snapshot)
end

Events.OnObjectAdded.Add(client.add)
Events.OnObjectAboutToBeRemoved.Add(client.remove)
Events.LoadGridsquare.Add(client.loadSquare)
Events.OnTick.Add(client.tick)
Events.OnTickEvenPaused.Add(client.publish)
Events.OnMainMenuEnter.Add(client.clear)
