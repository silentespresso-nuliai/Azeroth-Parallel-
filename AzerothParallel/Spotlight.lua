-- ==========================================
-- Spotlight.lua: 职业高光（技能触发特写）
-- ==========================================
-- 做什么：当你按下本职业的核心爆发技能，屏幕右上角（或左上角）会切入一块特写：
--   职业色速度线 + 你的头像 + “【你的名字】开启了 化身！”的大字。
-- 注意：
--   1. 只用 UIParent 下自己建的 Frame / Texture / FontString，不碰动作条、姓名版、单位框架。
--   2. 不替换任何全局 API；查询技能信息时全部用 pcall 包住，读不到就安静跳过。
--   3. 想让队友也看到，双方都必须装本插件，并且在同一个小队/团队/公会里。
--   4. 音效只使用游戏内置的 SOUNDKIT，找不到时不响，也不会报错。

local PREFIX = "AzerothPar"
local PROTOCOL = "H1" -- 消息协议号，和 Network.lua 的 "1|..." 区分开

-- 存档变量是插件加载后才注入的，所以用之前必须再确认一次（引继.md 里提过的坑）
local function EnsureDB()
    AP_DB = AP_DB or {}
    AP_DB.spotlight = AP_DB.spotlight or {}
    local db = AP_DB.spotlight
    if db.enabled == nil then db.enabled = true end
    if db.sound == nil then db.sound = true end
    -- 音效选择：0 = 随机，1~3 = 固定 Media/sounds 里的第几个
    if type(db.soundIndex) ~= "number" or db.soundIndex < -1 or db.soundIndex > 3 then
        db.soundIndex = 0
    end
    -- 广播开关不再在界面里提供，默认始终开启，保证团队/小队能看到彼此的高光
    db.broadcast = true
    -- 释放间距（分钟）：1~10，默认 1 分钟
    if type(db.cooldownMinutes) ~= "number" or db.cooldownMinutes < 0 or db.cooldownMinutes > 10 then
        db.cooldownMinutes = 1
    end
    if db.position ~= "TOPLEFT" and db.position ~= "TOPRIGHT" then
        db.position = "TOPRIGHT"
    end
    -- 自定义大招：只存一个字符串，可以是技能名，也可以是技能 ID（纯数字）。
    -- 留空 = 使用下面写好的默认职业表。
    if type(db.customSpell) ~= "string" then db.customSpell = "" end
    -- 核心技能培养：选定的官方技能名 + 15 级后自定义的名字
    if type(db.coreSpell) ~= "string" then db.coreSpell = "" end
    if type(db.coreAlias) ~= "string" then db.coreAlias = "" end
    if type(db.coreDesc) ~= "string" then db.coreDesc = "" end
    -- 老存档兼容：之前设过自定义大招的，直接当作核心技能继续培养
    if db.coreSpell == "" and db.customSpell ~= "" then
        db.coreSpell = db.customSpell
    end
    -- 5 级喊话功能已整体删除，清掉旧存档里的残留字段
    db.coreChatEnabled = nil
    db.chatText = nil
    db.chatMode = nil
    -- 是否只在组队/团队中触发（默认关闭，单人做任务也能看高光）
    if db.groupOnly == nil then db.groupOnly = false end
end
EnsureDB()

-- ==========================================
-- 1. 数据层：哪些技能算“高光”
-- ==========================================
-- id     = 技能的 SpellID（以正式服为准，私服若改了 ID 会走下面的 official 名字兜底）
-- official = 官方技能名，用于 ID 对不上时按名字匹配
-- label  = 高光里显示的短名（“化身”比全名更适合大字）
-- sound  = "EPIC" 用史诗掉落音，不写就用升级音
-- ==========================================
-- 立绘图片配置（可选）
-- ==========================================
-- 键 = 技能 ID，值 = 插件目录内的图片路径。
-- ★ 魔兽只认 .tga（32 位未压缩）或 .blp，PNG 不会被客户端加载，会显示空白。
-- 把图片放进 AzerothParallel\Media\ 下，然后取消下面示例的注释即可。
-- 建议尺寸 256×256 或 512×512，正方形，背景透明。
local PORTRAIT_IMAGES = {
    -- [102560] = "Interface\\AddOns\\AzerothParallel\\Media\\Face1.tga",
    -- [194223] = "Interface\\AddOns\\AzerothParallel\\Media\\Face2.tga",
    -- [50334]  = "Interface\\AddOns\\AzerothParallel\\Media\\Face3.tga",
}

local SPELL_DATA = {
    DRUID = {
        { id = 102560, official = "化身：艾露恩之眷", label = "化身", sound = "EPIC" },
        { id = 102543, official = "化身：丛林之王", label = "化身", sound = "EPIC" },
        { id = 102558, official = "化身：乌索克的守护者", label = "化身", sound = "EPIC" },
        { id = 33891,  official = "化身：生命之树", label = "化身", sound = "EPIC" },
        { id = 194223, official = "超凡之盟", label = "超凡之盟", sound = "EPIC" },
        { id = 50334,  official = "狂暴", label = "狂暴", sound = "EPIC" },
    },
    WARRIOR = {
        { id = 1719,   official = "鲁莽", label = "鲁莽" },
        { id = 107574, official = "天神下凡", label = "天神下凡" },
        { id = 227847, official = "剑刃风暴", label = "剑刃风暴" },
    },
    PALADIN = {
        { id = 31884,  official = "复仇之怒", label = "复仇之怒", sound = "EPIC" },
        { id = 105809, official = "神圣复仇者", label = "神圣复仇者" },
    },
    HUNTER = {
        { id = 193530, official = "野性守护", label = "野性守护" },
        { id = 19574,  official = "狂野怒火", label = "狂野怒火" },
        { id = 266779, official = "协同进攻", label = "协同进攻" },
    },
    ROGUE = {
        { id = 13750,  official = "冲动", label = "冲动" },
        { id = 185313, official = "暗影之舞", label = "暗影之舞" },
    },
    PRIEST = {
        { id = 10060,  official = "能量灌注", label = "能量灌注", sound = "EPIC" },
        { id = 200183, official = "神圣化身", label = "神圣化身" },
        { id = 194249, official = "虚空形态", label = "虚空形态" },
    },
    SHAMAN = {
        { id = 114050, official = "升腾", label = "升腾", sound = "EPIC" },
        { id = 114051, official = "升腾", label = "升腾", sound = "EPIC" },
        { id = 114052, official = "升腾", label = "升腾", sound = "EPIC" },
        { id = 2825,   official = "嗜血", label = "嗜血", sound = "EPIC" },
        { id = 32182,  official = "英勇", label = "英勇", sound = "EPIC" },
    },
    MAGE = {
        { id = 190319, official = "燃烧", label = "燃烧", sound = "EPIC" },
        { id = 12042,  official = "奥术强化", label = "奥术强化" },
        { id = 12472,  official = "冰霜血脉", label = "冰霜血脉" },
    },
    WARLOCK = {
        { id = 265187, official = "召唤恶魔暴君", label = "恶魔暴君", sound = "EPIC" },
        { id = 1122,   official = "召唤地狱火", label = "地狱火", sound = "EPIC" },
        { id = 113858, official = "黑暗灵魂：动荡", label = "黑暗灵魂" },
        { id = 113860, official = "黑暗灵魂：哀难", label = "黑暗灵魂" },
        { id = 113861, official = "黑暗灵魂：学识", label = "黑暗灵魂" },
    },
}

-- 把上面的人类可读表，编译成两张查询表：
--   BY_ID[职业][技能ID]   → 条目
--   BY_NAME[职业][官方名] → 条目（私服改 ID 时的兜底）
local BY_ID, BY_NAME = {}, {}
for classToken, list in pairs(SPELL_DATA) do
    BY_ID[classToken] = {}
    BY_NAME[classToken] = {}
    for _, info in ipairs(list) do
        BY_ID[classToken][info.id] = info
        if info.official then BY_NAME[classToken][info.official] = info end
    end
end

-- 广播接收端只认这些职业 token，防止有人伪造奇怪的值
local CLASS_TOKENS = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true, MONK = true,
    DEATHKNIGHT = true, DEMONHUNTER = true, EVOKER = true,
}

-- ==========================================
-- 2. 公共小工具（和 Network.lua 保持同一套安全习惯）
-- ==========================================
local hasSecretAPI = type(issecretvalue) == "function"

local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

-- 按 UTF-8 字符数截断；直接按字节切会把汉字从中间切断
local function TruncateUTF8(text, maxChars)
    if not maxChars or maxChars <= 0 then return "" end
    local count, i = 0, 1
    local len = #text
    while i <= len do
        if count >= maxChars then return text:sub(1, i - 1) end
        local byte = text:byte(i)
        local step = 1
        if byte >= 240 then
            step = 4
        elseif byte >= 224 then
            step = 3
        elseif byte >= 192 then
            step = 2
        end
        i = i + step
        count = count + 1
    end
    return text
end

-- 清理广播字段：去掉换行、管道符、颜色代码，并限制长度
local function Sanitize(text, maxLength)
    if text == nil or IsSecret(text) then return "" end
    local ok, result = pcall(function()
        local s = tostring(text)
        s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|\n\r]", "")
        if maxLength then s = TruncateUTF8(s, maxLength) end
        return s
    end)
    return (ok and result) or ""
end

local function Now()
    if type(GetTime) == "function" then return GetTime() end
    return 0
end

-- 去掉输入框两端的空格，避免用户多按一下空格就匹配不到技能
local function Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 读出自定义大招。空字符串表示没设置，返回 nil 让事件走默认职业表。
-- 核心技能：优先用培养系统里选定的技能，老存档没有就退回 customSpell
local function GetCoreSpellName()
    EnsureDB()
    local value = Trim(Sanitize(AP_DB.spotlight.coreSpell, 60))
    if value == "" then
        value = Trim(Sanitize(AP_DB.spotlight.customSpell, 60))
    end
    if value == "" then return nil end
    return value
end

-- 培养等级：每 6 点熟练度升 1 级，1 级起步，最高 50 级。
-- 熟练度数据与「称谓典籍」共用 AP_DB.flavor.skillProf，不另存一份。
local function GetCoreLevel()
    local official = GetCoreSpellName()
    if not official then return 0 end
    local prof = AP_DB.flavor and AP_DB.flavor.skillProf
    local points = (prof and prof[official]) or 0
    return math.min(50, math.floor(points / 6) + 1)
end

local function GetCorePoints()
    local official = GetCoreSpellName()
    if not official then return 0 end
    local prof = AP_DB.flavor and AP_DB.flavor.skillProf
    return (prof and prof[official]) or 0
end

-- 事件里仍沿用旧名字，内部统一走核心技能
local function GetCustomSpell()
    return GetCoreSpellName()
end

-- 是否在队伍/团队中：用于“只在组队时触发”的开关
local function IsInGroupNow()
    local ok, value
    if type(IsInRaid) == "function" then
        ok, value = pcall(IsInRaid)
        if ok and value then return true end
    end
    if type(IsInGroup) == "function" then
        ok, value = pcall(IsInGroup)
        if ok and value then return true end
    end
    if type(GetNumRaidMembers) == "function" then
        ok, value = pcall(GetNumRaidMembers)
        if ok and type(value) == "number" and value > 0 then return true end
    end
    if type(GetNumPartyMembers) == "function" then
        ok, value = pcall(GetNumPartyMembers)
        if ok and type(value) == "number" and value > 0 then return true end
    end
    return false
end

local function CurrentClass()
    local ok, _, token = pcall(UnitClass, "player")
    if ok and token then return token end
    return AP_DB.flavor and AP_DB.flavor.currentClass
end

local function GetDisplayName()
    local name = AP_DB.flavor and AP_DB.flavor.customName
    if type(name) == "string" and name ~= "" and not IsSecret(name) then return name end
    local ok, unitName = pcall(UnitName, "player")
    if ok and type(unitName) == "string" then return unitName end
    return "无名冒险者"
end

-- 把官方技能名换成“称谓典籍”里当前流派的专属称呼。
-- 比如高阶会德鲁伊的“星辰坠落”会显示成典籍里写的“星穹倾泻”。
-- 查不到就原样返回 fallback，绝不影响高光正常显示。
local aliasCache = {}
local function ResolveFactionAlias(officialName, fallback)
    if not AP_FlavorManager or type(AP_FlavorManager.GetTermList) ~= "function" then
        return fallback
    end
    local classToken = CurrentClass()
    local factionID = AP_DB.flavor and AP_DB.flavor.currentFaction
    if not classToken or not factionID then return fallback end

    -- 缓存按“职业:流派”分开：切流派后 key 变化，下次会自动重建
    local key = tostring(classToken) .. ":" .. tostring(factionID)
    local map = aliasCache[key]
    if not map then
        map = {}
        local ok, list = pcall(AP_FlavorManager.GetTermList, classToken, factionID)
        if ok and type(list) == "table" then
            for _, term in ipairs(list) do
                if term.official and term.alias then
                    map[term.official] = term.alias
                end
            end
        end
        aliasCache[key] = map
    end

    local alias
    if type(officialName) == "string" and officialName ~= "" then
        alias = map[officialName]
    end
    if not alias and type(fallback) == "string" and fallback ~= "" then
        alias = map[fallback]
    end
    return alias or fallback
end

local function ClassColor(classToken)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    return color or { r = 0.83, g = 0.69, b = 0.22 }
end

-- 流派主题色：Data.lua 里给流派配了 themeColor 就用它，没配就回退职业色。
-- 只在本机触发时使用；远程队友只带职业信息，不知道对方流派。
local function GetThemeColor(classToken)
    local factionID = AP_DB.flavor and AP_DB.flavor.currentFaction
    local data = AP_FlavorData and AP_FlavorData[classToken]
    if not factionID or not data or not data.factions then return nil end
    for _, faction in ipairs(data.factions) do
        if faction.id == factionID then return faction.themeColor end
    end
    return nil
end

-- 核心技能显示名：改过名就优先用新名字，试放和实战共用同一套规则
local function GetCoreDisplayLabel(officialName, fallback)
    EnsureDB()
    local core = GetCoreSpellName()
    local alias = AP_DB.spotlight.coreAlias
    if core and type(alias) == "string" and alias ~= "" then
        return alias
    end
    return ResolveFactionAlias(officialName, fallback)
end

-- 核心技能改名后，清掉 tooltip/施法条的别名缓存，让新名字立刻生效
local function ClearAliasCache()
    if AP_TooltipAlias and AP_TooltipAlias.SetEnabled and AP_TooltipAlias.IsEnabled then
        AP_TooltipAlias.SetEnabled(AP_TooltipAlias.IsEnabled())
    end
end

local function HexCode(color)
    local function part(v)
        return math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5)
    end
    return string.format("|cff%02x%02x%02x", part(color.r), part(color.g), part(color.b))
end

-- 安全取技能名：优先新 API，老客户端回退 GetSpellInfo（只调用，不替换）
local function FetchSpellName(spellID)
    if type(spellID) ~= "number" then return nil end
    local name
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then name = info.name end
    end
    if name == nil and type(GetSpellInfo) == "function" then
        local ok, result = pcall(GetSpellInfo, spellID)
        if ok then name = result end
    end
    if type(name) ~= "string" or IsSecret(name) then return nil end
    return name
end

-- ==========================================
-- 3. 音效（只用内置 SOUNDKIT，取不到就静默）
-- ==========================================
local function SoundKitID(key)
    if type(SOUNDKIT) ~= "table" then return nil end
    local ok, id = pcall(function() return SOUNDKIT[key] end)
    if ok and type(id) == "number" then return id end
    return nil
end

-- 自定义高光音效：Media/sounds 里的文件随机挑一个播放。
-- 如果客户端拒绝插件目录里的音频，调用本身不会报错，但会没有声音。
-- 按这些文件名放自己的 ogg 到 Media/sounds/；想换名字就改这三行。
local CUSTOM_SOUNDS = {
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\sound1.ogg",
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\sound2.ogg",
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\sound3.ogg",
}

-- 记录当前正在播放的高光音效，下一次触发时先停掉旧的，避免连续试放时叠成一团
local lastSpotSoundHandle

local function PlaySpotSound(kind, force)
    EnsureDB()
    if not AP_DB.spotlight.sound then return end
    if (AP_DB.spotlight.soundIndex or 0) == -1 then return end
    -- 30 级才解锁本地音效；试放同样遵守，低等级不白给声音
    local coreSpell = GetCoreSpellName()
    if coreSpell and GetCoreLevel() < 30 then return end

    -- 优先随机播放自定义音效；老客户端没有 PlaySoundFile 时才退回内置音
    if type(PlaySoundFile) == "function" and #CUSTOM_SOUNDS > 0 then
        local index = AP_DB.spotlight.soundIndex or 0
        local path
        if index >= 1 and index <= #CUSTOM_SOUNDS then
            path = CUSTOM_SOUNDS[index] -- 玩家自己选的固定音效
        else
            path = CUSTOM_SOUNDS[math.random(#CUSTOM_SOUNDS)] -- 随机
        end
        -- 先停掉上一个高光音效，保证同一时间只有一个在响
        if lastSpotSoundHandle and type(StopSound) == "function" then
            pcall(StopSound, lastSpotSoundHandle)
            lastSpotSoundHandle = nil
        end
        -- 新版带声道参数，老版没有；失败也保持自定义音，避免和内置音叠在一起
        local ok, _, handle = pcall(PlaySoundFile, path, "Master")
        if not ok then
            ok, _, handle = pcall(PlaySoundFile, path)
        end
        if ok and type(handle) == "number" then
            lastSpotSoundHandle = handle
        end
        return
    end

    local id
    if kind == "EPIC" then id = SoundKitID("UI_EPICLOOT_TOAST") end
    id = id or SoundKitID("LEVEL_UP") or 888 -- 888 是升级音最常见的 ID，作为最后兜底
    if type(PlaySound) ~= "function" then return end

    if lastSpotSoundHandle and type(StopSound) == "function" then
        pcall(StopSound, lastSpotSoundHandle)
        lastSpotSoundHandle = nil
    end
    -- 新版 PlaySound 第二个参数是声道，老版没有；失败就退回单参数
    local ok, _, handle = pcall(PlaySound, id, "Master")
    if not ok then
        ok, _, handle = pcall(PlaySound, id)
    end
    if ok and type(handle) == "number" then
        lastSpotSoundHandle = handle
    end
end

-- ==========================================
-- 4. 特效层：一个可复用的 Frame + 贴图 + 动画
-- ==========================================
local spot = CreateFrame("Frame", "AP_SpotlightFrame", UIParent, "BackdropTemplate")
spot:SetSize(440, 150)
spot:SetFrameStrata("HIGH")
spot:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
spot:SetBackdropColor(0, 0, 0, 0.72)
spot:SetBackdropBorderColor(0.83, 0.69, 0.22, 0.9)
spot:Hide()

-- 位置：默认右上角。y 取 -230 是为了避开右上角的小地图。
local function ApplyPosition()
    EnsureDB()
    spot:ClearAllPoints()
    if AP_DB.spotlight.position == "TOPLEFT" then
        spot:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -250)
    else
        spot:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -250)
    end
end
ApplyPosition()

-- 左侧职业色竖条：让整块特写有“切进来”的视觉重量
local accent = spot:CreateTexture(nil, "ARTWORK")
accent:SetWidth(6)
accent:SetPoint("TOPLEFT", spot, "TOPLEFT", 0, 0)
accent:SetPoint("BOTTOMLEFT", spot, "BOTTOMLEFT", 0, 0)
accent:SetColorTexture(0.83, 0.69, 0.22, 1)

-- 头像背后的光晕（暴雪动作按钮的选中边框，ADD 混合后很像光）
local glow = spot:CreateTexture(nil, "BACKGROUND")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetSize(170, 170)
glow:SetPoint("LEFT", spot, "LEFT", 34, 0)
glow:SetVertexColor(0.83, 0.69, 0.22, 0.8)

-- 头像本体：用 SetPortraitTexture 临时“拍”一张当前角色头像，不依赖外部图片
local portrait = spot:CreateTexture(nil, "ARTWORK")
portrait:SetSize(96, 96)
portrait:SetPoint("LEFT", spot, "LEFT", 22, 0)
pcall(portrait.SetMaskTexture, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

-- 自定义立绘：叠在头像上面。图片文件不存在时只会透出下面的头像，不会变成空白。
-- 必须是 .tga / .blp；PNG 不会被加载。尺寸与头像一致，保持 110×110。
local portraitImage = spot:CreateTexture(nil, "ARTWORK")
portraitImage:SetSize(96, 96)
portraitImage:SetPoint("LEFT", spot, "LEFT", 22, 0)
portraitImage:Hide()

-- 四角星闪光：旋转 + 淡出，放在头像右上角
local spark = spot:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\Cooldown\\star4")
spark:SetBlendMode("ADD")
spark:SetSize(60, 60)
spark:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 12, 14)
spark:SetVertexColor(1, 0.95, 0.7, 1)

-- 大字：第一行名字，第二行技能短名（技能名用职业色）
local mainText = spot:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
mainText:SetPoint("TOPLEFT", spot, "TOPLEFT", 140, -30)
mainText:SetWidth(280)
mainText:SetJustifyH("CENTER")
mainText:SetFont(mainText:GetFont(), 21, "OUTLINE")
mainText:SetSpacing(8)
mainText:SetText("")

-- 底部小字：装饰用，告诉屏幕前的你“这是高光时刻”
local subText = spot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subText:SetPoint("BOTTOM", spot, "BOTTOM", 80, 16)
subText:SetFont(subText:GetFont(), 12, "OUTLINE")
subText:SetText("|cff888888—— 高 光 时 刻 ——|r")

-- 速度线：纯色细条，每条约自己宽度向左滑动并淡出。
-- 不用旋转贴图（WoW 的纯色纹理旋转后看不出形状），改用“多条错位细线”制造速度感。
local streakLines, streakGroups = {}, {}
for i = 1, 9 do
    local line = spot:CreateTexture(nil, "BORDER")
    line:SetHeight((i % 3 == 0) and 3 or 2)
    local width = 60 + (i * 31) % 140
    line:SetWidth(width)
    line:SetPoint("TOPLEFT", spot, "TOPLEFT", 20 + (i * 40) % 160, -12 - (i - 1) * 14)
    line:SetBlendMode("ADD")
    line:SetColorTexture(1, 0.95, 0.8, 1)
    line:SetAlpha(0)

    local group = line:CreateAnimationGroup()
    local move = group:CreateAnimation("Translation")
    move:SetDuration(0.55)
    move:SetOffset(-(width + 80), 0)
    local fade = group:CreateAnimation("Alpha")
    fade:SetDuration(0.55)
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0)
    -- 不同版本对“延迟”的支持不一样：AnimationGroup 上不一定有 SetStartDelay，
    -- 所以退一步挂到两条动画自身上；连动画都不支持就同时播放，最多损失一点错落感。
    local delay = (i - 1) * 0.035
    if move.SetStartDelay then pcall(move.SetStartDelay, move, delay) end
    if fade.SetStartDelay then pcall(fade.SetStartDelay, fade, delay) end

    streakLines[i] = line
    streakGroups[i] = group
end

-- 星光旋转动画：部分老客户端可能没有 Rotation 类型，创建失败就跳过
local sparkGroup
do
    local ok, group = pcall(function()
        local g = spark:CreateAnimationGroup()
        local spin = g:CreateAnimation("Rotation")
        spin:SetDegrees(160)
        spin:SetDuration(1.1)
        local fade = g:CreateAnimation("Alpha")
        fade:SetDuration(1.1)
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        return g
    end)
    if ok then sparkGroup = group end
end

-- 整块特写的淡入 / 淡出
local appearGroup = spot:CreateAnimationGroup()
local appearFade = appearGroup:CreateAnimation("Alpha")
appearFade:SetFromAlpha(0)
appearFade:SetToAlpha(1)
appearFade:SetDuration(0.18)
-- 弹跳：基础缩放是 0.86，这里给一个明显大于 1 的终点，
-- 无论客户端把 SetScale 理解成绝对倍数还是相对倍数，都能看到放大效果。
-- 动画结束后由 OnFinished 统一归位到 1。
local appearPop = appearGroup:CreateAnimation("Scale")
appearPop:SetDuration(0.22)
appearPop:SetScale(1.16, 1.16)
-- 关键修正：部分客户端在动画结束后会把属性还原成动画开始前的值，
-- 表现就是“淡入一结束整块特写就消失了”。结束时强制拉回完整状态。
appearGroup:SetScript("OnFinished", function()
    if spot:IsShown() then
        spot:SetAlpha(1)
        spot:SetScale(1)
    end
end)

local disappearGroup = spot:CreateAnimationGroup()
local disappearFade = disappearGroup:CreateAnimation("Alpha")
disappearFade:SetFromAlpha(1)
disappearFade:SetToAlpha(0)
disappearFade:SetDuration(0.35)

-- 每次显示都换一个 token，防止旧的定时器把新一轮动画提前关掉
local activeToken = 0

-- 延迟执行。优先用官方 C_Timer；客户端没有 C_Timer 时，绝不能直接 callback()，
-- 否则会变成“高光一出现就立刻淡出”，视觉上只闪 0.5 秒。
-- 这里用自己的 OnUpdate 计时器兜底。
local pendingDelays = {}
local delayElapsed = 0
local delayTicker = CreateFrame("Frame")
delayTicker:Hide()
delayTicker:SetScript("OnUpdate", function(self, elapsed)
    delayElapsed = delayElapsed + elapsed
    for i = #pendingDelays, 1, -1 do
        local item = pendingDelays[i]
        if delayElapsed >= item.at then
            table.remove(pendingDelays, i)
            pcall(item.fn)
        end
    end
    if #pendingDelays == 0 then
        delayElapsed = 0
        self:Hide()
    end
end)

local function After(seconds, callback)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(seconds, callback)
        return
    end
    table.insert(pendingDelays, { at = delayElapsed + seconds, fn = callback })
    delayTicker:Show()
end

-- 屏幕边缘闪光：只在触发瞬间闪一下职业色。
-- 不去移动 UIParent（震屏会影响所有暴雪界面和布局），只叠一层不接收鼠标的贴图。
local flash = CreateFrame("Frame", "AP_SpotlightFlash", UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("HIGH")
flash:EnableMouse(false)
flash:Hide()

-- 边缘光晕厚度：想调视觉效果只改这一个数
local FLASH_THICKNESS = 60

local function MakeFlashEdge()
    local tex = flash:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetBlendMode("ADD")
    tex:SetAlpha(0)
    return tex
end

-- 上、下两条横边
local flashEdges = {}
local topEdge = MakeFlashEdge()
topEdge:SetPoint("TOPLEFT", flash, "TOPLEFT", 0, 0)
topEdge:SetPoint("TOPRIGHT", flash, "TOPRIGHT", 0, 0)
topEdge:SetHeight(FLASH_THICKNESS)
local bottomEdge = MakeFlashEdge()
bottomEdge:SetPoint("BOTTOMLEFT", flash, "BOTTOMLEFT", 0, 0)
bottomEdge:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", 0, 0)
bottomEdge:SetHeight(FLASH_THICKNESS)
-- 左、右两条竖边
local leftEdge = MakeFlashEdge()
leftEdge:SetPoint("TOPLEFT", flash, "TOPLEFT", 0, 0)
leftEdge:SetPoint("BOTTOMLEFT", flash, "BOTTOMLEFT", 0, 0)
leftEdge:SetWidth(FLASH_THICKNESS)
local rightEdge = MakeFlashEdge()
rightEdge:SetPoint("TOPRIGHT", flash, "TOPRIGHT", 0, 0)
rightEdge:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", 0, 0)
rightEdge:SetWidth(FLASH_THICKNESS)
flashEdges = { topEdge, bottomEdge, leftEdge, rightEdge }

local flashGroups = {}
for i, tex in ipairs(flashEdges) do
    local group = tex:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetDuration(0.5)
    fade:SetFromAlpha(0.45)
    fade:SetToAlpha(0)
    flashGroups[i] = group
end

local flashToken = 0
local function FlashEdges(color)
    for _, tex in ipairs(flashEdges) do
        tex:SetColorTexture(color.r, color.g, color.b, 1)
    end
    flash:Show()
    for _, group in ipairs(flashGroups) do
        group:Stop()
        group:Play()
    end
    flashToken = flashToken + 1
    local myToken = flashToken
    After(0.55, function()
        if flashToken == myToken then flash:Hide() end
    end)
end

-- 找队友的 unit token：/target 查名字太打扰玩家，这里直接遍历小队/团队
local function FindUnitByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local function matches(unit)
        if not UnitExists or not UnitExists(unit) then return false end
        local ok, unitName = pcall(UnitName, unit)
        if not ok or type(unitName) ~= "string" or IsSecret(unitName) then return false end
        return unitName == name
    end
    if matches("player") then return "player" end
    for i = 1, 4 do
        if matches("party" .. i) then return "party" .. i end
    end
    for i = 1, 40 do
        if matches("raid" .. i) then return "raid" .. i end
    end
    return nil
end

-- 画头像：自己/队友用真实头像；找不到 unit 时退化成职业图标
local function SetSpotPortrait(classToken, unitToken)
    if unitToken and type(SetPortraitTexture) == "function" then
        local ok = pcall(SetPortraitTexture, portrait, unitToken)
        if ok then return end
    end
    local icon = "Interface\\Icons\\ClassIcon_" .. tostring(classToken)
    local ok = pcall(portrait.SetTexture, portrait, icon)
    if not ok then pcall(portrait.SetTexture, portrait, "Interface\\Icons\\INV_Misc_QuestionMark") end
end

-- ==========================================
-- 5. 核心：显示一次高光
-- ==========================================
-- name       显示的名字（自己用 RP 名，队友用收到的名字）
-- label      技能短名
-- classToken 职业 token，用来取职业色和职业图标
-- unitToken  头像来源，nil 时用职业图标
-- soundKind  "EPIC" 或 nil
local function ShowHighlight(name, label, classToken, unitToken, soundKind, imagePath, force)
    EnsureDB()
    -- force = 试放按钮：即使总开关关着也允许预览
    if not force and not AP_DB.spotlight.enabled then return end
    -- 组队限制放在事件入口处理；试放按钮始终可用，方便单人调试

    -- 名字和技能短名都会直接拼进 FontString，先清一遍，防止存档里的奇怪字符破坏排版
    name = Sanitize(name, 40)
    label = Sanitize(label, 20)
    if name == "" then name = "无名冒险者" end
    if label == "" then label = "爆发" end

    local color = ClassColor(classToken)
    -- 自己触发/试放时用当前流派的主题色；远程队友保持职业色
    if unitToken == "player" then
        local theme = GetThemeColor(classToken)
        if theme then color = theme end
    end
    local hex = HexCode(color)

    -- 边框、竖条、光晕、星光、速度线全部染成职业色
    spot:SetBackdropBorderColor(color.r, color.g, color.b, 0.9)
    accent:SetColorTexture(color.r, color.g, color.b, 1)
    glow:SetVertexColor(color.r, color.g, color.b, 0.8)
    spark:SetVertexColor(
        math.min(1, color.r + 0.25),
        math.min(1, color.g + 0.25),
        math.min(1, color.b + 0.25),
        1
    )
    for _, line in ipairs(streakLines) do
        line:SetColorTexture(color.r, color.g, color.b, 1)
    end

    -- 头像永远先铺好作为兜底；配置了立绘图片就叠上去。
    -- 图片路径写错/文件不存在时，露出的仍然是头像，不会变成一块空白。
    SetSpotPortrait(classToken, unitToken)
    if type(imagePath) == "string" and imagePath ~= "" then
        portraitImage:SetTexture(imagePath)
        portraitImage:Show()
    else
        portraitImage:Hide()
    end
    mainText:SetText("【" .. name .. "】开启了\n" .. hex .. label .. "|r！")

    -- 先显示再淡入，避免上一轮的淡出把新内容吃成透明
    -- 这里必须把上一轮的淡出动画也停掉，否则它会继续把 alpha 拉向 0
    disappearGroup:Stop()
    spot:SetAlpha(0)
    spot:SetScale(0.86) -- 弹跳动画的起点
    spot:Show()

    activeToken = activeToken + 1
    local myToken = activeToken

    appearGroup:Stop()
    appearGroup:Play()

    for _, group in ipairs(streakGroups) do
        group:Stop()
        group:Play()
    end
    if sparkGroup then
        sparkGroup:Stop()
        sparkGroup:Play()
    end

    FlashEdges(color)
    PlaySpotSound(soundKind, force)

    -- 停留 3 秒后淡出；token 对不上说明期间弹了新的高光，就放弃这次收尾
    After(3, function()
        if activeToken ~= myToken then return end
        -- 淡出前先确保完全可见，避免透明度被上一段动画还原成 0 后，
        -- 淡出动画的 FromAlpha=1 又把它拉起来，造成“第二次闪烁”。
        spot:SetAlpha(1)
        disappearGroup:Stop()
        disappearGroup:Play()
    end)
    disappearGroup:SetScript("OnFinished", function()
        if activeToken == myToken then spot:Hide() end
    end)
end

-- ==========================================
-- 6. 广播：让同队/同团/同会的插件用户也看到
-- ==========================================
-- 消息格式：H1|职业|RP名|技能短名
-- 字段都很短，SendAddonMessage 默认 255 字节上限完全够用。
local lastSendAt = 0

local function CanSend()
    local inRaid = (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0)
    local inParty = (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0)
    local inGuild = (IsInGuild and IsInGuild()) or (GetGuildInfo and GetGuildInfo("player") ~= nil)
    return inRaid, inParty, inGuild
end

local function BroadcastHighlight(classToken, label)
    EnsureDB()
    if not AP_DB.spotlight.broadcast then return end
    if type(SendAddonMessage) ~= "function" then return end

    -- 1 秒内只发一条，避免连续按技能把队伍频道刷爆
    local now = Now()
    if now - lastSendAt < 1 then return end

    local className = Sanitize(classToken, 20)
    local displayName = Sanitize(GetDisplayName(), 40)
    local safeLabel = Sanitize(label, 20)
    if className == "" or displayName == "" or safeLabel == "" then return end

    local inRaid, inParty, inGuild = CanSend()
    if not (inRaid or inParty or inGuild) then return end

    lastSendAt = now
    local message = PROTOCOL .. "|" .. className .. "|" .. displayName .. "|" .. safeLabel
    if inRaid then pcall(SendAddonMessage, PREFIX, message, "RAID") end
    if inParty and not inRaid then pcall(SendAddonMessage, PREFIX, message, "PARTY") end
    if inGuild then pcall(SendAddonMessage, PREFIX, message, "GUILD") end
end

-- ==========================================
-- 6.1 远程队友的 5 个独立槽位（1~5 区域）
-- ==========================================
-- 多个队友同时开爆发时，每人占用一个槽位，绝不互相覆盖。
-- 位置固定在屏幕右侧竖排：主特写下方，1 号最上，5 号最下。
-- 五个固定区域：右上、右中、左上、左中、中上
-- 想改大小只改宽高；想挪区域改 SLOT_POINTS。
local REMOTE_SLOTS = 5
local REMOTE_SLOT_WIDTH = 440
local REMOTE_SLOT_HEIGHT = 150
local SLOT_POINTS = {
    { "TOPRIGHT", -20, -250 }, -- 1 右上，和左上同高
    { "RIGHT",    -20, 0 },    -- 2 右中
    { "TOPLEFT",   20, -250 }, -- 3 左上，和右上同高
    { "LEFT",      20, 0 },    -- 4 左中
    { "TOP",        0, -250 }, -- 5 中央顶部
}

local remoteSlots = {}
for i = 1, REMOTE_SLOTS do
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(REMOTE_SLOT_WIDTH, REMOTE_SLOT_HEIGHT)
    local p = SLOT_POINTS[i] or SLOT_POINTS[REMOTE_SLOTS]
    f:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.78)
    f:SetBackdropBorderColor(0.83, 0.69, 0.22, 0.9)
    f:Hide()

    -- 左侧职业色竖条（和主特写同一个视觉语言）
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(5)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    accent:SetColorTexture(1, 1, 1, 1)

    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(96, 96)
    portrait:SetPoint("LEFT", f, "LEFT", 22, 0)
    pcall(portrait.SetMaskTexture, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 140, -24)
    text:SetWidth(REMOTE_SLOT_WIDTH - 160)
    text:SetJustifyH("LEFT")
    text:SetSpacing(6)
    text:SetFont(text:GetFont(), 18, "OUTLINE")

    remoteSlots[i] = {
        frame = f,
        accent = accent,
        portrait = portrait,
        text = text,
        expireAt = 0,
        token = 0,
    }
end

-- 队友槽位顺序：第二次一定和自己相反方向，然后右中、左中，最后中央顶部
local function GetRemoteSlotOrder()
    EnsureDB()
    local pos = AP_DB.spotlight.position
    if pos == "TOPLEFT" then
        -- 自己在左上：右上、右中、左中、中央顶部
        return { 1, 2, 4, 5 }
    elseif pos == "TOPRIGHT" then
        -- 自己在右上：左上、右中、左中、中央顶部
        return { 3, 2, 4, 5 }
    end
    return { 1, 2, 3, 4, 5 }
end

-- 显示一条远程高光：先找空槽，5 个全满就复用最早到期的那个
local function ShowRemoteHighlight(name, label, classToken, unitToken, forcedIndex)
    EnsureDB()
    if not AP_DB.spotlight.enabled then return end
    -- 组队限制由 OnAddonMessage 入口处理；调试接口 /run 仍可直接调用

    name = Sanitize(name, 40)
    label = Sanitize(label, 20)
    if name == "" or label == "" then return end

    local color = ClassColor(classToken)
    local now = Now()

    local slot
    if forcedIndex and remoteSlots[forcedIndex] then
        slot = remoteSlots[forcedIndex]
    else
        local order = GetRemoteSlotOrder()
        for _, idx in ipairs(order) do
            if not remoteSlots[idx].frame:IsShown() then
                slot = remoteSlots[idx]
                break
            end
        end
        if not slot then
            slot = remoteSlots[order[1]]
            for _, idx in ipairs(order) do
                if remoteSlots[idx].expireAt < slot.expireAt then
                    slot = remoteSlots[idx]
                end
            end
        end
    end

    -- 每次占用都换 token：旧槽位如果被复用，旧的隐藏回调不会被误触发
    slot.token = slot.token + 1
    local myToken = slot.token
    slot.expireAt = now + 3.4

    slot.frame:SetBackdropBorderColor(color.r, color.g, color.b, 0.9)
    slot.accent:SetColorTexture(color.r, color.g, color.b, 1)

    if unitToken and type(SetPortraitTexture) == "function"
        and pcall(SetPortraitTexture, slot.portrait, unitToken) then
        -- 找到队友单位：显示他的真实头像
    else
        -- 找不到单位：显示职业图标
        local icon = "Interface\\Icons\\ClassIcon_" .. tostring(classToken)
        if not pcall(slot.portrait.SetTexture, slot.portrait, icon) then
            slot.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    slot.text:SetText("【" .. name .. "】\n开启了 " .. HexCode(color) .. label .. "|r！")
    slot.frame:SetAlpha(1)
    slot.frame:Show()

    -- 3 秒后淡出。淡出动画按槽位复用，避免每次触发都新建 AnimationGroup。
    After(3, function()
        if slot.token ~= myToken then return end
        local group = slot.frame.apFadeOut
        if not group then
            group = slot.frame:CreateAnimationGroup()
            local fade = group:CreateAnimation("Alpha")
            fade:SetDuration(0.3)
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0)
            slot.frame.apFadeOut = group
        end
        -- 每次播放前更新 OnFinished：槽位可能已经被新玩家复用，
        -- 用当前这次显示的 token 判断，避免旧回调把新内容隐藏掉。
        group:SetScript("OnFinished", function()
            if slot.token == myToken then slot.frame:Hide() end
        end)
        group:Stop()
        group:Play()
    end)
end

-- 接收端防刷屏：同一个发送者 3 秒内只显示一次。
-- 不同玩家不再互相挤占，各自拿一个槽位。
local lastRemoteAt = {}

local function OnAddonMessage(prefix, message, sender)
    EnsureDB()
    -- 勾选“只在组队/团队中触发”后，单人状态直接跳过
    if AP_DB.spotlight.groupOnly and not IsInGroupNow() then return end
    if type(prefix) ~= "string" or IsSecret(prefix) or prefix ~= PREFIX then return end
    if type(message) ~= "string" or IsSecret(message) then return end

    if not AP_DB.spotlight.enabled then return end
    local classToken, displayName, label = message:match("^H1|([^|]*)|([^|]*)|(.*)$")
    if not classToken or not CLASS_TOKENS[classToken] then return end

    displayName = Sanitize(displayName, 40)
    label = Sanitize(label, 20)
    if displayName == "" or label == "" then return end
    if type(sender) ~= "string" or IsSecret(sender) then return end

    -- 跨服名字可能带“-服务器”，这里只取角色名
    local senderName = sender:match("^([^%-]+)") or sender
    local okMyName, myName = pcall(UnitName, "player")
    if okMyName and type(myName) == "string" and myName == senderName then return end

    local now = Now()
    if lastRemoteAt[senderName] and now - lastRemoteAt[senderName] < 3 then return end
    lastRemoteAt[senderName] = now

    -- 远程队友的高光只显示画面，不播声音：
    -- 声音文件在每个人自己的客户端里，别让别人的高光用你的音效乱响。
    ShowRemoteHighlight(displayName, label, classToken, FindUnitByName(senderName))
end

-- ==========================================
-- 7. 事件：监听自己成功施放技能
-- ==========================================
-- UNIT_SPELLCAST_SUCCEEDED 的参数顺序各版本不同：
--   现代：unit, castGUID, spellID
--   老版：unit, spellName, spellRank, spellID
-- 所以下面不认死参数位置，而是挑“看起来像数字”的那个当 spellID。
local lastCastAt = {}
local lastShowAt = 0

-- 本地触发间隔由玩家在右页「释放间距」调整（1~10 分钟）
local lastTriggerAt = 0

-- 调试日志：默认关闭。游戏里输入 /AP spotlog 可开关。
-- 用来确认“到底有没有收到施法事件、事件里的技能 ID 和名字是什么”。
local debugEnabled = false
local function DebugPrint(text)
    if not debugEnabled then return end
    print("|cffffd700[高光调试]|r " .. tostring(text))
end

local eventFrame = CreateFrame("Frame")
local function SafeRegister(frame, event)
    if type(frame.RegisterEvent) == "function" then
        pcall(frame.RegisterEvent, frame, event)
    end
end
SafeRegister(eventFrame, "UNIT_SPELLCAST_SUCCEEDED")
SafeRegister(eventFrame, "CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "CHAT_MSG_ADDON" then
        -- CHAT_MSG_ADDON: prefix, message, channel, sender
        OnAddonMessage(arg1, arg2, arg4)
        return
    end

    if debugEnabled then
        DebugPrint("事件参数类型：unit=" .. type(arg1)
            .. " arg2=" .. type(arg2) .. " arg3=" .. type(arg3) .. " arg4=" .. type(arg4)
            .. " secret3=" .. tostring(IsSecret(arg3)))
    end

    -- 只关心自己；队友的技能由广播那边处理。
    -- 先确认 arg1 是普通字符串，secret 值不能直接比较。
    if type(arg1) ~= "string" or IsSecret(arg1) or arg1 ~= "player" then return end

    local spellID, eventName
    if type(arg2) == "number" then
        spellID = arg2
    elseif type(arg3) == "number" then
        spellID = arg3
    elseif type(arg4) == "number" then
        spellID = arg4
    end

    -- 关键坑：现代客户端的第二个参数是施法 GUID（形如 "Cast-3-..."），
    -- 只有老版本才是技能名。必须把 GUID 排除掉，否则后面拿它当技能名去查表，
    -- 真正的名字兜底就永远不会执行，私服改了技能 ID 时会完全不触发。
    if type(arg2) == "string" and not IsSecret(arg2) and arg2:sub(1, 5) ~= "Cast-" then
        eventName = arg2
    end

    -- secret 值不能读、不能比较，直接放弃这次触发
    if spellID and IsSecret(spellID) then return end
    if eventName and IsSecret(eventName) then eventName = nil end
    if not spellID and not eventName then return end

    -- 起手高光让位给正面形象：Emotes.lua 登记了这次施法，消费后跳过本次高光
    if AP_SuppressSpotlightAt and (GetTime() - AP_SuppressSpotlightAt > 20) then
        AP_SuppressSpotlightSpell = nil
        AP_SuppressSpotlightAt = nil
    end
    local suppressedHighLight = false
    if spellID and AP_SuppressSpotlightSpell == spellID then
        AP_SuppressSpotlightSpell = nil
        AP_SuppressSpotlightAt = nil
        suppressedHighLight = true
    end

    if debugEnabled then
        DebugPrint("收到施法：spellID=" .. tostring(spellID)
            .. "，事件名=" .. tostring(eventName)
            .. "，查询名=" .. tostring(FetchSpellName(spellID)))
    end

    EnsureDB()
    -- 高光总开关只拦高光视觉和广播；40/50 特效不受它影响
    local highLightEnabled = AP_DB.spotlight.enabled
    -- 勾选“只在组队/团队中触发”后，单人状态直接跳过
    if AP_DB.spotlight.groupOnly and not IsInGroupNow() then
        DebugPrint("触发范围是“仅组队/团队”，当前是单人，整次触发跳过")
        return
    end

    local classToken = CurrentClass()
    if not classToken then return end

    local now = Now()
    local custom = GetCustomSpell()
    local coreLevel = custom and GetCoreLevel() or 0
    local info

    if debugEnabled then
        DebugPrint("核心技能=" .. tostring(custom)
            .. "，核心等级=" .. tostring(coreLevel))
    end

    if debugEnabled then
        DebugPrint("当前模式：" .. (custom and ("自定义大招=" .. custom) or "默认职业表")
            .. "，职业=" .. tostring(classToken))
    end

    if custom then
        -- ===== 自定义模式：只认玩家自己设置的那一个大招 =====
        -- 输入纯数字按 SpellID 匹配；输入文字按官方技能名匹配。
        -- 文字匹配允许“包含”：比如填“化身”，可以命中“化身：艾露恩之眷”。
        local officialName = eventName or FetchSpellName(spellID)
        local customID = tonumber(custom)
        local matched = false
        if customID then
            matched = (spellID ~= nil and spellID == customID)
        elseif officialName then
            matched = (officialName == custom) or (officialName:find(custom, 1, true) ~= nil)
        end
        if not matched then
            if debugEnabled then
                DebugPrint("自定义大招未命中：设置=" .. custom .. "，实际技能名=" .. tostring(officialName))
            end
            return
        end

        -- 大字优先显示官方技能名；如果用户只填了 ID，就去查一次名字
        local label = custom
        if customID then label = FetchSpellName(customID) or custom end
        info = { label = label, official = officialName, id = spellID or customID, sound = "EPIC" }
        -- 记下真实 spellID，之后图标可以直接取这个技能的原图标
        if spellID and type(spellID) == "number" then
            AP_DB.spotlight.coreSpellID = spellID
            -- 第一次施放会补上 ID；如果面板开着，顺手刷新球池里的图标
            local panel4 = AP_Panels and AP_Panels[4]
            if panel4 and panel4.LeftPage and panel4.LeftPage:IsVisible()
                and AP_Spotlight and AP_Spotlight.RefreshCoreUI then
                AP_Spotlight.RefreshCoreUI()
            end
        end
    else
        -- ===== 默认模式：按职业表匹配 =====
        -- 先按 SpellID 查；查不到再按官方技能名查（兼容私服改 ID）
        if spellID then
            local ok, found = pcall(function() return BY_ID[classToken] and BY_ID[classToken][spellID] end)
            if ok then info = found end
        end
        if not info then
            local spellName = eventName or FetchSpellName(spellID)
            if spellName then
                local ok, found = pcall(function() return BY_NAME[classToken] and BY_NAME[classToken][spellName] end)
                if ok then info = found end
            end
        end
    end
    if not info then
        if debugEnabled then
            DebugPrint("未命中默认表：职业=" .. tostring(classToken) .. "，spellID=" .. tostring(spellID))
        end
        return
    end

    -- 触发间隔：0 = 无限制，1~10 分钟
    local cooldownMinutes = math.floor(tonumber(AP_DB.spotlight.cooldownMinutes) or 1)
    if cooldownMinutes < 0 then cooldownMinutes = 0 end
    if cooldownMinutes > 10 then cooldownMinutes = 10 end
    if cooldownMinutes > 0 then
        local cooldownSec = cooldownMinutes * 60
        if lastTriggerAt > 0 and now - lastTriggerAt < cooldownSec then
            if debugEnabled then
                DebugPrint("触发间隔中，剩余约 "
                    .. math.ceil(cooldownSec - (now - lastTriggerAt)) .. " 秒")
            end
            return
        end
    end

    -- 同一技能 3 秒内只弹一次；全局 0.5 秒内只弹一次（防止连按多个技能时叠在一起）
    local key = spellID or info.id or info.label
    if lastCastAt[key] and now - lastCastAt[key] < 3 then return end
    if now - lastShowAt < 0.5 then return end
    lastCastAt[key] = now
    lastShowAt = now
    lastTriggerAt = now

    -- ===== 核心技能培养的等级门槛 =====
    -- 40/50 特效有各自的开关，独立于 20 级高光开关
    if custom and AP_Aura and AP_Aura.Trigger then
        AP_Aura.Trigger(classToken, AP_DB.flavor and AP_DB.flavor.currentFaction)
    end

    -- 起手让位给正面形象时，只跳过本次高光视觉和广播；特效已经执行过了
    if suppressedHighLight then
        if debugEnabled then DebugPrint("本次高光让位给正面形象，特效继续") end
        return
    end

    -- 20 级才出现高光视觉与广播
    if custom and coreLevel < 20 then
        if debugEnabled then
            DebugPrint("核心技能 Lv." .. coreLevel .. "，未到 20 级，本次不弹高光")
        end
        return
    end
    if not highLightEnabled then
        if debugEnabled then DebugPrint("高光总开关已关闭，本次只走特效，不弹高光") end
        return
    end

    -- 改过名就用新名字；否则跟称谓典籍的流派称呼走
    local displayLabel = GetCoreDisplayLabel(info.official, info.label)
    -- 本机按技能 ID 找立绘；远程队友不会加载你的图片文件，所以不加进广播
    local imagePath = info.id and PORTRAIT_IMAGES[info.id]
    ShowHighlight(GetDisplayName(), displayLabel, classToken, "player", info.sound, imagePath)
    BroadcastHighlight(classToken, displayLabel)
end)

-- ==========================================
-- 8. 设置页（第 4 个 Tab：核心奥义）
-- ==========================================
-- 先占个名字，面板创建成功后再换成真正的刷新函数（供 /AP 调试和以后扩展调用）
local RefreshSkillList = function() end
local RefreshCoreUI -- 核心技能培养视图的刷新函数，UI 块里赋值
local previewBtn, posBtn

local panel = AP_Panels and AP_Panels[4]
if panel and panel.LeftPage and panel.RightPage then
    local left, right = panel.LeftPage, panel.RightPage

    local title = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -30)
    title:SetFont(title:GetFont(), 24, "")
    title:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    title:SetText("核心奥义")

    -- ==========================================
    -- 左页重做：核心技能培养
    -- ==========================================
    -- 未选：从当前职业/流派的“技能”词条里挑一个；
    -- 已选：显示核心技能卡片、等级、按等级解锁的功能。
    local chooseFrame = CreateFrame("Frame", nil, left)
    chooseFrame:SetAllPoints(left)

    local coreFrame = CreateFrame("Frame", nil, left)
    coreFrame:SetAllPoints(left)
    coreFrame:Hide()

    local chooseIntro = chooseFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chooseIntro:SetPoint("TOPLEFT", chooseFrame, "TOPLEFT", 30, -66)
    chooseIntro:SetWidth(340)
    chooseIntro:SetJustifyH("LEFT")
    chooseIntro:SetSpacing(4)
    chooseIntro:SetFont(chooseIntro:GetFont(), 15, "")
    chooseIntro:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    chooseIntro:SetText("|cff8c261a选择一个核心技能长期培养|r\n|cff6b5a45熟练度越高，高光解锁的功能越多；数据与「称谓典籍」共用。|r")

    local chooseScroll = CreateFrame("ScrollFrame", nil, chooseFrame, "UIPanelScrollFrameTemplate")
    chooseScroll:SetPoint("TOPLEFT", chooseFrame, "TOPLEFT", 30, -118)
    chooseScroll:SetSize(340, 340)
    local chooseChild = CreateFrame("Frame", nil, chooseScroll)
    chooseChild:SetWidth(320)
    chooseChild:SetHeight(1)
    chooseScroll:SetScrollChild(chooseChild)

    local chooseEmpty = chooseFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chooseEmpty:SetPoint("TOP", chooseFrame, "TOP", 0, -200)
    chooseEmpty:SetFont(chooseEmpty:GetFont(), 14, "")
    chooseEmpty:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
    chooseEmpty:SetText("当前流派的词条里没有可培养的技能。")
    chooseEmpty:Hide()

    -- 核心技能候选过滤：去掉 1 级初始技能、被动/buff、种族技能。
    -- 技能书扫描失败时只按 STARTER_SPELLS 名单兜底。
    local STARTER_SPELLS = {
        ["月火术"] = true, ["愤怒"] = true, ["治疗之触"] = true,
        ["野性印记"] = true, ["回春术"] = true, ["树皮术"] = true,
        ["纠缠根须"] = true, ["精灵之火"] = true,
        ["熊形态"] = true, ["猎豹形态"] = true, ["旅行形态"] = true,
    }

    local function BuildSpellBookInfoMap()
        local map = {}

        -- 1) 现代法术书
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
            and C_SpellBook.GetSpellBookSkillLineInfo
            and C_SpellBook.GetSpellBookItemInfo then
            local okLines, lineCount = pcall(C_SpellBook.GetNumSpellBookSkillLines)
            if okLines and type(lineCount) == "number" then
                for lineIndex = 1, lineCount do
                    local okLine, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
                    if okLine and type(lineInfo) == "table" then
                        local offset = lineInfo.itemIndexOffset or 0
                        local count = lineInfo.numSpellBookItems or 0
                        local isRace = type(lineInfo.name) == "string" and lineInfo.name:find("种族") ~= nil
                        for j = 1, count do
                            local okItem, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, offset + j, "spell")
                            if okItem and type(itemInfo) == "table" and itemInfo.spellID then
                                local name = FetchSpellName(itemInfo.spellID)
                                if name and not map[name] then
                                    local passive = false
                                    local harmful = false
                                    if C_Spell and C_Spell.IsSpellPassive then
                                        local okP, p = pcall(C_Spell.IsSpellPassive, itemInfo.spellID)
                                        passive = okP and p or false
                                    end
                                    if C_Spell and C_Spell.IsSpellHarmful then
                                        local okH, h = pcall(C_Spell.IsSpellHarmful, itemInfo.spellID)
                                        harmful = okH and h or false
                                    end
                                    map[name] = {
                                        spellID = itemInfo.spellID,
                                        passive = passive,
                                        harmful = harmful,
                                        race = isRace,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2) 旧版天赋树：补上法术书里没有的天赋技能和技能图标
        if type(GetNumTalentTabs) == "function" and type(GetTalentInfo) == "function" then
            local okTabs, tabCount = pcall(GetNumTalentTabs)
            if okTabs and type(tabCount) == "number" then
                for tab = 1, tabCount do
                    for index = 1, 30 do
                        local ok, name, icon = pcall(GetTalentInfo, tab, index)
                        if not ok or type(name) ~= "string" or name == "" then break end
                        if not map[name] then
                            map[name] = { icon = icon, talent = true }
                        elseif not map[name].icon and icon then
                            map[name].icon = icon
                        end
                    end
                end
            end
        end

        return map
    end

    local function TrySpellTexture(spellID)
        if type(spellID) ~= "number" then return nil end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
        if type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
        return nil
    end

    -- 按技能名反查 spellID：旧客户端 GetSpellInfo 的第 7 个返回值就是 ID。
    -- 重选技能时按钮上可能没有 ID，用它补上，避免图标退化成职业图标。
    local function TrySpellIDByName(name)
        if type(name) ~= "string" or name == "" then return nil end
        if type(GetSpellInfo) == "function" then
            local ok, _, _, _, _, _, _, spellID = pcall(GetSpellInfo, name)
            if ok and type(spellID) == "number" then return spellID end
        end
        return nil
    end

    -- 按技能名直接取图标：旧客户端 GetSpellTexture 允许传名字
    local function TrySpellTextureByName(name)
        if type(name) ~= "string" or name == "" then return nil end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, name)
            if ok and tex then return tex end
        end
        if type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, name)
            if ok and tex then return tex end
        end
        return nil
    end

    local function GetCoreSpellIcon(official)
        EnsureDB()
        -- 1) 施放时记录过 spellID 的，直接取原图标，最准
        local tex = TrySpellTexture(AP_DB.spotlight.coreSpellID)
        if tex then return tex end

        -- 2) 刚重选、还没施放过的技能没有 ID，按名字取一次图标
        tex = TrySpellTextureByName(official)
        if tex then return tex end
        tex = TrySpellTexture(TrySpellIDByName(official))
        if tex then return tex end

        -- 3) 法术书 / 旧版天赋树扫描到的技能
        local info = BuildSpellBookInfoMap()[official]
        if info then
            tex = TrySpellTexture(info.spellID)
            if tex then return tex end
            if info.icon then return info.icon end
        end

        return "Interface\\Icons\\ClassIcon_" .. tostring(CurrentClass())
    end

    local chooseButtons = {}
    for i = 1, 24 do
        local btn = CreateFrame("Button", nil, chooseChild, "UIPanelButtonTemplate")
        btn:SetSize(320, 30)
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
        local fs = btn:GetFontString()
        if fs then
            fs:SetFont(fs:GetFont(), 12, "")
        end
        btn:SetScript("OnClick", function(self)
            local term = self.term
            if not term then return end
            EnsureDB()
            AP_DB.spotlight.coreSpell = term.official
            AP_DB.spotlight.customSpell = term.official
            AP_DB.spotlight.coreSpellID = self.spellID
            AP_DB.spotlight.coreAlias = ""
            ClearAliasCache()
            RefreshCoreUI()
        end)
        chooseButtons[i] = btn
    end

    -- ---------- 已选：核心技能名（图标移进球池中心） ----------
    -- 原来头顶那块带图标的小卡片不要了，只在球池上方留一行技能名。
    local coreName = coreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    coreName:SetPoint("TOP", coreFrame, "TOP", 0, -66)
    coreName:SetWidth(300)
    coreName:SetJustifyH("CENTER")
    coreName:SetFont(coreName:GetFont(), 20, "OUTLINE")
    coreName:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    coreName:SetText("核心技能")

    -- ---------- 球池：满溢程度 = 核心等级 ----------
    -- 旧客户端没有圆形遮罩，所以把球拆成 64 条横条：
    -- 每条按圆的弦长算宽度，拼起来就是一个圆。
    -- 液面以上是深色玻璃，液面以下是职业色液体。
    local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
    local ORB_R = 68                      -- 球的半径
    local ORB_BARS = 64                   -- 横条数量，越多越圆滑
    local ORB_BAR_H = (ORB_R * 2) / ORB_BARS
    local ORB_DIAMETER = ORB_R * 2

    local orbFrame = CreateFrame("Frame", nil, coreFrame)
    orbFrame:SetSize(ORB_DIAMETER + 30, ORB_DIAMETER + 16)
    orbFrame:SetPoint("TOP", coreFrame, "TOP", 0, -172)

    -- 球底阴影：两条半透明黑条，让球看起来是“放在”书页上的
    local orbShadowWide = orbFrame:CreateTexture(nil, "BACKGROUND")
    orbShadowWide:SetTexture(WHITE_TEX)
    orbShadowWide:SetSize(104, 5)
    orbShadowWide:SetPoint("TOP", orbFrame, "TOP", 0, ORB_DIAMETER + 4)
    orbShadowWide:SetVertexColor(0, 0, 0, 0.10)

    local orbShadowDeep = orbFrame:CreateTexture(nil, "BACKGROUND")
    orbShadowDeep:SetTexture(WHITE_TEX)
    orbShadowDeep:SetSize(72, 8)
    orbShadowDeep:SetPoint("TOP", orbFrame, "TOP", 0, ORB_DIAMETER + 3)
    orbShadowDeep:SetVertexColor(0, 0, 0, 0.12)

    local orbOutline, orbGlass, orbLiquid, orbShine = {}, {}, {}, {}
    for i = 1, ORB_BARS do
        -- cy 是这条横条中心相对球心的高度；越靠近球顶/球底，弦长越短
        local cy = (i - 0.5) * ORB_BAR_H - ORB_R
        local half = math.sqrt(math.max(0, ORB_R * ORB_R - cy * cy))
        local y = -(i - 1) * ORB_BAR_H

        -- 1) 外圈描边：比玻璃略宽，勾出球的轮廓
        local outline = orbFrame:CreateTexture(nil, "BACKGROUND")
        outline:SetTexture(WHITE_TEX)
        outline:SetSize(half * 2 + 3, ORB_BAR_H + 0.6)
        outline:SetPoint("TOP", orbFrame, "TOP", 0, y)
        outline:SetVertexColor(0.34, 0.24, 0.14, 0.55)
        orbOutline[i] = outline

        -- 2) 玻璃底色：没有液体时看到的深色球体
        local glass = orbFrame:CreateTexture(nil, "ARTWORK")
        glass:SetTexture(WHITE_TEX)
        glass:SetSize(math.max(1, half * 2 - 1), ORB_BAR_H + 0.6)
        glass:SetPoint("TOP", orbFrame, "TOP", 0, y)
        glass:SetVertexColor(0.09, 0.07, 0.05, 0.92)
        orbGlass[i] = glass

        -- 3) 液体：比玻璃再窄一点，留出玻璃壁的厚度
        local liquid = orbFrame:CreateTexture(nil, "ARTWORK")
        liquid:SetTexture(WHITE_TEX)
        liquid:SetSize(math.max(1, half * 2 - 4), ORB_BAR_H + 0.6)
        liquid:SetPoint("TOP", orbFrame, "TOP", 0, y)
        liquid:SetVertexColor(0.55, 0.82, 1, 1)
        liquid:SetAlpha(0)   -- 具体哪些横条显示由液面动画决定
        orbLiquid[i] = liquid

        -- 4) 左上方的一小块反光，只画球体上 1/3，增加玻璃质感
        if i <= math.floor(ORB_BARS * 0.33) then
            local shine = orbFrame:CreateTexture(nil, "OVERLAY")
            shine:SetTexture(WHITE_TEX)
            shine:SetSize(math.max(2, half * 0.45), ORB_BAR_H + 0.6)
            shine:SetPoint("TOP", orbFrame, "TOP", -half * 0.45, y)
            shine:SetVertexColor(1, 1, 1, 0.09)
            orbShine[i] = shine
        end
    end

    local coreResetBtn = CreateFrame("Button", nil, coreFrame, "UIPanelButtonTemplate")
    coreResetBtn:SetSize(26, 22)
    coreResetBtn:SetPoint("TOPLEFT", orbFrame, "TOPRIGHT", -10, -6)
    coreResetBtn:SetFrameLevel(orbFrame:GetFrameLevel() + 8)
    coreResetBtn:SetText("×")
    coreResetBtn:SetScript("OnClick", function()
        local official = GetCoreSpellName()
        if official then
            StaticPopup_Show("AP_SPOTLIGHT_RESET_CORE", official)
        end
    end)

    -- 核心等级：从原卡片里挪到球池下方
    local coreLevelText = coreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coreLevelText:SetPoint("TOP", coreFrame, "TOP", 0, -318)
    coreLevelText:SetWidth(320)
    coreLevelText:SetJustifyH("CENTER")
    coreLevelText:SetFont(coreLevelText:GetFont(), 13, "")
    coreLevelText:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
    coreLevelText:SetText("")

    -- ---------- 核心描述（球池上方，约两行） ----------
    local descLabel = coreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descLabel:SetPoint("TOPLEFT", coreFrame, "TOPLEFT", 30, -98)
    descLabel:SetFont(descLabel:GetFont(), 13, "")
    descLabel:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
    descLabel:SetText("核心描述")

    local coreDescInput = CreateFrame("EditBox", nil, coreFrame, "BackdropTemplate")
    coreDescInput:SetSize(340, 40)
    coreDescInput:SetPoint("TOPLEFT", coreFrame, "TOPLEFT", 30, -116)
    coreDescInput:SetFontObject("GameFontNormalSmall")
    coreDescInput:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    coreDescInput:SetTextInsets(6, 6, 4, 4)
    coreDescInput:SetAutoFocus(false)
    -- 多行：文字超出宽度会自动折到第二行
    coreDescInput:SetMultiLine(true)
    coreDescInput:SetMaxLetters(80)
    coreDescInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    coreDescInput:SetBackdropColor(1, 0.96, 0.85, 0.55)
    coreDescInput:SetBackdropBorderColor(0.30, 0.20, 0.10, 0.8)
    coreDescInput:SetText(AP_DB.spotlight.coreDesc or "")
    local function SaveCoreDesc()
        local value = Trim(Sanitize(coreDescInput:GetText() or "", 80))
        AP_DB.spotlight.coreDesc = value
        coreDescInput:SetText(value)
    end
    coreDescInput:SetScript("OnEnterPressed", function(self)
        SaveCoreDesc()
        self:ClearFocus()
    end)
    coreDescInput:SetScript("OnEditFocusLost", SaveCoreDesc)

    -- ---------- 左页：等级解锁功能（只读） ----------
    local unlockTitle = coreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unlockTitle:SetPoint("TOPLEFT", coreFrame, "TOPLEFT", 30, -344)
    unlockTitle:SetFont(unlockTitle:GetFont(), 13, "")
    unlockTitle:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
    unlockTitle:SetText("等级解锁")

    local unlockText = coreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unlockText:SetPoint("TOPLEFT", coreFrame, "TOPLEFT", 30, -366)
    unlockText:SetWidth(340)
    unlockText:SetJustifyH("LEFT")
    unlockText:SetSpacing(5)
    unlockText:SetFont(unlockText:GetFont(), 13, "")
    unlockText:SetText("")

    -- ---------- 球池动态 ----------
    -- 液体高度用 orbFill（0~1）表示：0 级留一点底液，50 级接近满溢。
    -- 液面、气泡和图标都在 OnUpdate 里缓缓动，平时几乎不耗性能。
    local orbFill = 0.05
    local orbTargetFill = 0.05
    local orbElapsed = 0
    local orbAcc = 0

    -- 取液体颜色：优先职业色，客户端没给职业色时退回流派主题色
    local function GetCoreThemeColor()
        local classToken = CurrentClass()
        local classColor = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
        local factionID = AP_DB.flavor and AP_DB.flavor.currentFaction
        if AP_Aura and AP_Aura.GetTheme then
            local theme = AP_Aura.GetTheme(classToken, factionID)
            if theme and theme.color then
                return theme.color[1], theme.color[2], theme.color[3]
            end
        end
        return AP_Theme.accent[1], AP_Theme.accent[2], AP_Theme.accent[3]
    end

    -- 设置等级（0~50）和液体颜色；液面会自己慢慢涨过去
    local function SetOrbLevel(level, r, g, b)
        level = math.max(0, math.min(50, tonumber(level) or 0))
        orbTargetFill = 0.05 + (level / 50) * 0.92
        if r then
            for i = 1, ORB_BARS do
                -- 液体越往下越暗，模拟球体底部的阴影，立体感更强
                local shade = 0.72 + (1 - i / ORB_BARS) * 0.30
                orbLiquid[i]:SetVertexColor(r * shade, g * shade, b * shade, 1)
                -- 外圈用职业色的暗调，像玻璃壁映出的颜色
                orbOutline[i]:SetVertexColor(r * 0.30 + 0.10, g * 0.30 + 0.07, b * 0.30 + 0.05, 0.62)
            end
        end
    end

    -- 气泡：几颗小白点，在液体里从球底往上浮
    local orbBubbles = {}
    for i = 1, 6 do
        local tex = orbFrame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(WHITE_TEX)
        tex:SetSize(4, 4)
        tex:SetVertexColor(1, 1, 1, 0.30)
        orbBubbles[i] = {
            tex = tex,
            pos = math.random(),
            side = math.random() * 2 - 1,
            speed = 0.12 + math.random() * 0.10,
        }
    end

    orbFrame:SetScript("OnUpdate", function(self, dt)
        -- 每秒更新约 20 次就够了，既顺滑又不浪费性能
        orbAcc = orbAcc + dt
        if orbAcc < 0.05 then return end
        local step = orbAcc
        orbAcc = 0

        -- 液面平滑追上目标高度：升级时会看到液体缓缓上涨
        if math.abs(orbTargetFill - orbFill) > 0.0005 then
            orbFill = orbFill + (orbTargetFill - orbFill) * math.min(1, step * 3)
        end

        orbElapsed = orbElapsed + step
        local fillPx = orbFill * ORB_DIAMETER
        local liquidTop = ORB_R - fillPx        -- 液面相对球心的 y（向下为正）
        local sway = math.sin(orbElapsed * 1.8) * 2.2

        for i = 1, ORB_BARS do
            local cy = (i - 0.5) * ORB_BAR_H - ORB_R
            local barBottom = cy + ORB_BAR_H / 2
            -- 每条横条按自己的相位轻微起伏，液面就不是一条死板的直线
            local wave = math.sin(orbElapsed * 2.6 + i * 0.65) * 1.8
            local surface = liquidTop + sway + wave
            local coverage = (barBottom - surface) / ORB_BAR_H
            coverage = math.max(0, math.min(1, coverage))
            orbLiquid[i]:SetAlpha(coverage * 0.88)
        end

        -- 气泡只在液体够多时出现
        local showBubbles = fillPx > ORB_BAR_H * 2
        for i = 1, #orbBubbles do
            local bubble = orbBubbles[i]
            if not showBubbles then
                bubble.tex:Hide()
            else
                bubble.tex:Show()
                bubble.pos = bubble.pos + bubble.speed * step
                if bubble.pos > 1 then
                    bubble.pos = 0
                    bubble.side = math.random() * 2 - 1
                end
                local yOff = ORB_R - bubble.pos * fillPx
                local half = math.sqrt(math.max(0, ORB_R * ORB_R - yOff * yOff))
                bubble.tex:SetPoint("CENTER", orbFrame, "TOP",
                    bubble.side * half * 0.62, -(ORB_R + yOff))
                bubble.tex:SetAlpha(math.min(1, math.sin(bubble.pos * math.pi)) * 0.35)
            end
        end
    end)

    -- ---------- 右页：等级操作 + 两个总设置 ----------
    local function EnableText()
        return AP_DB.spotlight.enabled and "已开启" or "已关闭"
    end
    local function ScopeText()
        return AP_DB.spotlight.groupOnly and "仅组队 / 团队" or "所有人"
    end

    local soundNames = { "随机", "sound1.ogg", "sound2.ogg", "sound3.ogg" }
    local function SoundButtonText()
        local index = AP_DB.spotlight.soundIndex or 0
        if index == -1 then return "已关闭" end
        return soundNames[index + 1] or "随机"
    end
    local function CycleSound()
        if GetCoreLevel() < 30 then return end
        local index = AP_DB.spotlight.soundIndex or 0
        if index == 3 then
            index = -1
        elseif index == -1 then
            index = 0
        else
            index = index + 1
        end
        AP_DB.spotlight.soundIndex = index
        if index ~= -1 and AP_DB.spotlight.sound then
            PlaySpotSound("EPIC")
        end
    end

    -- 左标签 + 右值，点整行切换；值文字用暗金色提示可点
    local function MakeToggleRow(parent, label, y, valueFunc, onClick)
        local host = parent or coreFrame
        local labelFS = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT", host, "TOPLEFT", 30, y)
        labelFS:SetFont(labelFS:GetFont(), 14, "")
        labelFS:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
        labelFS:SetText(label)

        local valueFS = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valueFS:SetPoint("LEFT", labelFS, "RIGHT", 14, 0)
        valueFS:SetFont(valueFS:GetFont(), 14, "OUTLINE")
        valueFS:SetTextColor(0.50, 0.30, 0.10)
        valueFS:SetText(valueFunc())

        local btn = CreateFrame("Button", nil, host)
        btn:SetPoint("TOPLEFT", labelFS, "TOPLEFT", -4, 4)
        btn:SetPoint("BOTTOMRIGHT", valueFS, "BOTTOMRIGHT", 16, -4)
        btn:SetScript("OnClick", function()
            onClick()
            valueFS:SetText(valueFunc())
        end)
        btn:SetScript("OnEnter", function() valueFS:SetTextColor(0.85, 0.42, 0.10) end)
        btn:SetScript("OnLeave", function() valueFS:SetTextColor(0.50, 0.30, 0.10) end)
        btn.labelFS = labelFS
        btn.valueFS = valueFS
        return valueFS, btn
    end

    -- 整行显隐：未解锁的等级功能在右页完全不显示
    local function SetRowShown(valueFS, btn, shown)
        if btn and btn.labelFS then
            if shown then btn.labelFS:Show() else btn.labelFS:Hide() end
        end
        if valueFS then
            if shown then valueFS:Show() else valueFS:Hide() end
        end
        if btn then
            if shown then btn:Show() else btn:Hide() end
        end
    end

    -- 广播默认开启
    if AP_DB.spotlight.broadcast == nil then AP_DB.spotlight.broadcast = true end

    -- ---------- 15 级：改名 ----------
    local aliasLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aliasLabel:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -94)
    aliasLabel:SetFont(aliasLabel:GetFont(), 14, "")
    aliasLabel:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    aliasLabel:SetText("15 级 · 修改核心技能名字")

    local aliasInput = CreateFrame("EditBox", nil, right, "BackdropTemplate")
    aliasInput:SetSize(240, 28)
    aliasInput:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -116)
    aliasInput:SetFontObject("GameFontNormal")
    aliasInput:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    aliasInput:SetTextInsets(6, 6, 0, 0)
    aliasInput:SetAutoFocus(false)
    aliasInput:SetMaxLetters(40)
    aliasInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    aliasInput:SetBackdropColor(1, 0.96, 0.85, 0.55)
    aliasInput:SetBackdropBorderColor(0.30, 0.20, 0.10, 0.8)
    local aliasSavedText -- 先声明，下面的保存函数会用到

    local function SaveCoreAlias()
        if GetCoreLevel() < 15 then return end
        local value = Trim(Sanitize(aliasInput:GetText() or "", 40))
        local old = AP_DB.spotlight.coreAlias or ""
        AP_DB.spotlight.coreAlias = value
        aliasInput:SetText(value)
        if value ~= old then
            print("|cffffd700[AP]|r 核心技能名字已保存：" .. (value ~= "" and value or "（已清除）"))
        end
        aliasSavedText:SetText("已保存")
        ClearAliasCache()
        RefreshCoreUI()
    end
    aliasInput:SetScript("OnEnterPressed", function(self)
        SaveCoreAlias()
        self:ClearFocus()
    end)
    aliasInput:SetScript("OnEditFocusLost", SaveCoreAlias)

    -- 不再放“保存”按钮：输入后回车/失焦自动保存，旁边只显示状态
    aliasSavedText = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    aliasSavedText:SetPoint("LEFT", aliasInput, "RIGHT", 10, 0)
    aliasSavedText:SetFont(aliasSavedText:GetFont(), 12, "")
    aliasSavedText:SetTextColor(0.25, 0.45, 0.2)
    aliasSavedText:SetText("")
    aliasInput:SetScript("OnEditFocusGained", function() aliasSavedText:SetText("") end)

    -- ---------- 20 级：高光时刻总开关 ----------
    local highLightValue, highLightRowBtn = MakeToggleRow(right, "20 级 · 高光时刻", -166,
        EnableText, function()
            AP_DB.spotlight.enabled = not AP_DB.spotlight.enabled
        end)

    -- ---------- 30 级：本地音效 ----------
    local soundValue, soundRowBtn = MakeToggleRow(right, "30 级 · 本地音效", -200,
        SoundButtonText, CycleSound)
    soundRowBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("本地高光音效", 1, 0.82, 0.2)
        GameTooltip:AddLine("文件放在 AzerothParallel\\Media\\sounds\\ 下", 1, 1, 1)
        GameTooltip:AddLine("sound1.ogg / sound2.ogg / sound3.ogg", 1, 1, 1)
        GameTooltip:AddLine("点击切换；30 级解锁", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    soundRowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---------- 40 级：流派施放特效 ----------
    local function AuraText()
        if not (AP_Aura and AP_Aura.IsUnlocked and AP_Aura.IsUnlocked()) then
            return "未解锁"
        end
        return (AP_Aura.IsEnabled and AP_Aura.IsEnabled()) and "已开启" or "已关闭"
    end

    local auraValue, auraRowBtn = MakeToggleRow(right, "40 级 · 施放特效", -232,
        AuraText, function()
            if AP_Aura and AP_Aura.Toggle then AP_Aura.Toggle() end
        end)

    local function HeadAuraText()
        if not (AP_HeadAura and AP_HeadAura.IsUnlocked and AP_HeadAura.IsUnlocked()) then
            return "未解锁"
        end
        return (AP_HeadAura.IsEnabled and AP_HeadAura.IsEnabled()) and "已开启" or "已关闭"
    end

    local headAuraValue, headAuraRowBtn = MakeToggleRow(right, "50 级 · 头顶特效", -264,
        HeadAuraText, function()
            if AP_HeadAura and AP_HeadAura.Toggle then AP_HeadAura.Toggle() end
        end)

    -- ---------- 触发范围 / 释放间距 ----------
    local scopeValue, scopeRowBtn = MakeToggleRow(right, "触发范围", -30, ScopeText, function()
        AP_DB.spotlight.groupOnly = not AP_DB.spotlight.groupOnly
    end)

    local function CooldownText()
        local minutes = AP_DB.spotlight.cooldownMinutes or 1
        if minutes <= 0 then return "无限制" end
        return minutes .. " 分钟"
    end
    local function CycleCooldown()
        local value = (AP_DB.spotlight.cooldownMinutes or 1) + 1
        if value > 10 then value = 0 end
        AP_DB.spotlight.cooldownMinutes = value
    end

    local cooldownValue, cooldownRowBtn = MakeToggleRow(right, "释放间距", -62,
        CooldownText, CycleCooldown)

    -- ---------- 视图刷新 ----------
    local function FillChooseList()
        local list, seen = {}, {}
        local spellInfo = BuildSpellBookInfoMap()
        local terms = AP_FlavorManager and AP_FlavorManager.GetTermList
            and AP_FlavorManager.GetTermList(CurrentClass(), AP_DB.flavor.currentFaction)
        if terms then
            for _, term in ipairs(terms) do
                local official = term.official
                if term.category == "技能" and official and not seen[official] then
                    local skip = STARTER_SPELLS[official] and true or false
                    local info = spellInfo[official]
                    if not skip and info and info.spellID then
                        -- 被动 / buff（非伤害）和种族技能不进候选
                        skip = info.passive or info.race or (not info.harmful)
                    end
                    if not skip then
                        seen[official] = true
                        table.insert(list, term)
                    end
                end
            end
        end
        for i, btn in ipairs(chooseButtons) do
            local term = list[i]
            if term then
                local info = spellInfo[term.official]
                btn.term = term
                -- 扫描不到 ID 时按技能名再查一次，保证选完就能显示技能原图标
                btn.spellID = (info and info.spellID) or TrySpellIDByName(term.official)
                btn:SetText((term.alias or term.official) .. "（" .. term.official .. "）")
                btn:Show()
            else
                btn.term = nil
                btn:Hide()
            end
        end
        chooseChild:SetHeight(math.max(1, #list * 34 + 10))
        if #list == 0 then chooseEmpty:Show() else chooseEmpty:Hide() end
    end

    RefreshCoreUI = function()
        if RefreshSkillList then RefreshSkillList() end
        local official = GetCoreSpellName()
        if not official then
            chooseFrame:Show()
            coreFrame:Hide()
            descLabel:Hide()
            coreDescInput:Hide()
            if previewBtn then previewBtn:Hide() end
            if posBtn then posBtn:Hide() end
            FillChooseList()
            return
        end

        chooseFrame:Hide()
        coreFrame:Show()
        descLabel:Show()
        coreDescInput:Show()
        if previewBtn then previewBtn:Show() end
        if posBtn then posBtn:Show() end

        local level = GetCoreLevel()
        local points = GetCorePoints()
        local maxProf = 300
        local okLevel, playerLevel = pcall(UnitLevel, "player")
        if okLevel and type(playerLevel) == "number" and not IsSecret(playerLevel) then
            maxProf = math.max(5, playerLevel * 5)
        end

        local displayName = ResolveFactionAlias(official, official) or official
        if (AP_DB.spotlight.coreAlias or "") ~= "" then
            displayName = AP_DB.spotlight.coreAlias
        end
        coreName:SetText("【" .. displayName .. "】")
        coreLevelText:SetText("核心 Lv." .. level .. " / 50    熟练度 " .. points .. "/" .. maxProf)
        -- 球池：等级决定液面高度，职业/流派色决定液体颜色
        local orbColorR, orbColorG, orbColorB = GetCoreThemeColor()
        SetOrbLevel(level, orbColorR, orbColorG, orbColorB)
        coreDescInput:SetText(AP_DB.spotlight.coreDesc or "")

        local function LevelState(n)
            if level >= n then return "|cff3f6b2e已解锁|r" end
            return "|cff8c261a还需 " .. (n - level) .. " 级|r"
        end
        unlockText:SetText(
            "15 级 · 修改核心技能名字    " .. LevelState(15) .. "\n" ..
            "20 级 · 高光时刻    " .. LevelState(20) .. "\n" ..
            "30 级 · 本地音效    " .. LevelState(30) .. "\n" ..
            "40 级 · 施放特效    " .. LevelState(40) .. "\n" ..
            "50 级 · 头顶特效    " .. LevelState(50)
        )

        local showAlias = level >= 15
        if showAlias then
            aliasLabel:Show()
            aliasInput:Show()
            aliasSavedText:Show()
            aliasLabel:SetText("15 级 · 修改核心技能名字")
            aliasInput:SetText(AP_DB.spotlight.coreAlias or "")
            if (AP_DB.spotlight.coreAlias or "") ~= "" then
                aliasSavedText:SetText("已保存")
            else
                aliasSavedText:SetText("")
            end
        else
            aliasLabel:Hide()
            aliasInput:Hide()
            aliasSavedText:Hide()
        end
        scopeValue:SetText(ScopeText())
        cooldownValue:SetText(CooldownText())

        local showHighLight = level >= 20
        SetRowShown(highLightValue, highLightRowBtn, showHighLight)
        if showHighLight then highLightValue:SetText(EnableText()) end

        local showSound = level >= 30
        SetRowShown(soundValue, soundRowBtn, showSound)
        if showSound then soundValue:SetText(SoundButtonText()) end

        local showAura = level >= 40
        SetRowShown(auraValue, auraRowBtn, showAura)
        if showAura then auraValue:SetText(AuraText()) end

        local showHead = level >= 50
        SetRowShown(headAuraValue, headAuraRowBtn, showHead)
        if showHead then headAuraValue:SetText(HeadAuraText()) end
    end

    -- 重练：清空该技能的熟练度和核心技能选择
    StaticPopupDialogs["AP_SPOTLIGHT_RESET_CORE"] = {
        text = "确定重练「%s」吗？\n\n该技能的熟练度会全部清零，核心技能选择也会解除。",
        button1 = "重练",
        button2 = "取消",
        OnAccept = function()
            EnsureDB()
            local official = GetCoreSpellName()
            if official and AP_DB.flavor and AP_DB.flavor.skillProf then
                AP_DB.flavor.skillProf[official] = nil
            end
            AP_DB.spotlight.coreSpell = ""
            AP_DB.spotlight.customSpell = ""
            AP_DB.spotlight.coreAlias = ""
            -- 旧技能的图标 ID 也一起清掉，免得重选后图标错位
            AP_DB.spotlight.coreSpellID = nil
            ClearAliasCache()
            RefreshCoreUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- 面板重新显示时刷新等级（战斗里熟练度可能涨了）
    if left.HookScript then
        left:HookScript("OnShow", function() RefreshCoreUI() end)
    end
    RefreshCoreUI()
    -- 试放按钮：不用真进战斗，点一下就能看特效
    -- 连续试放的计数：2 秒内连续点，第 2 次开始用组队槽位，第 5 次触发彩蛋
    local previewCount = 0
    local lastPreviewAt = 0
    local lastPreviewSoundAt = 0
    local eggShown = false

    previewBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    previewBtn:SetSize(150, 30)
    previewBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 30, 20)
    previewBtn:SetText("试放我的高光")
    previewBtn:SetScript("OnClick", function()
        local classToken = CurrentClass()
        local custom = GetCustomSpell()
        local label, official, previewID
        if custom then
            local customID = tonumber(custom)
            official = customID and FetchSpellName(customID) or custom
            label = official or custom
            previewID = customID
        else
            local list = SPELL_DATA[classToken]
            local info = list and list[1]
            label = info and info.label or "爆发"
            official = info and info.official
            previewID = info and info.id
        end
        -- 试放同样走核心技能改名的优先级
        local displayLabel = GetCoreDisplayLabel(official, label)

        -- 书本界面会挡住特效，先收起；整个序列结束后再恢复
        if AP_MainFrame then AP_MainFrame:Hide() end
        if AP_Aura and AP_Aura.Trigger then
            AP_Aura.Trigger(classToken, AP_DB.flavor and AP_DB.flavor.currentFaction, true)
        end

        -- 第 1 个：自己
        ShowHighlight(GetDisplayName(), displayLabel, classToken, "player", "EPIC",
            previewID and PORTRAIT_IMAGES[previewID], true)

        -- 依次模拟另外四名队友，音效互斥错开
        local order = GetRemoteSlotOrder()
        local function ShowTeammate(n, delay)
            After(delay, function()
                local idx = order[n - 1] or 5
                ShowRemoteHighlight("试放队友 " .. n, displayLabel, classToken, nil, idx)
                PlaySpotSound("EPIC", true)
            end)
        end
        ShowTeammate(2, 0.9)
        ShowTeammate(3, 1.8)
        ShowTeammate(4, 2.7)
        After(3.6, function()
            ShowRemoteHighlight("阿尔萨斯", "去死吧，父亲", "DEATHKNIGHT", nil, 5)
            PlaySpotSound("EPIC", true)
        end)
        After(6.5, function()
            if AP_MainFrame then AP_MainFrame:Show() end
        end)
    end)
    -- 放在左页最上层，避免被核心卡片/选择列表挡住点击
    previewBtn:SetFrameLevel(left:GetFrameLevel() + 30)

    -- 位置切换：右上 / 左上
    posBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    posBtn:SetSize(140, 28)
    posBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 192, 21)
    posBtn:SetFrameLevel(left:GetFrameLevel() + 30)
    posBtn:SetText(AP_DB.spotlight.position == "TOPLEFT" and "位置：左上" or "位置：右上")
    posBtn:SetScript("OnClick", function(self)
        AP_DB.spotlight.position = (AP_DB.spotlight.position == "TOPLEFT") and "TOPRIGHT" or "TOPLEFT"
        ApplyPosition()
        self:SetText(AP_DB.spotlight.position == "TOPLEFT" and "位置：左上" or "位置：右上")
    end)

    -- 两个按钮创建完成后再刷一次，决定未选核心技能时是否隐藏
    RefreshCoreUI()

    -- 右页：本职业的触发技能清单（只读）
    local rightTitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    rightTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -30)
    rightTitle:SetFont(rightTitle:GetFont(), 22, "")
    rightTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    rightTitle:SetText("核心技能与触发")

    local hint = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -10)
    hint:SetFont(hint:GetFont(), 13, "")
    hint:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
    hint:SetText("|cff6b5a45左页选定核心技能后，只会响应那一个技能|r")

    local listText = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listText:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -105)
    listText:SetWidth(340)
    listText:SetJustifyH("LEFT")
    listText:SetSpacing(7)
    listText:SetFont(listText:GetFont(), 16, "")

    -- 右页已经改成设置页，旧的三行清单不再显示（函数保留，避免其他引用报错）
    rightTitle:Hide()
    hint:Hide()
    listText:Hide()
    listText:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

    RefreshSkillList = function()
        -- 自定义大招优先：开了自定义就只显示这一条，避免玩家以为默认表也在生效
        local custom = GetCustomSpell()
        if custom then
            listText:SetText("|cff8c261a核心技能培养中|r\n\n只会响应这一个技能：\n|cff3a2414"
                .. custom .. "|r\n\n|cff6b5a45想换技能，请在左页点「×」重练。|r")
            return
        end

        local classToken = CurrentClass()
        local list = SPELL_DATA[classToken] or {}
        local lines, seen = {}, {}
        for _, info in ipairs(list) do
            if not seen[info.label] then
                seen[info.label] = true
                table.insert(lines, "|cff8c261a•|r " .. info.label
                    .. "  |cff6b5a45" .. (info.official or tostring(info.id)) .. "|r")
            end
        end
        if #lines == 0 then
            listText:SetText("|cff6b5a45当前职业还没有配置高光技能。|r")
        else
            listText:SetText(table.concat(lines, "\n"))
        end
    end
    RefreshSkillList()

    -- 职业切换后（比如小号），打开面板时刷新一次清单
    local refreshFrame = CreateFrame("Frame")
    SafeRegister(refreshFrame, "PLAYER_LOGIN")
    refreshFrame:SetScript("OnEvent", RefreshSkillList)
end

-- ==========================================
-- 9. 对外接口（方便调试和以后扩展）
-- ==========================================
-- 判断某个 spellID 是不是当前核心技能（给 Emotes 的正面形象让位逻辑用）
local function IsCoreSpell(spellID)
    if type(spellID) ~= "number" then return false end
    local official = GetCoreSpellName()
    if not official then return false end
    local customID = tonumber(official)
    if customID and customID == spellID then return true end
    local name = FetchSpellName(spellID)
    if not name then return false end
    return name == official or name:find(official, 1, true) ~= nil
end

AP_Spotlight = {
    Show = ShowHighlight,
    GetCoreLevel = GetCoreLevel,
    IsCoreSpell = IsCoreSpell,
    -- 调试用：/run AP_Spotlight.ShowRemote("名字", "技能", "DRUID")
    -- 连续执行 5 次可以检查 1~5 号槽位是否互不重叠
    ShowRemote = ShowRemoteHighlight,
    RefreshList = RefreshSkillList,
    RefreshCoreUI = RefreshCoreUI,
    -- 调试：/AP spotprof 200 -> 给当前核心技能加 200 点熟练度，方便验证 15/20/30 级解锁
    AddCoreProf = function(amount)
        EnsureDB()
        local official = GetCoreSpellName()
        if not official then
            print("|cffffd700[AP]|r 请先在「核心奥义」左页选择一个核心技能。")
            return
        end
        AP_DB.flavor = AP_DB.flavor or {}
        AP_DB.flavor.skillProf = AP_DB.flavor.skillProf or {}
        local current = AP_DB.flavor.skillProf[official] or 0
        local value = math.max(0, current + (tonumber(amount) or 10))
        AP_DB.flavor.skillProf[official] = value
        if RefreshCoreUI then RefreshCoreUI() end
        if AP_FlavorUI and AP_FlavorUI.RefreshSpellBook then
            local previewData = AP_FlavorManager and AP_FlavorManager.GetPreviewFactionData()
            if previewData then AP_FlavorUI.RefreshSpellBook(previewData) end
        end
        print("|cffffd700[AP]|r「" .. official .. "」熟练度：" .. value)
    end,
    -- /AP spotlog 会调用这个开关；只影响聊天框里的调试输出，不影响正常触发
    ToggleDebug = function()
        debugEnabled = not debugEnabled
        print("|cffffd700[AP]|r 高光调试日志：" .. (debugEnabled and "已开启" or "已关闭"))
    end,
}
