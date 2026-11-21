-- ==========================================
-- Network.lua: 插件间互通（RP 名字 + 流派简称）
-- ==========================================
-- 只有“双方都装了本插件，并且在同一个小队/团队/公会里”才能互相看到。
-- 数据只走官方插件消息接口 SendAddonMessage，不碰任何非公开通道。
-- 客户端/私服禁用插件消息时自动降级，不报错、不刷屏。
--
-- 消息格式很短：协议号|流派简称|RP名字
-- 例如：1|夜爪|怒里哀·风暴烈酒

local PREFIX = "AzerothPar"
local PROTOCOL = "1"

-- 存档变量是在插件文件加载之后才真正注入的，
-- 所以这些表不能只在文件顶部初始化一次，必须在用之前再确认一遍。
local function EnsureDB()
    AP_DB = AP_DB or {}
    AP_DB.network = AP_DB.network or {}
    if AP_DB.network.enabled == nil then AP_DB.network.enabled = true end
    AP_DB.peers = AP_DB.peers or {}
end
EnsureDB()

-- 广播里直接发简称，不在接收端查表：
-- 这样即使两边插件版本/词条不同，也不会显示成错误的名字。
local FACTION_SHORT = {
    DRUID = { Highborne = "高阶会", Windshaper = "塑风者", Nightclaw = "夜爪" },
    PALADIN = { SilverHand = "白银之手", Sunwalker = "烈日行者", UndeadPaladin = "灰烬誓约", LoneOath = "独行誓者" },
    PRIEST = { HolyChurch = "圣光", MoonPriestess = "月神", ShadowPriest = "遗忘", VoodooPriest = "巫毒" },
    WARLOCK = { StandardWarlock = "契约", Necromancer = "死灵", ShadowCouncil = "暗影议会", SuccubusFan = "魅魔", LegionCultist = "军团" },
    MAGE = { StandardMage = "肯瑞托", WildMage = "流浪", MercenaryMage = "佣兵" },
    WARRIOR = { StandardWarrior = "狮盾", HordeWarrior = "血旗", MercenaryWarrior = "佣兵", TavernBrawler = "酒馆" },
    ROGUE = { SI7 = "军情", Uncrowned = "无冕者", Pirate = "血帆", Scoundrel = "混蛋" },
    HUNTER = { Ranger = "游侠", Rifleman = "火枪手", ShadowHunter = "暗影猎手", WildHunter = "独行" },
    SHAMAN = { StandardShaman = "先祖", EarthenRing = "大地之环" },
}

local hasSecretAPI = type(issecretvalue) == "function"

local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

-- 清洗广播内容：去掉换行、管道符和颜色代码，并限制长度
local function Sanitize(text, maxLength)
    if text == nil or IsSecret(text) then return "" end
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|\n\r]", "")
    if maxLength and #text > maxLength then text = text:sub(1, maxLength) end
    return text
end

-- 跨服 sender 可能带 "-服务器"，统一取前面的角色名
local function BaseName(name)
    if not name or IsSecret(name) then return nil end
    local ok, result = pcall(function()
        return name:match("^([^%-]+)") or name
    end)
    if ok then return result end
    return nil
end

local function GetShortName()
    if not AP_DB.flavor then return "" end
    local factionData = AP_FlavorManager and AP_FlavorManager.GetCurrentFactionData()
    if not factionData then return "" end
    local map = FACTION_SHORT[AP_DB.flavor.currentClass]
    return (map and map[factionData.id]) or factionData.name or ""
end

-- 记录上次广播时间：收到别人消息时，如果自己很久没发过，就补发一次
local lastBroadcastAt = 0

local function Now()
    if time then return time() end
    if GetTime then return GetTime() end
    return 0
end

-- 向当前可用的聊天范围广播自己
local function Broadcast()
    EnsureDB()
    if not AP_DB.network.enabled then return false end
    if not AP_DB.flavor then return false end
    if type(SendAddonMessage) ~= "function" then return false end

    local rpName = Sanitize(AP_DB.flavor.customName, 40)
    if rpName == "" then rpName = Sanitize(UnitName("player"), 40) end
    local faction = Sanitize(GetShortName(), 20)
    if rpName == "" or faction == "" then return false end

    local message = PROTOCOL .. "|" .. faction .. "|" .. rpName
    local sent = false

    -- 旧内核没有 IsInRaid/IsInGroup，就用人数接口兜底
    local inRaid = (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0)
    local inParty = (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0)
    local inGuild = (IsInGuild and IsInGuild()) or (GetGuildInfo and GetGuildInfo("player") ~= nil)

    if inRaid then
        sent = pcall(SendAddonMessage, PREFIX, message, "RAID") or sent
    elseif inParty then
        sent = pcall(SendAddonMessage, PREFIX, message, "PARTY") or sent
    end
    if inGuild then
        sent = pcall(SendAddonMessage, PREFIX, message, "GUILD") or sent
    end
    if sent then lastBroadcastAt = Now() end
    return sent
end

-- 事件变化时合并成一次广播，避免组队瞬间连发好几条
local pendingBroadcast = 0
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
    pendingBroadcast = pendingBroadcast - elapsed
    if pendingBroadcast <= 0 then
        pendingBroadcast = 0
        self:Hide()
        Broadcast()
    end
end)

local function ScheduleBroadcast(delay)
    pendingBroadcast = delay or 1
    ticker:Show()
end

-- 登录时清掉太旧的缓存，避免存档无限膨胀（7 天）
local function CleanOldPeers()
    if not time then return end
    EnsureDB()
    local now = time()
    for name, record in pairs(AP_DB.peers) do
        if type(record) == "table" and record.updated and (now - record.updated) > 604800 then
            AP_DB.peers[name] = nil
        end
    end
end

-- 注册插件消息前缀（老版本没有这个接口，直接跳过）
if RegisterAddonMessagePrefix then
    pcall(RegisterAddonMessagePrefix, PREFIX)
end

local frame = CreateFrame("Frame")
local function SafeRegister(event)
    if not event then return end
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("CHAT_MSG_ADDON")
SafeRegister("PLAYER_LOGIN")
SafeRegister("GROUP_ROSTER_UPDATE")
SafeRegister("PARTY_MEMBERS_CHANGED")
SafeRegister("RAID_ROSTER_UPDATE")
SafeRegister("GUILD_ROSTER_UPDATE")
SafeRegister("PLAYER_GUILD_UPDATE")

frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    EnsureDB()
    if event == "CHAT_MSG_ADDON" then
        -- 关掉开关后彻底不接收，避免“关了但还在收数据”
        if not AP_DB.network.enabled then return end
        if type(prefix) ~= "string" or IsSecret(prefix) or prefix ~= PREFIX then return end
        if type(message) ~= "string" or IsSecret(message) then return end
        local version, faction, rpName = message:match("^(%d+)|([^|]*)|(.*)$")
        if not version or version ~= PROTOCOL then return end

        rpName = Sanitize(rpName, 40)
        faction = Sanitize(faction, 20)
        if rpName == "" or not sender then return end

        local key = BaseName(sender)
        if not key then return end

        local record = {
            name = rpName,
            faction = faction,
            updated = (time and time()) or 0,
        }
        AP_DB.peers[key] = record
        if key ~= sender then AP_DB.peers[sender] = record end

        -- 已经显示出来的姓名版立即刷新一遍
        if AP_Nameplate and AP_Nameplate.RefreshAll then AP_Nameplate.RefreshAll() end

        -- 同好名录如果开着，也立即刷新
        if AP_PeersUI and AP_PeersUI.Refresh then AP_PeersUI.Refresh() end

        -- 对方可能是刚登录的。如果自己很久没广播过，就补发一次，让对方也能看到自己。
        -- 10 秒的间隔是为了防止两边互相回应造成无限循环。
        if Now() - lastBroadcastAt > 10 then
            ScheduleBroadcast(2)
        end

    elseif event == "PLAYER_LOGIN" then
        CleanOldPeers()
        ScheduleBroadcast(3)

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE"
        or event == "PLAYER_GUILD_UPDATE" then
        ScheduleBroadcast(1)
    end
end)

local function SetEnabled(value)
    EnsureDB()
    if value == nil then value = not AP_DB.network.enabled end
    AP_DB.network.enabled = value and true or false

    if AP_DB.network.enabled then
        print("|cffffd700[AP]|r 姓名版互通已开启（小队/团队/公会）。")
        Broadcast()
    else
        pendingBroadcast = 0
        ticker:Hide()
        print("|cffffd700[AP]|r 姓名版互通已关闭，不再发送或接收数据。")
    end
    return AP_DB.network.enabled
end

AP_Network = {
    Broadcast = Broadcast,
    SetEnabled = SetEnabled,
    GetShortName = GetShortName,
}
