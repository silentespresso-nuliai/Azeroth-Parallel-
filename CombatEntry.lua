-- ==========================================
-- CombatEntry.lua: 判断“主动进战”还是“被动进战”
--
-- 用法：
--   AP_CombatEntry.Get()        -> "active" / "passive" / nil（不在战斗中）
--   AP_CombatEntry.Register(fn) -> 进战 / 脱战时回调 fn(state)，state 同上
--
-- 判断依据（启发式，不是 100% 准确）：
--   进战前 ACTIVE_WINDOW 秒内，你自己对敌对目标做过攻击性动作 => 主动
--   否则（走进怪的仇恨范围、被别人拉到怪、被偷袭等）           => 被动
-- 为避免“秘密数值”问题，这里不读战斗日志，只用你自己的施法事件和目标信息。
-- ==========================================
AP_CombatEntry = AP_CombatEntry or {}
local CE = AP_CombatEntry

-- ---------- 可调参数 ----------
local ACTIVE_WINDOW = 3.0   -- 进战前多少秒内的攻击性动作算“主动”（读条很长的技能可适当调大）

local lastHostileAction = 0 -- 最近一次攻击性动作的时间
local entryType = nil       -- nil / "active" / "passive"
local callbacks = {}

local function MarkHostile()
    lastHostileAction = GetTime()
end

local function TargetIsHostile()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
end

-- 技能是否带有“攻击性”。接口不存在时返回 nil，由调用方按“目标是敌对”兜底。
local function SpellIsHarmful(spellID)
    if not spellID or not (C_Spell and C_Spell.IsSpellHarmful) then return nil end
    local ok, result = pcall(C_Spell.IsSpellHarmful, spellID)
    if ok then return result end
    return nil
end

local function ClassifyNow()
    if GetTime() - lastHostileAction <= ACTIVE_WINDOW then
        return "active"
    end
    return "passive"
end

local function Fire()
    for _, fn in ipairs(callbacks) do
        pcall(fn, entryType)
    end
end

-- ---------- 对外接口 ----------
function CE.Get()
    -- 兜底：如果别的模块在我们之前处理了进战事件，这里按需现算
    if not entryType and UnitAffectingCombat("player") then
        entryType = ClassifyNow()
    end
    return entryType
end

function CE.Register(fn)
    if type(fn) == "function" then
        table.insert(callbacks, fn)
    end
end

-- ---------- 事件 ----------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")     -- 进战
f:RegisterEvent("PLAYER_REGEN_ENABLED")      -- 脱战
f:RegisterEvent("PLAYER_ENTER_COMBAT")       -- 开始近战自动攻击
f:RegisterEvent("START_AUTOREPEAT_SPELL")    -- 开始自动射击 / 法杖
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        entryType = ClassifyNow()
        Fire()
    elseif event == "PLAYER_REGEN_ENABLED" then
        entryType = nil
        lastHostileAction = 0   -- 清掉，避免下一次进战被上次的动作误判
        Fire()
    elseif event == "PLAYER_ENTER_COMBAT" or event == "START_AUTOREPEAT_SPELL" then
        -- START_AUTOREPEAT_SPELL 可能带 unit 参数；只认玩家自己，
        -- 否则队友开始自动射击也会被算成你的攻击性动作。
        local unit = ...
        if event == "PLAYER_ENTER_COMBAT" or unit == nil or unit == "player" then
            MarkHostile()
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- 参数：unit, target, castGUID, spellID
        local spellID = select(4, ...)
        if TargetIsHostile() and SpellIsHarmful(spellID) ~= false then
            MarkHostile()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- 参数：unit, castGUID, spellID（读条技能在这里才真正落地）
        local spellID = select(3, ...)
        if TargetIsHostile() and SpellIsHarmful(spellID) ~= false then
            MarkHostile()
        end
    end
end)
