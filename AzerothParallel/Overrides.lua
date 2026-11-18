-- ==========================================
-- Overrides.lua: 把称谓“反映”到游戏内鼠标提示（第一层）
-- ==========================================
-- 安全边界（这是本文件存在的全部理由）：
--   1. 绝不替换 GetSpellInfo / GetSpellBookItemName 这类全局 API；
--   2. 只包装 GameTooltip 的几个显示方法，在原函数执行完之后改第一行文字；
--   3. 只影响自己的鼠标提示，别人看不到，也不会改变宏命令和服务器数据；
--   4. 只有在“称谓典籍”里勾选开关时才生效，默认关闭。
--
-- 开关状态：AP_DB.flavor.tooltipAlias，由 Flavor.lua 右页的复选框写入。

local enabled = false
local cachedKey
local cachedMap

-- 取当前职业/流派的“官方名 → 专属称呼”映射。
-- 切流派后 key 变化，下次悬停时会自动重建，不会残留上一个流派的称呼。
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

-- 去掉文本里可能夹带的颜色代码，避免查表时对不上
local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ApplyAliasToTooltip()
    if not enabled then return end
    local line = _G["GameTooltipTextLeft1"]
    if not line then return end

    local text = line:GetText()
    if not text or text == "" then return end
    text = StripColorCodes(text)

    local map = BuildAliasMap()
    if not map then return end

    local alias = map[text]
    -- 有些提示第一行是“技能名(等级 X)”，去掉括号再查一次
    if not alias then
        local base = text:match("^([^（(]+)")
        if base then alias = map[base] end
    end
    if not alias then return end

    line:SetText(alias)
    line:SetTextColor(GetAliasColor())
end

-- 只包装 GameTooltip 实例的方法；不碰任何全局取名字的函数。
local function HookTooltipMethod(methodName)
    local orig = GameTooltip[methodName]
    if type(orig) ~= "function" then return end
    GameTooltip[methodName] = function(self, ...)
        local result = orig(self, ...)
        ApplyAliasToTooltip()
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
        ApplyAliasToTooltip()
    end
end

AP_TooltipAlias = {
    SetEnabled = SetEnabled,
    IsEnabled = function() return enabled end,
}

-- 登录时按存档恢复开关状态
SetEnabled(AP_DB.flavor.tooltipAlias)
