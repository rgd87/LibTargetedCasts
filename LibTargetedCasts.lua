--[================[
LibTargetedCasts
Author: d87
--]================]


local MAJOR, MINOR = "LibTargetedCasts", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end


lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

lib.frame = lib.frame or CreateFrame("Frame")

lib.data = lib.data or {}

local f = lib.frame
local callbacks = lib.callbacks
local data = lib.data

local castsToRemove = {}
-- local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local GetTime = GetTime
local tinsert = tinsert
local UnitPlayerOrPetInParty = UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = UnitPlayerOrPetInRaid
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

f:SetScript("OnEvent", function(self, event, ...)
    return self[event](self, event, ...)
end)

local refreshCastTable = function(tbl, ...)
    local numArgs = select("#", ...)
    for i=1, numArgs do
        tbl[i] = select(i, ...)
    end
end

local IsGroupUnit = function(unit)
    return UnitExists(unit) and (UnitIsUnit(unit, "player") or UnitPlayerOrPetInParty(unit) or UnitPlayerOrPetInRaid(unit))
end

local previousEvent
local previousUnit = "player"
local previousTime = 0
function f:UNIT_SPELLCAST_COMMON_START(event, castType, srcUnit, castID, spellID)
    if not UnitIsFriend("player", srcUnit) then
        local now = GetTime()
        if previousEvent == event and previousTime == now and UnitIsUnit(previousUnit, srcUnit) then return end
        previousEvent = event
        previousUnit = srcUnit
        previousTime = now

        local dstUnit = srcUnit.."target"
        -- print(spellID, GetSpellInfo(spellID))
        if IsGroupUnit(dstUnit) then
            local srcGUID = UnitGUID(srcUnit)
            local dstGUID = UnitGUID(dstUnit)

            local casts = data[dstGUID]
            if not casts then
                data[dstGUID] = {}
                casts = data[dstGUID]
            end

            local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID
            if castType == "CAST" then
                name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(srcUnit)
            else
                name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(srcUnit)
                if name then
                    castID = srcGUID..spellID
                end
            end
            if not castID then return end

            if casts[castID] then
                refreshCastTable(casts[castID], srcGUID, dstGUID, castType, name, text, texture, startTimeMS/1000, endTimeMS/1000, isTradeSkill, castID, notInterruptible, spellID)
            else
                casts[castID] = { srcGUID, dstGUID, castType, name, text, texture, startTimeMS/1000, endTimeMS/1000, isTradeSkill, castID, notInterruptible, spellID }
            end
            -- callbacks:Fire("SPELLCAST_START", dstUnit, dstGUID, srcUnit, castID, spellID)
            callbacks:Fire("SPELLCAST_UPDATE", dstGUID)
        end
    end
end

function f:UNIT_SPELLCAST_START(event, ...)
    local castType = "CAST"
    return self:UNIT_SPELLCAST_COMMON_START(event, castType, ...)
end
f.UNIT_SPELLCAST_DELAYED = f.UNIT_SPELLCAST_START

function f:UNIT_SPELLCAST_CHANNEL_START(event, ...)
    local castType = "CHANNEL"
    return self:UNIT_SPELLCAST_COMMON_START(event, castType, ...)
end
f.UNIT_SPELLCAST_CHANNEL_UPDATE = f.UNIT_SPELLCAST_CHANNEL_START


function f:UNIT_SPELLCAST_COMMON_STOP(event, castType, srcUnit, castID, spellID)
    if not UnitIsFriend("player", srcUnit) then
        local now = GetTime()
        if previousEvent == event and previousTime == now and UnitIsUnit(previousUnit, srcUnit) then return end
        previousEvent = event
        previousUnit = srcUnit
        previousTime = now

        -- if castID == previousCastID then return end
        -- previousCastID = castID -- remove duplicates

        -- UnitPlayerOrPetInParty("unit") - Returns 1 if the specified unit/pet is a member of the player's party, nil otherwise (returns nil for "player" and "pet")
        -- UnitPlayerOrPetInRaid("unit") - Returns 1 if the specified unit/pet is a member of the player's raid, nil otherwise (returns nil for "player" and "pet")
        -- if UnitExists(dstUnit) and UnitIsPlayer(dstUnit) then
        if castType == "CHANNEL" and not castID then
            local srcGUID = UnitGUID(srcUnit)
            castID = srcGUID..spellID
        end

        for dstGUID, casts in pairs(data) do
            if casts[castID] then
                -- callbacks:Fire("SPELLCAST_STOP", dstUnit, dstGUID, srcUnit, castID, spellID)
                casts[castID] = nil
                callbacks:Fire("SPELLCAST_UPDATE", dstGUID)
                return
            end
        end
    end
end

function f:UNIT_SPELLCAST_STOP(event, ...)
    local castType = "CAST"
    return self:UNIT_SPELLCAST_COMMON_STOP(event, castType, ...)
end
f.UNIT_SPELLCAST_FAILED = f.UNIT_SPELLCAST_STOP
f.UNIT_SPELLCAST_FAILED_QUIET = f.UNIT_SPELLCAST_STOP
f.UNIT_SPELLCAST_INTERRUPTED = f.UNIT_SPELLCAST_STOP

function f:UNIT_SPELLCAST_CHANNEL_STOP(event, ...)
    local castType = "CHANNEL"
    return self:UNIT_SPELLCAST_COMMON_STOP(event, castType, ...)
end

function f:UNIT_TARGET(event, srcUnit)
    if not UnitIsFriend("player", srcUnit) then
        local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(srcUnit)
        if not castID then
            name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(srcUnit)
            if name then
                local srcGUID = UnitGUID(srcUnit)
                castID = srcGUID..spellID
            end
        end
        if castID then
            local srcGUID, dstGUID_old = lib:FindIncomingCastByID(castID)
            if dstGUID_old then
                local dstUnit = srcUnit.."target"
                local dstGUID_new = UnitGUID(dstUnit)

                if dstGUID_old ~= dstGUID_new then
                    local castInfo = data[dstGUID_old][castID]
                    data[dstGUID_old][castID] = nil
                    callbacks:Fire("SPELLCAST_UPDATE", dstGUID_old)

                    if IsGroupUnit(dstUnit) then
                        local casts = data[dstGUID_new]
                        if not casts then
                            data[dstGUID_new] = {}
                            casts = data[dstGUID_new]
                        end
                        casts[castID] = castInfo
                        callbacks:Fire("SPELLCAST_UPDATE", dstGUID_new)
                    end
                end
            end
        end
    end
end


function f:NAME_PLATE_UNIT_ADDED(event, srcUnit)
    local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(srcUnit)
    if castID then
        return self:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", srcUnit, castID, spellID)
    else
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(srcUnit)
        if spellID then
            return self:UNIT_SPELLCAST_CHANNEL_START("UNIT_SPELLCAST_CHANNEL_START", srcUnit, nil, spellID)
        end
    end
end

local normalUnits = {
    ["target"] = true,
    ["focus"] = true,
    ["boss1"] = true,
    ["boss2"] = true,
    ["boss3"] = true,
    ["boss4"] = true,
    ["boss5"] = true,
    ["arena1"] = true,
    ["arena2"] = true,
    ["arena3"] = true,
    ["arena4"] = true,
    ["arena5"] = true,
}


function f:NAME_PLATE_UNIT_REMOVED(event, srcUnit)
    for unit in pairs(normalUnits) do
        if UnitIsUnit(unit, srcUnit) then
            return
        end
    end

    local srcGUID = UnitGUID(srcUnit)

    for dstGUID, casts in pairs(data) do
        for castID, castInfo in pairs(casts) do
            if castInfo[1] == srcGUID then
                -- local dstUnit = srcUnit.."target"
                -- local srcGUID, dstGUID, name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = unpack(castInfo)
                -- callbacks:Fire("SPELLCAST_STOP", dstUnit, dstGUID, srcUnit, castID, spellID)
                tinsert(castsToRemove, castID)
            end
        end
    end
    self:CleanupCasts()
end

local function PeriodicCleanup()
    local now = GetTime()
    for dstGUID, casts in pairs(data) do
        for castID, castInfo in pairs(casts) do
            local endTime = castInfo[8]
            if now > endTime then
                -- local srcGUID, dstGUID, name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = unpack(castInfo)
                -- callbacks:Fire("SPELLCAST_STOP", nil, dstGUID, nil, castID, spellID)
                tinsert(castsToRemove, castID)
            end
        end
    end
    f:CleanupCasts()
end

function f:CleanupCasts()
    for dstGUID, casts in pairs(data) do
        local removed
        for i, castID in ipairs(castsToRemove) do
            if casts[castID] then
                -- callbacks:Fire("SPELLCAST_STOP", dstUnit, dstGUID, srcUnit, castID, spellID)
                casts[castID] = nil
                removed = true
            end
        end
        if removed then
            callbacks:Fire("SPELLCAST_UPDATE", dstGUID)
        end
    end
    table.wipe(castsToRemove)
end

function lib:GetUnitIncomingCastsTable(unit)
    local unitGUID = UnitGUID(unit)
    return data[unitGUID]
end

-- function lib:GetUnitIncomingCasts(...)
--     self:GetUnitIncomingCastsInternal(...)
--     return unpack(returnArray)
-- end

-- function lib:GetUnitIncomingCastsTable(...)
--     self:GetUnitIncomingCastsInternal(...)
--     return returnArray
-- end

function lib:GetUnitIncomingCastByID(dstGUID, castID)
    local casts = data[dstGUID]
    if casts then
        local castInfo = casts[castID]
        if castInfo then
            return unpack(castInfo)
        end
    end
end

function lib:FindIncomingCastByID(castID)
    for dstGUID, casts in pairs(data) do
        if casts[castID] then
            return unpack(casts[castID])
        end
    end
end

local cleanupTimer
function callbacks.OnUsed()
    -- f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("UNIT_SPELLCAST_START")
    f:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    f:RegisterEvent("UNIT_SPELLCAST_STOP")
    f:RegisterEvent("UNIT_SPELLCAST_FAILED")
    f:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

    f:RegisterEvent("UNIT_TARGET")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    if not cleanupTimer then
        cleanupTimer = C_Timer.NewTicker(10, PeriodicCleanup)
    end
end

function callbacks.OnUnused()
    f:UnregisterAllEvents()
    if cleanupTimer then
        cleanupTimer:Cancel()
    end
end


