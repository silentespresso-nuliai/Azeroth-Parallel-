-- ==========================================
-- Aura.lua: 核心 40 级 · 流派施放特效（方案 A：固定屏幕位置）
-- ==========================================
-- 规则：
--   1. 释放核心技能并成功触发高光时，同时开启本流派特效；
--   2. 特效一直存在，直到脱战（PLAYER_REGEN_ENABLED）才消失；
--   3. 触发间隔沿用高光的「释放间距」，不单独计时；
--   4. 右页「40 级 · 施放特效」开关控制是否允许出现；
--   5. 试放时强制预览 6 秒，方便低等级查看。
-- 注意：这是 2D UI 覆盖层，不是 3D 粒子，也不会修改游戏法术特效。

AP_DB = AP_DB or {}

local function EnsureDB()
    AP_DB.spotlight = AP_DB.spotlight or {}
    if AP_DB.spotlight.auraEnabled == nil then
        AP_DB.spotlight.auraEnabled = true
    end
end
EnsureDB()

-- ==========================================
-- 流派 → 主题表
-- ==========================================
-- color: 主色；styles: 用哪几组粒子（orbit / rise / fall / pulse）
local DEFAULT_THEME = { name = "冰霜", color = { 0.55, 0.82, 1 }, styles = { "orbit", "rise" } }

local THEMES = {
    DRUID = {
        Cenarius = { name = "自然之息", color = { 0.35, 0.85, 0.5 }, styles = { "fall", "orbit" } },
        Runetotem = { name = "图腾符文", color = { 0.85, 0.55, 0.2 }, styles = { "orbit", "pulse" } },
        Loa = { name = "洛阿巫毒", color = { 0.6, 0.3, 0.8 }, styles = { "rise", "orbit" } },
        Nightclaw = { name = "月影", color = { 0.55, 0.4, 0.85 }, styles = { "fall", "orbit" } },
    },
    PALADIN = {
        SilverHand = { name = "圣光", color = { 1, 0.85, 0.45 }, styles = { "rise", "pulse" } },
        Sunwalker = { name = "烈日", color = { 1, 0.55, 0.15 }, styles = { "rise", "orbit" } },
        UndeadPaladin = { name = "灰烬", color = { 0.6, 0.2, 0.15 }, styles = { "fall", "pulse" } },
        LoneOath = { name = "孤灯", color = { 0.75, 0.8, 0.9 }, styles = { "orbit", "pulse" } },
    },
    PRIEST = {
        HolyChurch = { name = "圣辉", color = { 1, 0.9, 0.55 }, styles = { "rise", "pulse" } },
        MoonPriestess = { name = "月华", color = { 0.65, 0.8, 1 }, styles = { "fall", "orbit" } },
        ShadowPriest = { name = "暗影", color = { 0.45, 0.2, 0.65 }, styles = { "orbit", "fall" } },
        VoodooPriest = { name = "巫毒", color = { 0.45, 0.8, 0.35 }, styles = { "rise", "orbit" } },
    },
    WARLOCK = {
        StandardWarlock = { name = "邪能", color = { 0.5, 0.9, 0.25 }, styles = { "rise", "orbit" } },
        Necromancer = { name = "亡骨", color = { 0.75, 0.85, 0.7 }, styles = { "fall", "rise" } },
        ShadowCouncil = { name = "暗影", color = { 0.4, 0.2, 0.6 }, styles = { "orbit", "pulse" } },
        SuccubusFan = { name = "魅惑", color = { 0.95, 0.45, 0.8 }, styles = { "fall", "orbit" } },
        LegionCultist = { name = "军团邪火", color = { 0.7, 1, 0.2 }, styles = { "rise", "pulse" } },
    },
    MAGE = {
        StandardMage = { name = "奥术", color = { 0.4, 0.6, 1 }, styles = { "orbit", "pulse" } },
        WildMage = { name = "野火", color = { 1, 0.55, 0.2 }, styles = { "rise", "orbit" } },
        MercenaryMage = { name = "铁火", color = { 0.8, 0.65, 0.45 }, styles = { "rise", "pulse" } },
    },
    WARRIOR = {
        StandardWarrior = { name = "怒气", color = { 0.95, 0.65, 0.2 }, styles = { "rise", "pulse" } },
        HordeWarrior = { name = "血怒", color = { 0.8, 0.15, 0.15 }, styles = { "rise", "orbit" } },
        MercenaryWarrior = { name = "铁血", color = { 0.6, 0.35, 0.3 }, styles = { "rise", "pulse" } },
        TavernBrawler = { name = "酒气", color = { 0.9, 0.7, 0.25 }, styles = { "rise", "orbit" } },
    },
    ROGUE = {
        SI7 = { name = "暗影", color = { 0.4, 0.55, 0.75 }, styles = { "orbit", "pulse" } },
        Uncrowned = { name = "暗紫", color = { 0.5, 0.3, 0.7 }, styles = { "fall", "orbit" } },
        Pirate = { name = "海火药", color = { 0.3, 0.6, 0.8 }, styles = { "rise", "fall" } },
        Scoundrel = { name = "毒药", color = { 0.55, 0.75, 0.25 }, styles = { "rise", "orbit" } },
    },
    HUNTER = {
        Ranger = { name = "自然", color = { 0.35, 0.7, 0.35 }, styles = { "fall", "orbit" } },
        Rifleman = { name = "火药", color = { 0.9, 0.55, 0.2 }, styles = { "rise", "pulse" } },
        ShadowHunter = { name = "巫毒", color = { 0.55, 0.35, 0.75 }, styles = { "orbit", "rise" } },
        WildHunter = { name = "荒野", color = { 0.6, 0.5, 0.3 }, styles = { "fall", "orbit" } },
    },
    SHAMAN = {
        StandardShaman = { name = "元素火", color = { 1, 0.5, 0.2 }, styles = { "rise", "orbit" } },
        EarthenRing = { name = "大地", color = { 0.6, 0.7, 0.3 }, styles = { "orbit", "rise" } },
    },
}

-- ==========================================
-- 粒子层
-- ==========================================
local frame = CreateFrame("Frame", "AP_AuraFrame", UIParent)
frame:SetSize(420, 300)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
frame:SetFrameStrata("BACKGROUND")
frame:EnableMouse(false)
frame:Hide()

local groups = { orbit = {}, rise = {}, fall = {}, pulse = {} }

local function NewTexture(texture, size)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(texture)
    tex:SetBlendMode("ADD")
    tex:SetSize(size, size)
    tex:SetVertexColor(0.55, 0.82, 1, 1)
    tex:SetAlpha(0)
    tex:Hide()
    return tex
end

for i = 1, 12 do
    groups.orbit[i] = {
        tex = NewTexture("Interface\\Cooldown\\star4", 10 + math.random(0, 14)),
        angle = (i / 12) * math.pi * 2,
        speed = 0.35 + math.random() * 0.35,
        rx = 100 + math.random(0, 45),
        ry = 34 + math.random(0, 18),
        alpha = 0.45 + math.random() * 0.35,
    }
end

for i = 1, 8 do
    groups.rise[i] = {
        tex = NewTexture(
            (i % 2 == 0) and "Interface\\Cooldown\\star4" or "Interface\\Buttons\\WHITE8x8",
            6 + math.random(0, 8)
        ),
        x = -80 + math.random(0, 160),
        speed = 20 + math.random() * 24,
        phase = math.random(),
        spin = (math.random() - 0.5) * 2,
    }
    groups.fall[i] = {
        tex = NewTexture(
            (i % 2 == 0) and "Interface\\Cooldown\\star4" or "Interface\\Buttons\\WHITE8x8",
            6 + math.random(0, 10)
        ),
        x = -90 + math.random(0, 180),
        speed = 20 + math.random() * 24,
        phase = math.random(),
        spin = (math.random() - 0.5) * 2,
    }
end

for i = 1, 3 do
    groups.pulse[i] = {
        tex = NewTexture("Interface\\Cooldown\\star4", 90 + math.random(0, 40)),
        phase = (i - 1) / 3,
        speed = 0.35 + math.random() * 0.15,
    }
end

local themeColor = { 0.55, 0.82, 1 }
local activeStyles = { orbit = false, rise = false, fall = false, pulse = false }

local function ApplyTheme(theme)
    theme = theme or DEFAULT_THEME
    themeColor = theme.color or DEFAULT_THEME.color
    for style, list in pairs(groups) do
        activeStyles[style] = false
        for _, p in ipairs(list) do
            p.tex:Hide()
            p.tex:SetAlpha(0)
        end
    end
    for _, style in ipairs(theme.styles or DEFAULT_THEME.styles) do
        if groups[style] then
            activeStyles[style] = true
            for _, p in ipairs(groups[style]) do
                p.tex:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
                p.tex:Show()
            end
        end
    end
end

local elapsedTotal = 0
local updateAcc = 0

frame:SetScript("OnUpdate", function(_, elapsed)
    updateAcc = updateAcc + elapsed
    if updateAcc < 0.03 then return end
    local dt = updateAcc
    updateAcc = 0
    elapsedTotal = elapsedTotal + dt

    if activeStyles.orbit then
        for i, p in ipairs(groups.orbit) do
            local a = p.angle + elapsedTotal * p.speed
            local x = math.cos(a) * p.rx
            local y = math.sin(a) * p.ry + math.sin(elapsedTotal * 1.3 + i) * 4
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(p.alpha + 0.15 * math.sin(elapsedTotal * 2 + i))
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, a) end
        end
    end

    if activeStyles.rise then
        for i, p in ipairs(groups.rise) do
            local prog = (p.phase + elapsedTotal * p.speed / 220) % 1
            local y = -110 + prog * 220
            local x = p.x + math.sin(elapsedTotal * 1.6 + i) * 10
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(math.sin(prog * math.pi) * 0.75)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * p.spin) end
        end
    end

    if activeStyles.fall then
        for i, p in ipairs(groups.fall) do
            local prog = (p.phase + elapsedTotal * p.speed / 240) % 1
            local y = 110 - prog * 220
            local x = p.x + math.sin(elapsedTotal * 1.4 + i) * 14
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(math.sin(prog * math.pi) * 0.7)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * p.spin) end
        end
    end

    if activeStyles.pulse then
        for i, p in ipairs(groups.pulse) do
            local prog = (p.phase + elapsedTotal * p.speed) % 1
            local scale = 0.65 + prog * 1.2
            p.tex:SetPoint("CENTER", frame, "CENTER", 0, -16)
            p.tex:SetScale(scale)
            p.tex:SetAlpha((1 - prog) * 0.22)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * 0.4 + i) end
        end
    end
end)

-- ==========================================
-- 触发 / 开关 / 脱战收起
-- ==========================================
local triggerToken = 0

local function IsUnlocked()
    return AP_Spotlight and AP_Spotlight.GetCoreLevel and AP_Spotlight.GetCoreLevel() >= 40
end

local function CurrentClass()
    local ok, _, token = pcall(UnitClass, "player")
    if ok and token then return token end
    return AP_DB.flavor and AP_DB.flavor.currentClass
end

local function Trigger(classToken, factionID, preview, previewDuration)
    -- 50 级头顶特效独立叠加，不覆盖 40 级环绕
    if AP_HeadAura and AP_HeadAura.Trigger then
        AP_HeadAura.Trigger(classToken, factionID, preview, previewDuration)
    end
    EnsureDB()
    if not preview then
        if not AP_DB.spotlight.auraEnabled then return end
        if not IsUnlocked() then return end
    end

    classToken = classToken or CurrentClass()
    factionID = factionID or (AP_DB.flavor and AP_DB.flavor.currentFaction)
    local theme = (THEMES[classToken] and THEMES[classToken][factionID]) or DEFAULT_THEME
    ApplyTheme(theme)

    triggerToken = triggerToken + 1
    local token = triggerToken
    frame:Show()

    -- 预览固定 6 秒；实战中一直留到脱战；脱战状态下释放则 6 秒后收起
    if preview then
        if C_Timer and C_Timer.After then
            C_Timer.After(previewDuration or 6, function()
                if triggerToken == token then frame:Hide() end
            end)
        end
    else
        local inCombat = (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")) and true or false
        if not inCombat and C_Timer and C_Timer.After then
            C_Timer.After(6, function()
                if triggerToken == token
                    and not (type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")) then
                    frame:Hide()
                end
            end)
        end
    end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    triggerToken = triggerToken + 1
    frame:Hide()
end)

AP_Aura = {
    Trigger = Trigger,
    GetTheme = function(classToken, factionID)
        return (THEMES[classToken] and THEMES[classToken][factionID]) or DEFAULT_THEME
    end,
    IsUnlocked = IsUnlocked,
    IsEnabled = function()
        EnsureDB()
        return AP_DB.spotlight.auraEnabled
    end,
    SetEnabled = function(value)
        EnsureDB()
        AP_DB.spotlight.auraEnabled = value and true or false
        if not AP_DB.spotlight.auraEnabled then
            triggerToken = triggerToken + 1
            frame:Hide()
        end
    end,
    Toggle = function()
        EnsureDB()
        AP_DB.spotlight.auraEnabled = not AP_DB.spotlight.auraEnabled
        if not AP_DB.spotlight.auraEnabled then
            triggerToken = triggerToken + 1
            frame:Hide()
        end
        if AP_DB.spotlight.auraEnabled and not IsUnlocked() then
            print("|cffffd700[AP]|r 施放特效需要核心 Lv.40。")
        else
            print("|cffffd700[AP]|r 施放特效：" .. (AP_DB.spotlight.auraEnabled and "已开启" or "已关闭"))
        end
        if AP_Spotlight and AP_Spotlight.RefreshCoreUI then AP_Spotlight.RefreshCoreUI() end
    end,
    Preview = function(classToken, factionID, duration)
        Trigger(
            classToken or CurrentClass(),
            factionID or (AP_DB.flavor and AP_DB.flavor.currentFaction),
            true,
            duration
        )
    end,
}

-- 本文件在 Spotlight 之后加载，补刷一次右页「施放特效」开关状态
if AP_Spotlight and AP_Spotlight.RefreshCoreUI then
    AP_Spotlight.RefreshCoreUI()
end
