-- ==========================================
-- CastBar.lua: 把称谓反映到自己的施法条
-- ==========================================
-- 与 Overrides 共用“应用到游戏内提示/施法条”开关。
-- 只改玩家自己的施法条文字；不碰目标条、姓名版或单位框架。
--
-- 已知施法条：
--   PlayerCastingBarFrame         暴雪默认
--   CastingBarFrame               老内核的默认名
--   AzeriteUnitFramePlayerCastBar AzeriteUI 的玩家施法条
-- 有些第三方施法条不把文字挂在固定字段上，所以除了常见字段，
-- 还会扫描框架自带/子框架的文字区域，找“当前正在施放的法术名”并替换。
-- 读不到/改不了一律 pcall 跳过，不影响游戏。

local TEXT_FIELDS = {
    "Text", "CastBarText", "castBarText", "TextString", "text",
    "SpellName", "spellName", "Label", "label", "CastName", "castName",
}

local BAR_NAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "AzeriteUnitFramePlayerCastBar" }

local hasSecretAPI = type(issecretvalue) == "function"
local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local lastInfo = { spellID = nil, name = nil, alias = nil }

local function FindText(frame)
    if not frame then return nil end
    for _, key in ipairs(TEXT_FIELDS) do
        local ok, fs = pcall(function() return frame[key] end)
        if ok and fs and fs.SetText then return fs end
    end
    return nil
end

-- 扫描框架自带的文字区域（以及一层子框架），
-- 只有内容等于“当前施法官方名”的区域才会被改成别名，避免误改计时数字。
local function SetMatchingRegions(frame, officialName, alias, depth)
    if not officialName or depth > 2 or not frame then return end

    local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
    if okRegions then
        for _, region in ipairs(regions) do
            if region and region.SetText and region.GetText then
                local okText, text = pcall(region.GetText, region)
                if okText and text and not IsSecret(text) then
                    local okMatch, matched = pcall(function()
                        local plain = StripColorCodes(text)
                        if plain == "" then return false end
                        if plain == officialName then return true end
                        local base = plain:match("^([^（(]+)")
                        return base == officialName
                    end)
                    if okMatch and matched then
                        pcall(region.SetText, region, alias)
                    end
                end
            end
        end
    end

    local okChildren, children = pcall(function() return { frame:GetChildren() } end)
    if okChildren then
        for _, child in ipairs(children) do
            SetMatchingRegions(child, officialName, alias, depth + 1)
        end
    end
end

local function ApplyAlias(alias, officialName, force)
    if not alias then return end
    if not force and not (AP_TooltipAlias and AP_TooltipAlias.IsEnabled and AP_TooltipAlias.IsEnabled()) then return end

    for _, barName in ipairs(BAR_NAMES) do
        local bar = _G[barName]
        if bar and bar.IsShown and bar:IsShown() then
            local fs = FindText(bar)
            if fs then pcall(fs.SetText, fs, alias) end
            SetMatchingRegions(bar, officialName, alias, 0)
        end
    end
end

-- 判断玩家是否还在读条/引导；只比 nil，不读 secret 内容
local function IsPlayerCasting()
    local ok1, name1 = pcall(UnitCastingInfo, "player")
    if ok1 and name1 then return true end
    local ok2, name2 = pcall(UnitChannelInfo, "player")
    if ok2 and name2 then return true end
    return false
end

local currentAlias, currentOfficialName, currentForce, sinceLastApply = nil, nil, false, 0

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
    if not currentAlias then
        self:Hide()
        return
    end

    sinceLastApply = sinceLastApply + elapsed
    if sinceLastApply < 0.1 then return end
    sinceLastApply = 0

    if not IsPlayerCasting() then
        currentAlias, currentOfficialName, currentForce = nil, nil, false
        self:Hide()
        return
    end

    ApplyAlias(currentAlias, currentOfficialName, currentForce)
end)

local function StartAlias(alias, officialName, force)
    currentAlias, currentOfficialName, currentForce = alias, officialName, force and true or false
    sinceLastApply = 0
    ApplyAlias(alias, officialName, currentForce) -- 先立刻试一次，之后由 ticker 持续压住刷新
    ticker:Show()
end

local function StopAlias()
    currentAlias, currentOfficialName, currentForce = nil, nil, false
    sinceLastApply = 0
    ticker:Hide()
end

local function GetCastingName(event)
    local ok, name
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        ok, name = pcall(UnitChannelInfo, "player")
    else
        ok, name = pcall(UnitCastingInfo, "player")
    end
    if ok then return name end
    return nil
end

local frame = CreateFrame("Frame")
local function SafeRegister(event)
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("UNIT_SPELLCAST_START")
SafeRegister("UNIT_SPELLCAST_CHANNEL_START")
SafeRegister("UNIT_SPELLCAST_STOP")
SafeRegister("UNIT_SPELLCAST_CHANNEL_STOP")
SafeRegister("UNIT_SPELLCAST_FAILED")
SafeRegister("UNIT_SPELLCAST_INTERRUPTED")

frame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        StopAlias()
        return
    end

    -- 核心技能 15 级后改的名优先级最高：即使 tooltip 开关关闭，施法条也显示新名字
    local force = false
    local spotlightDB = AP_DB and AP_DB.spotlight
    local coreSpell = spotlightDB and spotlightDB.coreSpell
    local coreAlias = spotlightDB and spotlightDB.coreAlias
    if coreSpell and coreSpell ~= "" and coreAlias and coreAlias ~= ""
        and AP_Spotlight and AP_Spotlight.IsCoreSpell and spellID then
        local okCore, isCore = pcall(AP_Spotlight.IsCoreSpell, spellID)
        if okCore and isCore then force = true end
    end

    local enabledNow = AP_TooltipAlias and AP_TooltipAlias.IsEnabled and AP_TooltipAlias.IsEnabled()
    if not enabledNow and not force then
        StopAlias()
        return
    end

    local alias, name, officialName
    if force then
        alias = coreAlias
        officialName = coreSpell
    else
        -- 新客户端事件参数里直接带 spellID
        if spellID and AP_TooltipAlias.GetAliasForID then
            alias = AP_TooltipAlias.GetAliasForID(spellID)
        end
        if spellID and AP_TooltipAlias.GetNameForID then
            local n = AP_TooltipAlias.GetNameForID(spellID)
            if n and not IsSecret(n) then officialName = n end
        end
    end

    -- 旧客户端或参数缺失时，用当前施法名称兜底
    if not alias then
        name = GetCastingName(event)
        if name and not IsSecret(name) then
            if AP_TooltipAlias.GetAliasByName then
                alias = AP_TooltipAlias.GetAliasByName(name)
            end
            officialName = officialName or name
        end
    end

    if IsSecret(name) then name = "<secret>" end
    lastInfo = { spellID = spellID, name = officialName or name, alias = alias }

    if alias then
        StartAlias(alias, officialName, force)
    else
        StopAlias()
    end
end)

AP_CastBar = {
    Debug = function()
        local parts = {}
        for _, barName in ipairs(BAR_NAMES) do
            local bar = _G[barName]
            if bar then
                local fields = {}
                for _, key in ipairs(TEXT_FIELDS) do
                    local ok, fs = pcall(function() return bar[key] end)
                    if ok and fs and fs.SetText then table.insert(fields, key) end
                end

                local regionTexts = {}
                local okRegions, regions = pcall(function() return { bar:GetRegions() } end)
                if okRegions then
                    for _, region in ipairs(regions) do
                        local okType, objType = pcall(function() return region:GetObjectType() end)
                        if okType and objType == "FontString" then
                            local okText, t = pcall(region.GetText, region)
                            if okText then
                                if IsSecret(t) then t = "<secret>" end
                                table.insert(regionTexts, tostring(t))
                            end
                        end
                    end
                end

                local okShown, shown = pcall(function() return bar:IsShown() end)
                table.insert(parts, string.format("%s 存在，显示=%s，文字字段=%s，区域文字=[%s]",
                    barName, tostring(okShown and shown),
                    #fields > 0 and table.concat(fields, "/") or "无",
                    table.concat(regionTexts, " | ")))
            else
                table.insert(parts, barName .. " 不存在")
            end
        end
        print("|cffffd700[AP]|r " .. table.concat(parts, "；"))
        print(string.format("|cffffd700[AP]|r 最近施法 id=%s name=%s alias=%s",
            tostring(lastInfo.spellID), tostring(lastInfo.name), tostring(lastInfo.alias)))
    end,
}
