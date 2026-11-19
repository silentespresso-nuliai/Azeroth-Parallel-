-- ==========================================
-- Overrides.lua: 把称谓“反映”到游戏内鼠标提示（第一层）
-- ==========================================
-- 安全边界：
--   1. 不替换 GetSpellInfo 这类全局 API；
--   2. 只包装 GameTooltip 的几个显示方法，在原函数执行完之后改第一行；
--   3. 只影响自己的鼠标提示，别人看不到；
--   4. 只在勾选开关时生效，默认关闭。
--
-- 新客户端（11.x/12.x）会把 tooltip 文本标记成 secret string，
-- 插件不能读取/比较/替换它。所以这里优先用“法术 ID → 官方名”查表，
-- 文本路径全部套 pcall；读不到就安静跳过，绝不把错误抛给游戏。

local enabled = false
local cachedKey
local cachedMap

local hasSecretAPI = type(issecretvalue) == "function"

-- 判断一个值是不是客户端不让我们读的 secret string
local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

-- 取当前职业/流派的“官方名 → 专属称呼”映射。
-- 切流派后 key 变化，下次悬停时会自动重建。
local function BuildAliasMap()
    local classToken = AP_DB.flavor.currentClass
    local factionID = AP_DB.flavor.currentFaction
    if not classToken or not factionID then return nil end

    local key = tostring(classToken) .. ":" .. tostring(factionID)
    if cachedKey == key and cachedMap then return cachedMap end

    local map = {}
    if AP_FlavorManager and AP_FlavorManager.GetTermList then
        local list = AP_FlavorManager.GetTermList(classToken, factionID)
        if list then
            for _, term in ipairs(list) do
                if term.official and term.alias then
                    map[term.official] = term.alias
                end
            end
        end
    end

    cachedKey, cachedMap = key, map
    return map
end

-- 别名颜色：用职业色，和左侧书签保持一致；客户端没有职业色就退回金色
local function GetAliasColor()
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[AP_DB.flavor.currentClass]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0.25
end

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- 按官方名查别名；name 可能是 secret string 或格式异常，全部兜住
local function LookupAliasByName(name)
    if not name or IsSecret(name) then return nil end
    local map = BuildAliasMap()
    if not map then return nil end

    local ok, alias = pcall(function()
        local found = map[name]
        if not found then
            local base = name:match("^([^（(]+)")
            if base then found = map[base] end
        end
        return found
    end)
    if ok then return alias end
    return nil
end

-- 通过法术 ID 拿官方名：新 API 优先，旧 API 兜底
local function GetSpellNameByID(spellID)
    if not spellID then return nil end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and info.name then
            return info.name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return name end
    end
    return nil
end

-- 只改第一行的文字和颜色，不碰 tooltip 的其他行
local function SetTooltipLine(alias)
    local line = _G["GameTooltipTextLeft1"]
    if not line then return false end

    local ok = pcall(line.SetText, line, alias)
    if not ok then return false end
    pcall(line.SetTextColor, line, GetAliasColor())
    return true
end

-- 主路径：法术 ID → 官方名 → 别名
local function ApplyAliasByID(spellID)
    if not enabled or not spellID then return false end
    local name = GetSpellNameByID(spellID)
    if not name then return false end
    local alias = LookupAliasByName(name)
    if not alias then return false end
    return SetTooltipLine(alias)
end

-- 兜底路径：直接读 tooltip 第一行。
-- 新客户端这里多半会读到 secret string，检测到就直接跳过。
local function ApplyAliasByText()
    if not enabled then return end
    local line = _G["GameTooltipTextLeft1"]
    if not line then return end

    local ok, text = pcall(line.GetText, line)
    if not ok or type(text) ~= "string" or IsSecret(text) then return end

    pcall(function()
        text = StripColorCodes(text)
        local alias = LookupAliasByName(text)
        if alias then SetTooltipLine(alias) end
    end)
end

-- 从 tooltip 方法的参数里尽量提取法术 ID
local function ExtractSpellID(methodName, a1, a2)
    if methodName == "SetSpellByID" or methodName == "SetSpell" then
        return tonumber(a1)

    elseif methodName == "SetHyperlink" then
        if type(a1) == "string" then
            return tonumber(a1:match("spell:(%d+)"))
        end

    elseif methodName == "SetAction" then
        if GetActionInfo then
            local ok, actionType, id = pcall(GetActionInfo, a1)
            if ok and actionType == "spell" then return id end
        end

    elseif methodName == "SetSpellbookItem" then
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, a1, a2)
            if ok and type(info) == "table" then
                return info.spellID or info.actionID
            end
        end
        if GetSpellBookItemInfo then
            local ok, itemType, spellID = pcall(GetSpellBookItemInfo, a1, a2)
            if ok and itemType == "SPELL" then return spellID end
        end
    end

    return nil
end

-- 只包装 GameTooltip 实例的方法；不碰任何全局取名字的函数。
--
-- 节流：同一个技能在极短时间内会被多个 tooltip 方法重复处理
-- （例如 SetSpellByID 之后紧跟着 SetHyperlink），没必要每次都查表、改字。
-- 这里按“技能 ID + 50ms”去重：同一技能只处理第一次，换技能立即处理，
-- 不会像全局时间节流那样漏掉玩家快速划过的新技能。
local lastAttemptID, lastAttemptAt = nil, 0

local function HookTooltipMethod(methodName)
    local orig = GameTooltip[methodName]
    if type(orig) ~= "function" then return end

    GameTooltip[methodName] = function(self, ...)
        local result = orig(self, ...)

        if enabled then
            local ok, spellID = pcall(ExtractSpellID, methodName, ...)
            if ok and spellID then
                local now = (type(GetTime) == "function" and GetTime()) or 0
                if lastAttemptID == spellID and now - lastAttemptAt < 0.05 then
                    return result
                end
                lastAttemptID, lastAttemptAt = spellID, now
            end
            if not (ok and ApplyAliasByID(spellID)) then
                ApplyAliasByText()
            end
        end

        return result
    end
end

-- 技能书、动作条、buff 图标、聊天里的法术链接，最终都会走到这几个方法
HookTooltipMethod("SetSpellByID")
HookTooltipMethod("SetSpell")
HookTooltipMethod("SetSpellbookItem")
HookTooltipMethod("SetAction")
HookTooltipMethod("SetHyperlink")
HookTooltipMethod("SetUnitBuff")
HookTooltipMethod("SetUnitDebuff")
HookTooltipMethod("SetUnitAura")

local function SetEnabled(value)
    enabled = value and true or false
    cachedKey = nil -- 下次悬停时按当前流派重建映射
    -- 开关刚打开时，如果提示正开着，立刻把当前这一条也换掉
    if enabled and GameTooltip:IsShown() then
        ApplyAliasByText()
    end
end

AP_TooltipAlias = {
    SetEnabled = SetEnabled,
    IsEnabled = function() return enabled end,
}

-- 登录时按存档恢复开关状态
SetEnabled(AP_DB.flavor.tooltipAlias)
