-- ==========================================
-- HeadAura.lua: 核心 50 级 · 专精头顶特效
-- ==========================================
-- 与 Aura.lua 的 40 级环绕特效独立：两个可以同时开着。
-- 颜色默认沿用当前流派主题色，形状按当前专精区分；平衡德固定为银白月光。

AP_DB = AP_DB or {}

local function EnsureDB()
    AP_DB.spotlight = AP_DB.spotlight or {}
    if AP_DB.spotlight.headAuraEnabled == nil then
        AP_DB.spotlight.headAuraEnabled = true
    end
end
EnsureDB()

-- ==========================================
-- 专精 → 头顶特效
-- 索引对应游戏里的专精顺序；德鲁伊有 4 个。
-- ==========================================
local DEFAULT_HEAD = { name = "光环", styles = { "ring", "pulse" } }

local HEAD_STYLES = {
    DRUID = {
        -- 平衡德：月牙 + 上升星点 + 从底部/两侧洒下的月光
        [1] = { name = "月穹星环", styles = { "beam", "rise" }, color = { 0.82, 0.9, 1 }, moon = true },
        [2] = { name = "兽爪血痕", styles = { "ring", "rise" }, color = { 0.9, 0.3, 0.2 } },
        [3] = { name = "厚土壁垒", styles = { "ring", "pulse" }, color = { 0.7, 0.55, 0.3 } },
        [4] = { name = "生命花环", styles = { "ring", "rise" }, color = { 0.4, 0.9, 0.5 } },
    },
    PALADIN = {
        [1] = { name = "圣光冠冕", styles = { "ring", "rise" } },
        [2] = { name = "壁垒光环", styles = { "ring", "pulse" } },
        [3] = { name = "审判之刃", styles = { "ring", "rise" }, color = { 1, 0.75, 0.35 } },
    },
    PRIEST = {
        [1] = { name = "圣盾光环", styles = { "ring", "pulse" } },
        [2] = { name = "圣辉冠", styles = { "rise", "pulse" } },
        [3] = { name = "虚空之眼", styles = { "ring", "fall" }, color = { 0.5, 0.25, 0.7 } },
    },
    WARLOCK = {
        [1] = { name = "痛苦之环", styles = { "ring", "fall" }, color = { 0.6, 0.2, 0.5 } },
        [2] = { name = "邪能之角", styles = { "ring", "rise" }, color = { 0.5, 1, 0.2 } },
        [3] = { name = "混沌火冠", styles = { "rise", "pulse" }, color = { 0.8, 0.5, 0.15 } },
    },
    MAGE = {
        [1] = { name = "奥术符文环", styles = { "ring", "pulse" }, color = { 0.45, 0.65, 1 } },
        [2] = { name = "烈焰王冠", styles = { "rise", "pulse" }, color = { 1, 0.5, 0.15 } },
        [3] = { name = "冰晶光环", styles = { "ring", "fall" }, color = { 0.6, 0.85, 1 } },
    },
    WARRIOR = {
        [1] = { name = "刃光冠", styles = { "ring", "rise" }, color = { 0.9, 0.75, 0.5 } },
        [2] = { name = "血怒之冠", styles = { "rise", "pulse" }, color = { 0.9, 0.2, 0.15 } },
        [3] = { name = "铁壁光环", styles = { "ring", "pulse" }, color = { 0.6, 0.6, 0.65 } },
    },
    ROGUE = {
        [1] = { name = "毒刃之环", styles = { "ring", "rise" }, color = { 0.55, 0.8, 0.25 } },
        [2] = { name = "火药光环", styles = { "ring", "fall" }, color = { 0.9, 0.6, 0.25 } },
        [3] = { name = "暗影之眼", styles = { "ring", "fall" }, color = { 0.5, 0.3, 0.7 } },
    },
    HUNTER = {
        [1] = { name = "兽魂之环", styles = { "ring", "rise" }, color = { 0.6, 0.5, 0.3 } },
        [2] = { name = "鹰眼之光", styles = { "ring", "pulse" }, color = { 0.8, 0.75, 0.35 } },
        [3] = { name = "荒野之息", styles = { "ring", "fall" }, color = { 0.55, 0.65, 0.3 } },
    },
    SHAMAN = {
        [1] = { name = "元素之冠", styles = { "rise", "pulse" }, color = { 1, 0.55, 0.2 } },
        [2] = { name = "风暴之环", styles = { "ring", "pulse" }, color = { 0.5, 0.75, 1 } },
        [3] = { name = "生命之泉", styles = { "rise", "ring" }, color = { 0.4, 0.9, 0.7 } },
    },
}

-- ==========================================
-- 头顶粒子层
-- ==========================================
local frame = CreateFrame("Frame", "AP_HeadAuraFrame", UIParent)
frame:SetSize(340, 240)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
frame:SetFrameStrata("BACKGROUND")
frame:EnableMouse(false)
frame:Hide()

local groups = { ring = {}, rise = {}, fall = {}, pulse = {}, beam = {} }

local function NewTexture(texture, width, height)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(texture)
    tex:SetBlendMode("ADD")
    tex:SetSize(width, height)
    tex:SetVertexColor(0.55, 0.82, 1, 1)
    tex:SetAlpha(0)
    tex:Hide()
    return tex
end

for i = 1, 8 do
    groups.ring[i] = {
        tex = NewTexture("Interface\\Cooldown\\star4", 8 + math.random(0, 10), 8 + math.random(0, 10)),
        angle = (i / 8) * math.pi * 2,
        speed = 0.4 + math.random() * 0.3,
        rx = 70 + math.random(0, 25),
        ry = 12 + math.random(0, 8),
        alpha = 0.5 + math.random() * 0.3,
    }
end

for i = 1, 6 do
    groups.rise[i] = {
        tex = NewTexture(
            (i % 2 == 0) and "Interface\\Cooldown\\star4" or "Interface\\Buttons\\WHITE8x8",
            6 + math.random(0, 8), 6 + math.random(0, 8)
        ),
        x = -50 + math.random(0, 100),
        speed = 18 + math.random() * 20,
        phase = math.random(),
        spin = (math.random() - 0.5) * 2,
    }
    groups.fall[i] = {
        tex = NewTexture(
            (i % 2 == 0) and "Interface\\Cooldown\\star4" or "Interface\\Buttons\\WHITE8x8",
            6 + math.random(0, 8), 6 + math.random(0, 8)
        ),
        x = -55 + math.random(0, 110),
        speed = 18 + math.random() * 20,
        phase = math.random(),
        spin = (math.random() - 0.5) * 2,
    }
end

for i = 1, 3 do
    groups.pulse[i] = {
        tex = NewTexture("Interface\\Cooldown\\star4", 70 + math.random(0, 30), 70 + math.random(0, 30)),
        phase = (i - 1) / 3,
        speed = 0.4 + math.random() * 0.15,
    }
end

-- 月光：从月牙底部和两侧向下洒，不穿过顶端尖部
local BEAM_X = { -60, -46, -28, 28, 46, 60 }
for i = 1, 6 do
    groups.beam[i] = {
        tex = NewTexture("Interface\\Buttons\\WHITE8x8", 2 + math.random(0, 4), 70 + math.random(0, 30)),
        x = BEAM_X[i] + (math.random() - 0.5) * 6,
        phase = math.random(),
        speed = 0.10 + math.random() * 0.12,
    }
end

-- 平衡德专属：一个外圆盘中间扣掉一个偏心小圆，横条填充出真正的月牙
-- 这是“大圆减小圆”，不是半圆弧带；只填充两个圆的交点之间，避免多出圆盖。
local moon = { segments = {}, glowBig = nil, glowSmall = nil }
local MOON_R = 42            -- 外圆半径
local MOON_HOLE_R = 40       -- 被扣掉的小圆半径
local MOON_HOLE_X = 8        -- 小圆向右偏
local MOON_HOLE_Y = 0
local MOON_CENTER_Y = 72
local moonXInt = (MOON_R * MOON_R - MOON_HOLE_R * MOON_HOLE_R + MOON_HOLE_X * MOON_HOLE_X)
    / (2 * MOON_HOLE_X)
local moonYInt = math.sqrt(math.max(0, MOON_R * MOON_R - moonXInt * moonXInt))

local function AddMoonBar(x1, x2, y)
    local w = x2 - x1
    if w < 1 then return end
    local tex = NewTexture("Interface\\Buttons\\WHITE8x8", w, 2.4)
    tex:SetPoint("CENTER", frame, "CENTER", (x1 + x2) / 2, y + MOON_CENTER_Y)
    tex:SetAlpha(0.42)
    moon.segments[#moon.segments + 1] = { tex = tex, base = 0.42 }
end

for y = -moonYInt, moonYInt, 2 do
    local outerHalf = math.sqrt(math.max(0, MOON_R * MOON_R - y * y))
    local dy = y - MOON_HOLE_Y
    local holeHalf = math.sqrt(math.max(0, MOON_HOLE_R * MOON_HOLE_R - dy * dy))
    local hLeft = MOON_HOLE_X - holeHalf
    local hRight = MOON_HOLE_X + holeHalf
    -- 大圆这一行减去小圆这一行，剩下的就是月牙
    if hLeft > -outerHalf then
        AddMoonBar(-outerHalf, math.min(hLeft, outerHalf), y)
    end
    if hRight < outerHalf then
        AddMoonBar(math.max(hRight, -outerHalf), outerHalf, y)
    end
end

moon.glowBig = NewTexture("Interface\\Cooldown\\star4", 110, 110)
moon.glowBig:SetPoint("CENTER", frame, "CENTER", 4, 72)
moon.glowSmall = NewTexture("Interface\\Cooldown\\star4", 40, 40)
moon.glowSmall:SetPoint("CENTER", frame, "CENTER", 14, 72)

local themeColor = { 0.55, 0.82, 1 }
local activeStyles = { ring = false, rise = false, fall = false, pulse = false, beam = false }
local moonActive = false

local function ApplyHeadTheme(style, color)
    themeColor = color or DEFAULT_HEAD.color or { 0.55, 0.82, 1 }

    moonActive = false
    for _, item in ipairs(moon.segments) do
        item.tex:Hide()
        item.tex:SetAlpha(0)
    end
    moon.glowBig:Hide()
    moon.glowSmall:Hide()

    for name, list in pairs(groups) do
        activeStyles[name] = false
        for _, p in ipairs(list) do
            p.tex:Hide()
            p.tex:SetAlpha(0)
        end
    end
    for _, name in ipairs(style.styles or DEFAULT_HEAD.styles) do
        if groups[name] then
            activeStyles[name] = true
            for _, p in ipairs(groups[name]) do
                p.tex:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
                p.tex:Show()
            end
        end
    end

    if style.moon then
        moonActive = true
        for _, item in ipairs(moon.segments) do
            item.tex:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
            item.tex:Show()
        end
        moon.glowBig:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
        moon.glowSmall:SetVertexColor(1, 1, 1, 1)
        moon.glowBig:Show()
        moon.glowSmall:Show()
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

    if activeStyles.ring then
        for i, p in ipairs(groups.ring) do
            local a = p.angle + elapsedTotal * p.speed
            local x = math.cos(a) * p.rx
            local y = math.sin(a) * p.ry
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(p.alpha + 0.15 * math.sin(elapsedTotal * 1.8 + i))
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, a) end
        end
    end

    if activeStyles.rise then
        for i, p in ipairs(groups.rise) do
            local prog = (p.phase + elapsedTotal * p.speed / 160) % 1
            local y = -60 + prog * 140
            local x = p.x + math.sin(elapsedTotal * 1.5 + i) * 8
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(math.sin(prog * math.pi) * 0.65)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * p.spin) end
        end
    end

    if activeStyles.fall then
        for i, p in ipairs(groups.fall) do
            local prog = (p.phase + elapsedTotal * p.speed / 180) % 1
            local y = 80 - prog * 150
            local x = p.x + math.sin(elapsedTotal * 1.2 + i) * 10
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(math.sin(prog * math.pi) * 0.65)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * p.spin) end
        end
    end

    if activeStyles.pulse then
        for i, p in ipairs(groups.pulse) do
            local prog = (p.phase + elapsedTotal * p.speed) % 1
            p.tex:SetPoint("CENTER", frame, "CENTER", 0, 4)
            p.tex:SetScale(0.7 + prog * 1.1)
            p.tex:SetAlpha((1 - prog) * 0.2)
            if p.tex.SetRotation then pcall(p.tex.SetRotation, p.tex, elapsedTotal * 0.3 + i) end
        end
    end

    if activeStyles.beam then
        for i, p in ipairs(groups.beam) do
            local prog = (p.phase + elapsedTotal * p.speed) % 1
            -- 从月牙下沿（y≈35）往下洒到脚边，不碰月牙顶端
            local y = 35 - prog * 100
            local x = p.x + math.sin(elapsedTotal * 0.8 + i) * 3
            p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            p.tex:SetAlpha(math.sin(prog * math.pi) * 0.18)
        end
    end

    if moonActive then
        local pulse = 0.8 + 0.2 * math.sin(elapsedTotal * 2)
        for _, item in ipairs(moon.segments) do
            item.tex:SetAlpha(item.base * pulse)
        end
        moon.glowBig:SetAlpha(0.10 + 0.05 * math.sin(elapsedTotal * 1.3))
        moon.glowSmall:SetAlpha(0.25 + 0.10 * math.sin(elapsedTotal * 1.7))
    end
end)

-- ==========================================
-- 触发 / 开关 / 脱战收起
-- ==========================================
local triggerToken = 0

local function CurrentClass()
    local ok, _, token = pcall(UnitClass, "player")
    if ok and token then return token end
    return AP_DB.flavor and AP_DB.flavor.currentClass
end

-- 旧版天赋树 + 双天赋：读取当前激活天赋组里点数最多的一页。
-- 如果客户端没有旧版天赋树接口，再退回现代专精。
local function GetSpecIndex(classToken)
    if type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function" then
        local okNum, count = pcall(GetNumTalentTabs)
        if okNum and type(count) == "number" and count > 0 then
            local group = 1
            if type(GetActiveTalentGroup) == "function" then
                local okG, g = pcall(GetActiveTalentGroup)
                if okG and type(g) == "number" and g >= 1 then group = g end
            end

            local bestTab, bestPoints = 1, -1
            for tab = 1, count do
                -- 第三/第四参数是旧版双天赋的“当前天赋组”
                local ok, _, _, points = pcall(GetTalentTabInfo, tab, false, false, group)
                if not ok or type(points) ~= "number" then
                    ok, _, _, points = pcall(GetTalentTabInfo, tab)
                end
                if ok and type(points) == "number" and points > bestPoints then
                    bestPoints = points
                    bestTab = tab
                end
            end

            -- 旧版德鲁伊只有 3 页，第三页是恢复；映射到恢复特效，而不是守护
            if classToken == "DRUID" and count == 3 and bestTab == 3 then
                return 4
            end
            return bestTab
        end
    end

    if type(GetSpecialization) == "function" then
        local ok, spec = pcall(GetSpecialization)
        if ok and type(spec) == "number" and spec >= 1 then return spec end
    end

    return 1
end

local function IsHeadUnlocked()
    return AP_Spotlight and AP_Spotlight.GetCoreLevel and AP_Spotlight.GetCoreLevel() >= 50
end

local function ShowHead(classToken, factionID)
    classToken = classToken or CurrentClass()
    factionID = factionID or (AP_DB.flavor and AP_DB.flavor.currentFaction)
    local spec = GetSpecIndex(classToken)
    local style = (HEAD_STYLES[classToken] and HEAD_STYLES[classToken][spec]) or DEFAULT_HEAD

    local bodyTheme = AP_Aura and AP_Aura.GetTheme and AP_Aura.GetTheme(classToken, factionID)
    local color = style.color or (bodyTheme and bodyTheme.color) or { 0.55, 0.82, 1 }

    ApplyHeadTheme(style, color)
    triggerToken = triggerToken + 1
    frame:Show()
end

local function Trigger(classToken, factionID, preview, previewDuration, respectLock)
    EnsureDB()
    -- 实战不再由施放核心技能触发：战斗里核心技能冷却好了就会自动显示
    if not preview then return end
    if respectLock and not IsHeadUnlocked() then
        -- 试放时只展示当前等级已经解锁的特效
        return
    end

    ShowHead(classToken, factionID)
    if C_Timer and C_Timer.After then
        local token = triggerToken
        C_Timer.After(previewDuration or 6, function()
            if triggerToken == token then frame:Hide() end
        end)
    end
end

-- ==========================================
-- 实战触发：战斗中核心技能冷却好了就显示，冷却中 / 脱战收起
-- ==========================================
local inCombat = false
local combatCheckAcc = 0

-- 新客户端会把战斗中的冷却/可用性数值标记成 secret，插件不能直接比较；
-- 这里先检测，secret 值就换一种不读数值的判断方式。
local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

local function IsCoreReady()
    EnsureDB()
    local db = AP_DB.spotlight
    local spellID = type(db.coreSpellID) == "number" and db.coreSpellID or nil
    local spellName = db.coreSpell
    if not spellName or spellName == "" then spellName = db.customSpell end
    local target = spellID or spellName
    if not target or target == "" then return false end

    -- 1) 旧接口：直接问“这个技能现在能不能用”
    if type(IsUsableSpell) == "function" then
        local ok, usable = pcall(IsUsableSpell, target)
        if ok and usable ~= nil and not IsSecretValue(usable) then
            return usable and true or false
        end
    end

    -- 2) 新接口：C_Spell.IsSpellUsable
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, target)
        if ok and usable ~= nil and not IsSecretValue(usable) then
            return usable and true or false
        end
    end

    -- 3) 老客户端：读冷却时间；如果是 secret 值就跳过比较
    if type(GetSpellCooldown) == "function" then
        local ok, start, duration = pcall(GetSpellCooldown, target)
        if ok and start ~= nil and not IsSecretValue(start) and not IsSecretValue(duration) then
            return start == 0 or (duration or 0) == 0
        end
    end

    -- 全部接口都读不到时（secret 环境），交给外面的「释放间隔」控制频率
    return true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatCheckAcc = 0
    else
        inCombat = false
        triggerToken = triggerToken + 1
        frame:Hide()
    end
end)

local lastHeadAt = 0          -- 上次触发时间，用来遵守「释放间隔」
local HEAD_SHOW_SECONDS = 8   -- 每次触发显示多久

combatFrame:SetScript("OnUpdate", function(_, elapsed)
    if not inCombat then return end
    combatCheckAcc = combatCheckAcc + elapsed
    if combatCheckAcc < 0.4 then return end
    combatCheckAcc = 0

    EnsureDB()
    local db = AP_DB.spotlight
    local enabled = db.headAuraEnabled and IsHeadUnlocked() and IsCoreReady()
    local cooldownSec = (db.cooldownMinutes or 1) * 60
    local now = GetTime()
    local canTrigger = cooldownSec <= 0 or lastHeadAt == 0 or (now - lastHeadAt) >= cooldownSec

    if enabled and canTrigger and not frame:IsShown() then
        lastHeadAt = now
        ShowHead()
        local token = triggerToken
        if C_Timer and C_Timer.After then
            C_Timer.After(HEAD_SHOW_SECONDS, function()
                if triggerToken == token and inCombat then
                    triggerToken = triggerToken + 1
                    frame:Hide()
                end
            end)
        end
    elseif (not enabled) and frame:IsShown() then
        triggerToken = triggerToken + 1
        frame:Hide()
    end
end)

AP_HeadAura = {
    Trigger = Trigger,
    IsUnlocked = IsHeadUnlocked,
    IsEnabled = function()
        EnsureDB()
        return AP_DB.spotlight.headAuraEnabled
    end,
    SetEnabled = function(value)
        EnsureDB()
        AP_DB.spotlight.headAuraEnabled = value and true or false
        if not AP_DB.spotlight.headAuraEnabled then
            triggerToken = triggerToken + 1
            frame:Hide()
        end
    end,
    Toggle = function()
        EnsureDB()
        AP_DB.spotlight.headAuraEnabled = not AP_DB.spotlight.headAuraEnabled
        if not AP_DB.spotlight.headAuraEnabled then
            triggerToken = triggerToken + 1
            frame:Hide()
        end
        if AP_DB.spotlight.headAuraEnabled and not IsHeadUnlocked() then
            print("|cffffd700[AP]|r 头顶特效需要核心 Lv.50。")
        else
            print("|cffffd700[AP]|r 头顶特效：" .. (AP_DB.spotlight.headAuraEnabled and "已开启" or "已关闭"))
        end
        if AP_Spotlight and AP_Spotlight.RefreshCoreUI then AP_Spotlight.RefreshCoreUI() end
    end,
}

-- 本文件在 Spotlight 之后加载，补刷一次右页开关状态
if AP_Spotlight and AP_Spotlight.RefreshCoreUI then
    AP_Spotlight.RefreshCoreUI()
end
