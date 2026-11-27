-- ==========================================
-- Emotes.lua: 表情与动作面板（点击图标 = 做一个表情 / 说一句话）
-- 打开方式：/ape   （也可以在 Core.lua 的 /AP 命令里加一行，见下方 AP_EmoteUI.Toggle）
-- ==========================================
AP_DB = AP_DB or {}
AP_DB.emote = AP_DB.emote or {}

-- 存档变量可能在插件文件加载完之后才注入，顶部这一次初始化会被整个覆盖，
-- 所以每次读写位置前都再确认一次（和 Network.lua 的 EnsureDB 同一个思路）。
local function EnsureEmoteDB()
    AP_DB = AP_DB or {}
    AP_DB.emote = AP_DB.emote or {}
    return AP_DB.emote
end

-- 去掉首尾空格。不依赖全局 strtrim，避免个别客户端没有这个函数。
local function TrimText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 提前声明：下面组装「最近常用」时要检查自定义槽里有没有写过 /表情
local GetCustomConfig

-- ---------- 可调参数 ----------
local COLUMNS = 5     -- 每行 5 个，10 个图标正好两行
local BTN_SIZE = 44   -- 图标大小
local BTN_GAP = 6     -- 图标间距
local PAD = 14        -- 面板内边距
local GLOBAL_CD = 1.5 -- 点一次后所有按钮冷却几秒，防止刷屏
local PANEL_TITLE = "表情动作"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- 末尾 5 个自定义槽：前 2 个用 /e 发自定义表情，后 3 个在说话频道发自定义内容
local CUSTOM_COUNT = 5
local RP_PREFIX = "【RP】" -- 所有「说出来」的话前面都会带上这个标记

-- ---------- 预设话术（「要说的话」里可选的内容，想加就往里添） ----------
local PHRASES = {
    "今天也是个适合冒险的好天气。",
    "有人见过我的坐骑吗？它又自己跑了。",
    "别担心，交给我吧。",
    "这一路走来，风景真不错。",
    "我们是不是在哪里见过？",
    "来一杯？我请客。",
    "愿圣光照亮你的道路。",
    "小心脚下，前面可能埋着伏兵。",
    "我的剑已经饥渴难耐了。",
    "要不要一起去酒馆坐坐？",
    "听说最近的悬赏很丰厚。",
    "别惹我，我今天心情不太好。",
    "愿风指引你的道路。",
    "今晚的酒馆，我请。",
    "这附近有什么值得一听的传闻吗？",
    "我的行囊里还留着半块面包。",
    "你看起来需要一位同伴。",
    "荒野在呼唤，我该出发了。",
    "别把后背交给陌生人——除非那个人是我。",
    "月升之时，我通常不在城里。",
    "记住今天的风，它明天就不会一样了。",
    "如果你听见狼嚎，别回头。",
    "故事讲到这里，剩下的要用脚去走。",
    "有事就来营地找我。",
}

-- 玩家种族图标：用各职业都能认出来的种族天赋图标，避免 RaceIcon_* 缺失时变黑块
local RACE_ICONS = {
    Human = "Interface\\Icons\\Ability_Racial_Perception",
    Orc = "Interface\\Icons\\Ability_Racial_BloodFury",
    Dwarf = "Interface\\Icons\\Ability_Racial_Stoneform",
    NightElf = "Interface\\Icons\\Ability_Racial_Shadowmeld",
    Undead = "Interface\\Icons\\Ability_Racial_WilloftheForsaken",
    Scourge = "Interface\\Icons\\Ability_Racial_WilloftheForsaken",
    Tauren = "Interface\\Icons\\Ability_Racial_Warstomp",
    Gnome = "Interface\\Icons\\Ability_Racial_EscapeArtist",
    Troll = "Interface\\Icons\\Ability_Racial_Berserking",
    BloodElf = "Interface\\Icons\\Ability_Racial_ArcaneTorrent",
    Draenei = "Interface\\Icons\\Ability_Racial_GiftOfTheNaaru",
}
local function GetPlayerRaceIcon()
    if type(UnitRace) ~= "function" then return FALLBACK_ICON end
    local okRace, _, raceToken = pcall(UnitRace, "player")
    if not okRace or type(raceToken) ~= "string" or raceToken == "" then
        return FALLBACK_ICON
    end
    local key = raceToken:gsub("%s+", "")
    return RACE_ICONS[key] or FALLBACK_ICON
end

-- ---------- 基础动作列表（固定 5 个） ----------
-- emote = "TOKEN"        -> 调用游戏内置表情（等同于输入 /joke /dance 等）
-- lines = { ... }        -> 说话用的句子；pick = true 时弹出列表让玩家自己挑
-- recent = true          -> 弹出「最近常用」表情列表
-- icon 都是 Interface\Icons 下的图标，哪个显示成绿块/问号就换一个名字
local EMOTES = {
    {
        name = "要说的话",
        desc = "点开话术列表，挑一句在说话频道说出来。",
        lines = PHRASES,
        pick = true, -- 关键：不随机说，而是先弹出「一览」让玩家自己挑
        icon = "Interface\\Icons\\INV_Misc_Note_01"
    },
    {
        name = "最近常用",
        desc = "从最近用过的 10 个表情里挑一个。",
        recent = true,
        icon = "Interface\\Icons\\INV_Misc_Book_09"
    },
    {
        name = "打招呼",
        desc = "向周围的人打个招呼。",
        emote = "HELLO",
        icon = GetPlayerRaceIcon()
    },
    {
        name = "再见",
        desc = "挥手告别。",
        emote = "BYE",
        icon = "Interface\\Icons\\Spell_Nature_AstralRecal"
    },
    {
        name = "魔法耗尽",
        desc = "表示你的魔法值耗尽了。",
        emote = "OOM",
        icon = "Interface\\Icons\\Spell_Shadow_ManaBurn"
    },
}

-- 5 个自定义槽的默认图标：前 2 个是 /e 表情，后 3 个是说话
local CUSTOM_ICONS = {
    "Interface\\Icons\\INV_Misc_Drum_01",             -- 自定义表情 1（跳舞感）
    "Interface\\Icons\\Ability_Warrior_RallyingCry",  -- 自定义表情 2（欢呼感）
    "Interface\\Icons\\INV_Misc_Note_04",
    "Interface\\Icons\\INV_Misc_Note_05",
    "Interface\\Icons\\INV_Misc_Note_06",
}

-- 其他图标按钮已经占用的表情：最近常用里不再重复出现
local RESERVED_EMOTES = {}
for _, entry in ipairs(EMOTES) do
    if entry.emote then RESERVED_EMOTES[entry.emote] = true end
end

-- 判断某个表情是否已被固定按钮或自定义槽（写成 /dance 这种）占用
local function IsReservedEmote(token)
    if not token or token == "" then return false end
    if RESERVED_EMOTES[token] then return true end
    for i = 1, CUSTOM_COUNT do
        local text = GetCustomConfig(i).text
        if text and text:sub(1, 1) == "/" then
            local cmd = text:match("^/(%S+)")
            if cmd and cmd:upper() == token then return true end
        end
    end
    return false
end

-- 最近常用表情：没历史记录时用这份默认名单补齐 10 个（不含固定按钮上的三个）
local RECENT_DEFAULT = {
    { token = "JOKE",   text = "讲笑话" },
    { token = "LAUGH",  text = "大笑" },
    { token = "DANCE",  text = "跳舞" },
    { token = "CHEER",  text = "欢呼" },
    { token = "FLEX",   text = "秀肌肉" },
    { token = "ROAR",   text = "咆哮" },
    { token = "TRAIN",  text = "火车" },
    { token = "BOW",    text = "鞠躬" },
    { token = "SALUTE", text = "敬礼" },
    { token = "THANK",  text = "感谢" },
    { token = "KISS",   text = "飞吻" },
    { token = "CRY",    text = "哭泣" },
    { token = "FLIRT",  text = "调情" },
    { token = "PITY",   text = "同情" },
}

local EMOTE_NAMES = {}
for _, item in ipairs(RECENT_DEFAULT) do
    EMOTE_NAMES[item.token] = item.text
end
EMOTE_NAMES["HELLO"] = "打招呼"
EMOTE_NAMES["BYE"] = "再见"
EMOTE_NAMES["OOM"] = "魔法耗尽"

-- 手动在聊天框输入 /sleep 这类表情时的中文名，用来补进「最近常用」
local EXTRA_EMOTE_NAMES = {
    SLEEP = "睡觉", SIT = "坐下", STAND = "站起", WAVE = "挥手", HI = "嗨",
    GREET = "问候", SMILE = "微笑", SHY = "害羞", TIRED = "疲惫", YAWN = "打哈欠",
    SIGH = "叹气", LOL = "大笑", GRIN = "咧嘴笑", ROFL = "笑翻", SILLY = "傻笑",
    BOW = "鞠躬", SALUTE = "敬礼", THANK = "感谢", KISS = "飞吻", CRY = "哭泣",
    FLIRT = "调情", PITY = "同情", MOON = "月亮", POINT = "指", TALK = "交谈",
    CHICKEN = "小鸡", RUDE = "粗鲁", SPIT = "吐口水", CONGRATULATE = "祝贺",
    HUG = "拥抱", WELCOME = "欢迎", FAREWELL = "告别", NO = "不", YES = "是",
    WAIT = "等待", BECKON = "招手", CALM = "冷静", INSULT = "辱骂", MERCY = "求饶",
    SHOO = "驱赶", SLAP = "耳光", STARE = "凝视", THREATEN = "威胁", VETO = "否决",
    VIOLIN = "拉小提琴", BOAST = "吹嘘", BORED = "无聊", COMFORT = "安慰",
    CONFUSED = "困惑", COUGH = "咳嗽", CURTSEY = "屈膝礼", DROOL = "流口水",
    FLEE = "逃跑", GLOAT = "幸灾乐祸", GROAN = "呻吟", GROVEL = "卑躬屈膝",
    HUNGRY = "饥饿", MOAN = "哀叹", MOURN = "哀悼", PLEAD = "恳求", SHOUT = "喊叫",
    SHRUG = "耸肩", SMACK = "咂嘴", SURPRISED = "惊讶", TAP = "轻敲", TEASE = "逗弄",
    TOAST = "干杯", THIRSTY = "口渴", VICTORY = "胜利", APOLOGIZE = "道歉",
    EXCUSE = "借口", OFFER = "提供", ROAR = "咆哮", TRAIN = "火车", FLEX = "秀肌肉",
    DANCE = "跳舞", CHEER = "欢呼", JOKE = "讲笑话", LAUGH = "大笑",
}
for token, name in pairs(EXTRA_EMOTE_NAMES) do
    if not EMOTE_NAMES[token] then EMOTE_NAMES[token] = name end
end

-- 记一次表情使用：把 token 提到最前面，最多留 10 个；固定按钮上的表情不记
local function RecordEmote(token)
    if not token or token == "" or IsReservedEmote(token) then return end
    local db = EnsureEmoteDB()
    db.recentEmotes = db.recentEmotes or {}
    for i = #db.recentEmotes, 1, -1 do
        if db.recentEmotes[i] == token then
            table.remove(db.recentEmotes, i)
        end
    end
    table.insert(db.recentEmotes, 1, token)
    while #db.recentEmotes > 10 do
        table.remove(db.recentEmotes)
    end
end

-- 组装「最近常用」列表：排除其他按钮已定义的表情，最多 10 个
local function GetRecentItems()
    local items, seen = {}, {}
    local db = EnsureEmoteDB()
    local recent = db.recentEmotes or {}

    local function Add(token)
        if #items >= 10 then return end
        if not token or token == "" or IsReservedEmote(token) or seen[token] then return end
        seen[token] = true
        items[#items + 1] = { text = EMOTE_NAMES[token] or token, token = token }
    end

    for _, token in ipairs(recent) do Add(token) end
    for _, item in ipairs(RECENT_DEFAULT) do Add(item.token) end
    return items
end

-- ---------- 卡片配色主题（经典 / 烈焰 / 月光 / 森林 / 幽暗 / 任务） ----------
-- border       = 标题、名牌、话术列表、按钮悬停的强调色
-- frameBorder  = 表情面板和属性条外框的边框色
-- panelBg      = 标题牌/名牌的背景色
-- accent       = 标题文字、RP 名、属性数值的颜色
-- buttonBorder = 图标按钮平时的边框色
local THEMES = {
    classic = {
        name = "经典",
        border = { 0.90, 0.72, 0.28 }, frameBorder = { 0.50, 0.50, 0.55 },
        panelBg = { 0.14, 0.11, 0.04 }, accent = { 1.00, 0.85, 0.30 },
        buttonBorder = { 0.40, 0.40, 0.45 },
    },
    flame = {
        name = "烈焰",
        border = { 0.92, 0.40, 0.14 }, frameBorder = { 0.55, 0.25, 0.16 },
        panelBg = { 0.18, 0.06, 0.02 }, accent = { 1.00, 0.58, 0.20 },
        buttonBorder = { 0.42, 0.20, 0.15 },
    },
    moonlight = {
        name = "月光",
        border = { 0.66, 0.80, 0.98 }, frameBorder = { 0.40, 0.52, 0.68 },
        panelBg = { 0.06, 0.09, 0.15 }, accent = { 0.82, 0.90, 1.00 },
        buttonBorder = { 0.30, 0.38, 0.50 },
    },
    forest = {
        name = "森林",
        border = { 0.42, 0.78, 0.38 }, frameBorder = { 0.30, 0.52, 0.28 },
        panelBg = { 0.05, 0.12, 0.05 }, accent = { 0.68, 0.96, 0.52 },
        buttonBorder = { 0.24, 0.38, 0.24 },
    },
    shadow = {
        name = "幽暗",
        border = { 0.62, 0.42, 0.88 }, frameBorder = { 0.42, 0.30, 0.62 },
        panelBg = { 0.09, 0.05, 0.14 }, accent = { 0.82, 0.62, 1.00 },
        buttonBorder = { 0.32, 0.24, 0.44 },
    },
    quest = {
        name = "任务",
        -- 原版任务面板的羊皮纸色，整体调亮一档；文字用深棕色保证对比
        border = { 0.55, 0.40, 0.20 }, frameBorder = { 0.45, 0.32, 0.16 },
        panelBg = { 0.95, 0.87, 0.69 }, accent = { 0.30, 0.20, 0.08 },
        buttonBorder = { 0.52, 0.40, 0.22 },
        bodyBg = { 0.89, 0.79, 0.60, 0.98 },
        buttonBg = { 0.30, 0.22, 0.12, 0.85 },
        muted = { 0.44, 0.34, 0.22 },
        pickerBg = { 0.92, 0.83, 0.65, 0.99 },
        pickerRowBg = { 0.97, 0.90, 0.73, 0.92 },
        pickerText = { 0.28, 0.19, 0.09 },
        light = true,
    },
}
local THEME_ORDER = { "classic", "flame", "moonlight", "forest", "shadow", "quest" }
local currentTheme = THEMES.classic

-- 读取（必要时先建立）第 i 个自定义槽的存档。
-- 存档长这样：AP_DB.emote.custom[1] = { name = "打个招呼", text = "你好呀。" }
function GetCustomConfig(i)
    local db = EnsureEmoteDB()
    db.custom = db.custom or {}
    db.custom[i] = db.custom[i] or {}
    return db.custom[i]
end

-- 把「固定 5 个 + 自定义 5 个」拼成当前要显示的完整列表。
-- 每次调用都重新读存档，所以设定页里一保存，按钮提示就会立刻更新。
local function GetEntries()
    local list = {}
    for i = 1, #EMOTES do
        list[i] = EMOTES[i]
    end

    for i = 1, CUSTOM_COUNT do
        local cfg = GetCustomConfig(i)
        local isEmoteSlot = i <= 2
        -- 名称固定，不再读取旧存档里的自定义名称，避免旧名字残留在提示里
        local name = isEmoteSlot and ("自定义表情 " .. i) or ("自定义说话 " .. (i - 2))

        local desc
        if cfg.text and cfg.text ~= "" then
            if cfg.text:sub(1, 1) == "/" then
                desc = "执行：" .. cfg.text
            elseif isEmoteSlot then
                desc = "表情：" .. cfg.text
            else
                desc = "说：" .. cfg.text
            end
        else
            desc = "还没有设置内容，请到「设定 → 表情动作」里填写。"
        end

        list[#list + 1] = {
            name = name,
            desc = desc,
            text = cfg.text,
            customSlot = i, -- 记下这是第几个自定义槽，点击时用来判断有没有填内容
            customIsEmote = isEmoteSlot,
            icon = CUSTOM_ICONS[i] or FALLBACK_ICON,
        }
    end
    return list
end

-- ==========================================
-- 逻辑
-- ==========================================
local lastUse = 0

local function FriendlyTargetUnit()
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsEnemy("player", "target") then
        return "target"
    end
    return nil
end

-- 自定义按钮的内容如果以 / 开头，就当作表情执行。
-- 例：/moon -> DoEmote("MOON")；/dance -> DoEmote("DANCE")。
-- 注意：不能用 RunMacroText，它在 WoW 里是受保护函数，插件调用必定失败。
-- DoEmote 不同客户端的返回值不一致（有的成功也返回 false），所以只看有没有报错。
local function RunSlashText(text)
    local cmd = text:match("^/(%S+)")
    local token = cmd and cmd:upper()
    if not token then return end

    local ok = pcall(DoEmote, token, FriendlyTargetUnit())
    if not ok then
        -- 某些客户端不接受显式的 nil 目标，再试一次单参数调用
        ok = pcall(DoEmote, token)
    end
    if ok then return end

    print("|cffffd700[AP]|r 无法执行：" .. text ..
        "。自定义栏只支持 /表情 类命令，例如 /moon、/dance。")
end

local function Perform(entry)
    if entry.emote then
        -- 有友方玩家目标时，表情会带上目标（比如对着某人飞吻）
        pcall(DoEmote, entry.emote, FriendlyTargetUnit())
        RecordEmote(entry.emote)
    elseif entry.text and entry.text ~= "" then
        if entry.text:sub(1, 1) == "/" then
            -- 以 / 开头：仍然当作表情命令执行
            RunSlashText(entry.text)
        elseif entry.customIsEmote then
            -- 自定义表情槽：等同于 /e 文本
            SendChatMessage(entry.text, "EMOTE")
        else
            -- 自定义说话槽：在说话频道带 RP 前缀
            SendChatMessage(RP_PREFIX .. entry.text, "SAY")
        end
    elseif entry.lines and #entry.lines > 0 then
        -- 兜底：随机挑一句，并且不和上一句重复（「要说的话」实际走的是选择列表）
        local n = #entry.lines
        local i = math.random(n)
        if n > 1 and i == entry.lastIndex then i = (i % n) + 1 end
        entry.lastIndex = i
        local channel = entry.channel or "SAY"
        local text = entry.lines[i]
        if channel == "SAY" then text = RP_PREFIX .. text end
        SendChatMessage(text, channel)
    end
end

-- ==========================================
-- 界面
-- ==========================================
local UI = {}
AP_EmoteUI = UI

local rows = math.ceil((#EMOTES + CUSTOM_COUNT) / COLUMNS) -- 总格数 = 固定 5 + 自定义 5
local gridW = COLUMNS * BTN_SIZE + (COLUMNS - 1) * BTN_GAP
local gridH = rows * BTN_SIZE + (rows - 1) * BTN_GAP
local TITLE_AREA = 34

local FRAME_W = gridW + PAD * 2
local FRAME_H = gridH + PAD * 2 + TITLE_AREA - 8

-- 外层卡片：只负责整体移动、位置存档和统一显隐。
-- 表情面板、名牌、属性条都挂在它下面。
-- 这样右上角 × 只会隐藏「表情面板」本身，上面的名牌和属性条会继续留在屏幕上。
local card = CreateFrame("Frame", "AP_EmoteCard", UIParent)
card:SetSize(FRAME_W, FRAME_H)
-- MEDIUM：让暴雪自带的窗口（任务/地图/人物属性/专业等，通常在 HIGH/DIALOG）
-- 盖在表情动作卡片之上，不再遮住这些窗口的底部。
card:SetFrameStrata("MEDIUM")
card:SetClampedToScreen(true)
card:SetMovable(true)
card:Hide()
UI.card = card

-- 真正的表情图标面板：铺满卡片，× 按钮关掉的就是它
local frame = CreateFrame("Frame", "AP_EmoteFrame", card, "BackdropTemplate")
frame:SetAllPoints(card)
-- 跟随卡片，保持在暴雪窗口下方
frame:SetFrameStrata("MEDIUM")
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0.07, 0.07, 0.08, 0.96)
frame:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
UI.frame = frame

-- 位置：读取上次保存的，没有就放在屏幕中间偏右（记录的是外层卡片的位置）
local function RestorePosition()
    card:ClearAllPoints()
    local pos = EnsureEmoteDB().pos
    if pos and pos[1] then
        card:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        card:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
end
RestorePosition()
UI.RestorePosition = RestorePosition

-- 存档可能在文件执行完之后才注入，启动时读到的位置可能是空的；
-- 登录完成后再恢复一次，避免每次都回到默认位置。
local positionLogin = CreateFrame("Frame")
positionLogin:RegisterEvent("PLAYER_LOGIN")
positionLogin:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    RestorePosition()
end)

-- 移动方式：必须按住 Shift 再拖动，避免平时点来点去把面板拖跑。
-- 名牌、属性条、标题牌也会被加进同一套拖动逻辑（见下面 MakeDragHandle）。
local function StopAndSavePosition()
    card:StopMovingOrSizing()
    local point, _, relPoint, x, y = card:GetPoint()
    EnsureEmoteDB().pos = { point, relPoint, x, y }
end

local function StartShiftMove()
    if IsShiftKeyDown() then
        card:StartMoving()
    end
end

-- 把一个区域变成拖动把手：按住 Shift 在它上面拖，就能移动整个面板
local function MakeDragHandle(handle)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", StartShiftMove)
    handle:SetScript("OnDragStop", StopAndSavePosition)
end

frame:SetScript("OnDragStart", StartShiftMove)
frame:SetScript("OnDragStop", StopAndSavePosition)

-- 顶部标题牌（压在上边框上，和截图里一样）
local title = CreateFrame("Frame", nil, frame, "BackdropTemplate")
title:SetSize(gridW + PAD * 2 - 36, 30)
title:SetPoint("TOP", frame, "TOP", 0, 12)
title:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
title:SetBackdropColor(0.14, 0.11, 0.04, 1)
title:SetBackdropBorderColor(0.9, 0.72, 0.28, 1)
local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("CENTER", 0, 0)
titleText:SetText(PANEL_TITLE)
-- 和名字一样的柔化处理：无硬描边 + 投影
titleText:SetFont(titleText:GetFont(), 19, "")
titleText:SetShadowColor(0, 0, 0, 0.9)
titleText:SetShadowOffset(1, -1)
titleText:SetTextColor(1, 0.85, 0.3)
MakeDragHandle(title)

-- ==========================================
-- 顶部名牌：RP 名 + 当前职业流派
-- 第一行是「职业流派」里设置的名字（如：珀耳塞福涅·黑檀），
-- 第二行是当前流派名（如：<夜爪德鲁伊>），并染上该流派的主题色。
-- ==========================================
-- 名牌挂在 card 上（而不是 frame 上）：点 × 关掉表情面板时，它会继续显示
local nameplate = CreateFrame("Frame", nil, card, "BackdropTemplate")
nameplate:SetSize(FRAME_W, 88) -- 比原来高一点，给姓名下方的小图标留一行
-- 向上抬高：先给下面的属性条留出位置（属性条高 50 + 间隔 6）
nameplate:SetPoint("BOTTOM", card, "TOP", 0, 78)
nameplate:SetClampedToScreen(true)
nameplate:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
nameplate:SetBackdropColor(0.1, 0.08, 0.03, 0.95)
nameplate:SetBackdropBorderColor(0.9, 0.72, 0.28, 1)
MakeDragHandle(nameplate)

local plateName = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
plateName:SetPoint("TOP", nameplate, "TOP", 0, -9)
plateName:SetWidth(FRAME_W - 16)
plateName:SetJustifyH("CENTER")
-- 名字不用硬描边：放大一点 + 投影，视觉上更粗、更柔和（略带糊感）
plateName:SetFont(plateName:GetFont(), 22, "")
plateName:SetShadowColor(0, 0, 0, 0.9)
plateName:SetShadowOffset(1, -1)
plateName:SetTextColor(1, 0.85, 0.3)

local plateFaction = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
plateFaction:SetPoint("TOP", plateName, "BOTTOM", 0, -1)
plateFaction:SetWidth(FRAME_W - 16)
plateFaction:SetJustifyH("CENTER")
plateFaction:SetFont(plateFaction:GetFont(), 15, "")

-- 第一个小图标（核心奥义）在下面才创建；这里先声明，供名牌刷新时同步流派图标
local coreIcon

-- 从职业流派模块（Data.lua / Flavor.lua）读取当前角色的数据。
-- 注意：Emotes.lua 比 Data.lua 先加载，所以这里只能等到「打开面板时」再读，
-- 不能在文件加载阶段就访问 AP_FlavorData。
local function UpdateNameplate()
    local flavor = (AP_DB and AP_DB.flavor) or {}

    -- 第一行：RP 名。没设过就退回游戏角色名
    local rpName = flavor.customName
    if not rpName or rpName == "" then
        rpName = UnitName("player") or "冒险者"
    end

    -- 第二行：当前职业流派名 + 颜色；同时记下流派图标
    local factionName, color, factionIcon
    local classData = AP_FlavorData and AP_FlavorData[flavor.currentClass]
    if classData then
        for _, f in ipairs(classData.factions or {}) do
            if f.id == flavor.currentFaction then
                factionName = f.name
                color = f.themeColor or f.color
                factionIcon = f.icon
                break
            end
        end
        -- 存档里的流派对不上时，退回本职业的第一个流派
        if not factionName then
            local first = (classData.factions or {})[1]
            if first then
                factionName = first.name
                color = first.themeColor or first.color
                factionIcon = first.icon
            end
        end
        color = color or classData.classColor
        factionName = factionName or classData.className
    end

    if not factionName then factionName = "冒险者" end
    if not color then color = { r = 1, g = 0.85, b = 0.3 } end

    -- 浅色主题（任务羊皮纸）下把流派颜色压暗一点，保证在亮背景上看得清
    if currentTheme.light then
        color = { r = color.r * 0.55, g = color.g * 0.55, b = color.b * 0.55 }
    end

    -- 第一个小图标用当前流派图标，和职业流派页保持一致
    if coreIcon and coreIcon.texture then
        coreIcon.texture:SetTexture(factionIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    plateName:SetText(rpName)
    plateFaction:SetText("<" .. factionName .. ">")
    plateFaction:SetTextColor(color.r, color.g, color.b)
end

-- 每次面板显示时都刷新一遍：在职业流派页改名或转投后，下次打开就是新的
frame:HookScript("OnShow", UpdateNameplate)

-- ==========================================
-- 卡片正上方的浮动提示（声望 / 熟练度提升）
-- 位置固定在名牌顶部上方约两行处。
-- ==========================================
local NOTIFY_W = 420
local notifyFrame = CreateFrame("Frame", nil, card)
notifyFrame:SetSize(NOTIFY_W, 24)
notifyFrame:SetPoint("BOTTOM", nameplate, "TOP", 0, 34)

local notifyText = notifyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
notifyText:SetPoint("CENTER")
notifyText:SetWidth(NOTIFY_W)
notifyText:SetJustifyH("CENTER")
notifyText:SetFont(notifyText:GetFont(), 16, "")
notifyText:SetShadowColor(0, 0, 0, 0.9)
notifyText:SetShadowOffset(1, -1)
notifyText:SetAlpha(0)

local notifyToken = 0
local NOTIFY_FONT_SIZE = 16
local NOTIFY_DURATION = 3.5

-- fontSize / duration 可选：默认用 16 号、3.5 秒；
-- 熟练度提示会传更大的字号和更长的停留时间。
function UI.Notify(text, r, g, b, fontSize, duration)
    if not text or text == "" then return end

    -- 卡片没显示时退回屏幕中央提示，避免消息丢失
    if not card:IsShown() then
        UIErrorsFrame:AddMessage(text, r or 1, g or 1, b or 1, 1)
        return
    end

    notifyToken = notifyToken + 1
    local token = notifyToken
    notifyText:SetFont(notifyText:GetFont(), fontSize or NOTIFY_FONT_SIZE, "")
    notifyText:SetText(text)
    notifyText:SetTextColor(r or 1, g or 1, b or 1)
    notifyText:SetAlpha(1)

    -- 默认 3.5 秒后淡出；期间来了新消息就以新消息为准
    if C_Timer and C_Timer.After then
        C_Timer.After(duration or NOTIFY_DURATION, function()
            if notifyToken == token then notifyText:SetAlpha(0) end
        end)
    end
end

-- ==========================================
-- 正面形象：屏幕左下方的 3D 实时模型（可 Shift 拖动）
-- 注意：PlayerModel 的镜头会随窗口高度一起放大，单纯加高只会把脸放得更大、
-- 并不会显示更多身体，所以这里用屏幕内放得下的高度，改为把镜头拉远。
-- ==========================================
local MODEL_W = 720 -- 宽度再放大 0.5 倍（480 → 720）
local MODEL_H = 660 -- 再高一点，方便 Shift 拖到合适位置
local modelFrame = CreateFrame("Frame", nil, card, "BackdropTemplate")
modelFrame:SetSize(MODEL_W, MODEL_H)
-- 同样用 MEDIUM：暴雪窗口（HIGH/DIALOG）会压住模型，模型本身点击穿透。
modelFrame:SetFrameStrata("MEDIUM")
-- 在 MEDIUM 内部用很高的 FrameLevel：
-- 这样能盖住聊天框、动作条等普通 UI，又不越过暴雪窗口所在的 HIGH/DIALOG。
modelFrame:SetFrameLevel(5000)
-- 不要背景：只显示人物，空白区域透明，不会再有黑框/空白问题
modelFrame:Hide()

-- 模型窗口位置存档：Shift 拖动后保存，重载/重新登录后恢复
local function SaveModelPosition()
    local point, relativeTo, relPoint, x, y = modelFrame:GetPoint()
    if not point then return end
    -- relativeTo 为 nil 时表示相对父级（卡片）
    local relName = "UIParent"
    if relativeTo == card or relativeTo == nil then relName = "card" end
    EnsureEmoteDB().modelPos = { point, relName, relPoint, x, y }
end

local function RestoreModelPosition()
    local db = EnsureEmoteDB()

    -- 一次性作废旧版自由位置，改用新的“屏幕左下角 + 约 3cm”默认位置
    if db.modelPosVersion ~= 1 then
        db.modelPos = nil
        db.modelPosVersion = 1
    end

    local pos = db.modelPos
    modelFrame:ClearAllPoints()
    if pos and pos[1] then
        local anchor = (pos[2] == "card") and card or UIParent
        modelFrame:SetPoint(pos[1], anchor, pos[3], pos[4], pos[5])
    else
        -- 贴图底边紧贴屏幕底部，左侧向右留约 3 厘米。
        -- 按屏幕宽度的 1/16 估算 3cm（常见 16:9 显示器宽度约 48cm），
        -- 这样不同分辨率下都接近 3 厘米，而不是写死像素。
        local edgeGap = (UIParent:GetWidth() or 1920) / 16
        modelFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", edgeGap, 0)
    end
end
UI.RestoreModelPosition = RestoreModelPosition
RestoreModelPosition()

-- 只有顶部一条拖动条响应鼠标，窗口其余部分完全不挡点击，
-- 避免战斗中大窗口遮住动作条导致“插件行为导致错误”。
modelFrame:SetMovable(true)
local modelDragBar = CreateFrame("Frame", nil, modelFrame, "BackdropTemplate")
modelDragBar:SetPoint("TOPLEFT", modelFrame, "TOPLEFT", 4, -4)
modelDragBar:SetPoint("TOPRIGHT", modelFrame, "TOPRIGHT", -4, -4)
modelDragBar:SetHeight(18)
modelDragBar:EnableMouse(true)
modelDragBar:RegisterForDrag("LeftButton")
modelDragBar:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then modelFrame:StartMoving() end
end)
modelDragBar:SetScript("OnDragStop", function()
    modelFrame:StopMovingOrSizing()
    SaveModelPosition()
end)

local dragHint = modelDragBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dragHint:SetPoint("CENTER")
dragHint:SetFont(dragHint:GetFont(), 11, "")
dragHint:SetTextColor(0.8, 0.8, 0.8)
dragHint:SetShadowColor(0, 0, 0, 0.9)
dragHint:SetShadowOffset(1, -1)
dragHint:SetText("Shift + 拖动这里")

-- 提示条要盖在模型窗口上方，避免被高窗口挡住
notifyFrame:SetFrameLevel(modelFrame:GetFrameLevel() + 5)

local playerModel = CreateFrame("PlayerModel", "AP_FrontModel", modelFrame)
playerModel:SetPoint("TOPLEFT", 6, -6)
playerModel:SetPoint("BOTTOMRIGHT", -6, 6)
playerModel:SetFrameLevel(modelFrame:GetFrameLevel() + 1)
playerModel:EnableMouse(false)

-- 错愕表演：不依赖某个具体表情动画是否存在。
-- 模型左右甩头 + 轻微弹跳 + 头顶「？！」大字，动画没命中时也能看出“被吓到”。
local shockText = modelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
shockText:SetPoint("TOP", modelFrame, "TOP", 0, 46)
shockText:SetFont(shockText:GetFont(), 44, "OUTLINE")
shockText:SetTextColor(1, 0.15, 0.1)
shockText:SetText("？！")
shockText:Hide()

local shockTicker = CreateFrame("Frame")
shockTicker:Hide()
local shockElapsed = 0
local SHOCK_DURATION = 0.7
shockTicker:SetScript("OnUpdate", function(self, elapsed)
    shockElapsed = shockElapsed + elapsed
    if shockElapsed >= SHOCK_DURATION then
        pcall(playerModel.SetRotation, playerModel, 0)
        modelFrame:SetScale(1)
        shockText:Hide()
        self:Hide()
        return
    end
    -- 频率较高的左右摆动，配合一点缩放，看起来像被吓了一跳
    local rotation = math.sin(shockElapsed * 50) * 14
    pcall(playerModel.SetRotation, playerModel, rotation)
    modelFrame:SetScale(1 + 0.05 * math.abs(math.sin(shockElapsed * 22)))
end)

local function ResetShock()
    shockTicker:Hide()
    shockText:Hide()
    pcall(playerModel.SetRotation, playerModel, 0)
    modelFrame:SetScale(1)
end

local function PlayShock()
    shockElapsed = 0
    shockText:Show()
    shockTicker:Show()
end

-- 施法动作 ID 各客户端不完全一样：按优先级找一个模型确实拥有的
local castAnimID
local CAST_ANIM_CANDIDATES = { 53, 54, 32, 31, 11 }
local modelCasting = false

-- 被动进战时的“哎呀”动作候选：12 = Cry（掩面哭泣），13 = Emote。
-- 不同客户端模型拥有的动画不一样，FindPassiveAnim 会挑第一个存在的。
local passiveAnimID
local PASSIVE_ANIM_CANDIDATES = { 12, 13, 101, 102, 103 }
local modelPassive = false

local function FindCastAnim()
    castAnimID = nil
    if not playerModel.HasAnimation then return end
    for _, id in ipairs(CAST_ANIM_CANDIDATES) do
        local ok, has = pcall(playerModel.HasAnimation, playerModel, id)
        if ok and has then
            castAnimID = id
            return
        end
    end
end

-- 找一个“挨打/哎呀”的表情动作；候选都不存在时返回 nil，模型仍然会显示。
local function FindPassiveAnim()
    passiveAnimID = nil
    if not playerModel.HasAnimation then return end
    for _, id in ipairs(PASSIVE_ANIM_CANDIDATES) do
        local ok, has = pcall(playerModel.HasAnimation, playerModel, id)
        if ok and has then
            passiveAnimID = id
            return
        end
    end
end

-- 判断玩家现在是不是“人形态”。
-- 德鲁伊变形、萨满幽魂之狼这类非人形态如果继续用 PlayerModel 复制，
-- 会把猫 / 熊 / 狼的巨大模型直接塞进窗口，所以这些形态一律不显示立绘。
local function IsHumanForm()
    -- 大部分形态职业（德鲁伊、萨满、狼人）用形态索引判断：0 = 人形
    local okForm, form = pcall(GetShapeshiftForm)
    if okForm and type(form) == "number" and form > 0 then
        return false
    end

    -- 部分客户端的幽魂之狼 / 变形走光环，不占用形态索引。
    -- 新版用 spellID 查光环，旧版退回按中文名查 buff。
    if type(C_UnitAuras) == "table" and C_UnitAuras.GetPlayerAuraBySpellID then
        local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 2645) -- 幽魂之狼
        if okAura and aura then return false end
    elseif type(UnitBuff) == "function" then
        local okAura, name = pcall(UnitBuff, "player", "幽魂之狼")
        if okAura and name then return false end
    end

    return true
end

-- 施法动作播完一次后自动重播，避免停在最后一个姿势上“傻站”
playerModel:SetScript("OnAnimFinished", function(self)
    if not modelFrame:IsShown() then return end
    if modelCasting and castAnimID then
        pcall(self.SetAnimation, self, castAnimID)
    elseif modelPassive and passiveAnimID then
        -- 被动形象也循环播放，别停在最后一个姿势
        pcall(self.SetAnimation, self, passiveAnimID)
    end
end)

local function RefreshModelUnit()
    pcall(playerModel.SetUnit, playerModel, "player")
    pcall(playerModel.SetRotation, playerModel, 0) -- 0 = 正面朝向镜头

    -- 脸部 + 上半身（1 = 脸部特写，数值越小视野越宽）
    -- 0.72：人物再放大一点
    local okZoom = pcall(playerModel.SetPortraitZoom, playerModel, 0.72)
    if not okZoom then
        -- 老客户端没有 SetPortraitZoom 时退回脸部镜头
        pcall(playerModel.SetCamera, playerModel, 0)
    end

    -- 先回到站立，等真正展示时再切施法动作
    pcall(playerModel.SetAnimation, playerModel, 0)
    FindCastAnim()
    FindPassiveAnim()
end

-- 模型已经独立到屏幕顶部，提示条固定回到名牌上方
local function UpdateNotifyAnchor()
    notifyFrame:ClearAllPoints()
    notifyFrame:SetPoint("BOTTOM", nameplate, "TOP", 0, 34)
end

local modelHideToken = 0

function UI.RefreshModel()
    -- 不再常驻显示：只有施法时临时出现；关闭开关时立刻收起
    if not EnsureEmoteDB().showModel then
        modelHideToken = modelHideToken + 1
        modelCasting = false
        modelPassive = false
        modelFrame:Hide()
        UpdateNotifyAnchor()
    end
end

-- 卡片收起时，模型也一起收起
card:HookScript("OnHide", function()
    modelHideToken = modelHideToken + 1
    modelCasting = false
    modelPassive = false
    ResetShock()
    modelFrame:Hide()
end)

-- 换装备 / 变形后刷新模型
local modelEventFrame = CreateFrame("Frame")
modelEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
if modelEventFrame.RegisterUnitEvent then
    modelEventFrame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
else
    modelEventFrame:RegisterEvent("UNIT_MODEL_CHANGED")
end
modelEventFrame:SetScript("OnEvent", function()
    if not modelFrame:IsShown() then return end
    -- 换装备时在非人形态，直接收起，不要刷新成猫/熊/狼的模型
    if not IsHumanForm() then
        modelCasting = false
        modelPassive = false
        modelFrame:Hide()
        UpdateNotifyAnchor()
        return
    end
    RefreshModelUnit()
end)

-- 变形时立刻收起立绘：德鲁伊进猫/熊、萨满开幽魂之狼等，
-- 不等下一次施法或换装备，避免巨大的非人模型留在屏幕上。
local formEventFrame = CreateFrame("Frame")
formEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
formEventFrame:SetScript("OnEvent", function()
    if not modelFrame:IsShown() then return end
    if not IsHumanForm() then
        modelCasting = false
        modelPassive = false
        ResetShock()
        modelFrame:Hide()
        UpdateNotifyAnchor()
    end
end)

-- 施法时让模型做施法动作，结束 / 打断后回到站立
local castEventFrame = CreateFrame("Frame")
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
}
for _, eventName in ipairs(CAST_EVENTS) do
    if castEventFrame.RegisterUnitEvent then
        castEventFrame:RegisterUnitEvent(eventName, "player")
    else
        castEventFrame:RegisterEvent(eventName)
    end
end
-- 施法时临时显示；结束/打断后过一小会儿自动收起
local function ShowCastModel()
    if not EnsureEmoteDB().showModel or not card:IsShown() then return false end
    -- 非人形态不显示立绘，也不消耗“本次战斗只能展示一次”的机会
    if not IsHumanForm() then return false end

    modelHideToken = modelHideToken + 1
    modelCasting = true
    modelPassive = false
    local wasHidden = not modelFrame:IsShown()
    modelFrame:Show()

    -- 只在从隐藏变为显示时重建模型，避免每次施法都重新加载，减少卡顿
    if wasHidden then
        RefreshModelUnit()
    end

    -- 切到施法动作；播完由 OnAnimFinished 自动重播
    if castAnimID then
        pcall(playerModel.SetAnimation, playerModel, castAnimID)
    end
    UpdateNotifyAnchor()
    return true
end

local function HideCastModelSoon(delay)
    modelHideToken = modelHideToken + 1
    local token = modelHideToken
    local function HideNow()
        if modelHideToken ~= token then return end

        -- 按住 Shift 调整窗口位置时先不收起，松手后再自动隐藏
        if IsShiftKeyDown() and C_Timer and C_Timer.After then
            C_Timer.After(1.0, HideNow)
            return
        end

        modelCasting = false
        modelPassive = false
        ResetShock()
        modelFrame:Hide()
        UpdateNotifyAnchor()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.9, HideNow)
    else
        HideNow()
    end
end

-- 被动进战：不施法、不亮施法动作，直接摆一个“哎呀”的哭泣/受击姿势
local function ShowHurtModel()
    if not EnsureEmoteDB().showModel or not card:IsShown() then return false end
    if not IsHumanForm() then return false end

    modelHideToken = modelHideToken + 1
    modelCasting = false
    modelPassive = true
    local wasHidden = not modelFrame:IsShown()
    if wasHidden then
        RefreshModelUnit()
    end

    -- 被动进战必须显示立绘：即使客户端没有哭泣 / 受击动画，也照常出现。
    -- 没有动画时靠下面的甩头 + 「？！」保持画面有反应，不会显得僵硬。
    modelFrame:Show()
    if passiveAnimID then
        pcall(playerModel.SetAnimation, playerModel, passiveAnimID)
    end
    PlayShock()
    UpdateNotifyAnchor()
    HideCastModelSoon(2.5)
    return true
end

-- 每次进入战斗只展示一次：记录本次战斗里是否已经触发过
local shownThisCombat = false

-- 被动进战（走进仇恨、被偷袭等）由 CombatEntry 通知，切到“哎呀”形象。
-- 主动进战不在这里处理，继续走原来的“第一次施法显示施法动作”。
if AP_CombatEntry and AP_CombatEntry.Register then
    AP_CombatEntry.Register(function(state)
        if state ~= "passive" then return end
        if ShowHurtModel() then
            shownThisCombat = true
        end
    end)
end

local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

local function IsPlayerInCombat()
    local ok, inCombat = pcall(UnitAffectingCombat, "player")
    if not ok or IsSecretValue(inCombat) then return false end
    return inCombat and true or false
end

local function HasHostileTarget()
    local okExists, exists = pcall(UnitExists, "target")
    if not okExists or IsSecretValue(exists) or not exists then return false end

    local okEnemy, enemy = pcall(UnitIsEnemy, "player", "target")
    if not okEnemy or IsSecretValue(enemy) then return false end
    return enemy and true or false
end

-- 是不是核心技能：是的话交给高光，正面形象不出现；
-- 不是核心技能才显示正面形象。两边互不抑制。
local function IsCoreSpellCast(spellID)
    return AP_Spotlight and AP_Spotlight.IsCoreSpell and AP_Spotlight.IsCoreSpell(spellID)
end

-- 起手用高光技能时，让高光模块跳过这一次，避免和 3D 模型同时出现
local function MaybeSuppressSpotlight(spellID)
    if IsCoreSpellCast(spellID) then return end
    if not spellID or shownThisCombat then return end
    if not EnsureEmoteDB().showModel or not card:IsShown() then return end
    -- 只针对战斗中或对敌对目标的起手，避免误伤脱战治疗/增益的高光
    if not IsPlayerInCombat() and not HasHostileTarget() then return end
    AP_SuppressSpotlightSpell = spellID
    AP_SuppressSpotlightAt = GetTime()
end

local function TryShowFirstCombatCast()
    if shownThisCombat then return end

    if IsPlayerInCombat() then
        -- 只有真正显示了立绘，才算用掉本次战斗的展示机会；
        -- 非人形态（猫/熊/狼等）不显示，之后变回人形再施法仍然可以展示。
        if ShowCastModel() then shownThisCombat = true end
        return
    end

    -- 起手技能（如月火术）在施法成功那一瞬间可能还没被标记为“战斗中”，
    -- 稍等 0.2 秒再检查一次，进战斗了就补上展示。
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            if shownThisCombat then return end
            if IsPlayerInCombat() then
                if ShowCastModel() then shownThisCombat = true end
            end
        end)
    end
end

-- 离开战斗时重置标记；不监听“进入战斗”，避免把刚补上的起手展示又清掉
local combatResetFrame = CreateFrame("Frame")
combatResetFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatResetFrame:SetScript("OnEvent", function()
    shownThisCombat = false
end)

castEventFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if unit and unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- 核心技能：不放正面形象，高光由 Spotlight 自己处理
        if not IsCoreSpellCast(spellID) then
            MaybeSuppressSpotlight(spellID)
            TryShowFirstCombatCast()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- 瞬发技能可能没有 START：第一次施法成功时也触发一次
        if not IsCoreSpellCast(spellID) then
            MaybeSuppressSpotlight(spellID)
            TryShowFirstCombatCast()
            HideCastModelSoon(2.5)
        end
    else
        -- 施法被中断/失败时清掉待用的高光抑制
        AP_SuppressSpotlightSpell = nil
        AP_SuppressSpotlightAt = nil
        -- 结束/打断后多留一会儿，方便看清动作
        HideCastModelSoon(1.5)
    end
end)

-- ==========================================
-- 属性条：力量 / 敏捷 / 智力 / 精神 / 回蓝 / 护甲 / 耐久
-- 夹在名牌和「表情与动作」标题之间，打开面板时立刻读数，之后每秒刷新。
-- ==========================================
-- 属性条同样挂在 card 上，× 关掉表情面板后仍然显示并继续刷新
local statsBar = CreateFrame("Frame", nil, card, "BackdropTemplate")
statsBar:SetSize(FRAME_W, 50)
-- 标题牌顶端在面板上方 12 像素，这里再留 10 像素间隙
statsBar:SetPoint("BOTTOM", card, "TOP", 0, 22)
statsBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
statsBar:SetBackdropColor(0.07, 0.07, 0.08, 0.96)
statsBar:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
MakeDragHandle(statsBar)

-- 12.0 起，战斗中的 UnitStat / UnitArmor 等会返回 secret 值：
-- 不能比较、不能做数学运算，但可以直接交给 FontString:SetText 显示。
-- 策略：能安全显示就显示实时值；显示不了就退回上一次非战斗时读到的值。
local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

-- 返回：普通数值 / isSecret 布尔 / secret 原值（原值不做任何运算）
local function ReadStat(index)
    local ok, value = pcall(UnitStat, "player", index)
    if not ok then return nil end
    if IsSecretValue(value) then return nil, true, value end
    if type(value) ~= "number" then return nil end
    return value
end

-- 已装备物品的耐久度平均值（戒指、饰品这类没有耐久的会自动跳过）。
-- 只要有一件读不到（secret），就整体退回缓存值，避免算出错误百分比。
local function GetDurabilityPercent()
    local total, count, blocked = 0, 0, false
    for slot = 1, 19 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok then
            if IsSecretValue(cur) or IsSecretValue(max) then
                blocked = true
            elseif type(cur) == "number" and type(max) == "number" and max > 0 then
                total = total + (cur / max)
                count = count + 1
            end
        end
    end
    if blocked or count == 0 then return nil end
    return total / count * 100
end

-- 七格的标签；desc 有内容的格子鼠标放上去会显示说明
local STAT_DEFS = {
    { key = "str",   label = "力量" },
    { key = "agi",   label = "敏捷" },
    { key = "int",   label = "智力" },
    { key = "spi",   label = "精神" },
    { key = "mana",  label = "回蓝", desc = "每秒自动回复的法力。" },
    { key = "armor", label = "护甲" },
    { key = "dura",  label = "耐久", desc = "已装备物品的平均剩余耐久度。" },
}

local statValues = {}
local statLabels = {}
local STAT_INNER = 4
local statCellW = (FRAME_W - STAT_INNER * 2) / #STAT_DEFS

for i, def in ipairs(STAT_DEFS) do
    local cell = CreateFrame("Button", nil, statsBar)
    cell:SetSize(statCellW, 42)
    cell:SetPoint("TOPLEFT", statsBar, "TOPLEFT", STAT_INNER + (i - 1) * statCellW, -4)

    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", cell, "TOP", 0, 0)
    label:SetWidth(statCellW - 2)
    label:SetJustifyH("CENTER")
    label:SetFont(label:GetFont(), 13, "")
    label:SetShadowColor(0, 0, 0, 0.75)
    label:SetShadowOffset(1, -1)
    label:SetTextColor(0.65, 0.65, 0.7)
    label:SetText(def.label)
    statLabels[def.key] = label

    local value = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOP", label, "BOTTOM", 0, -3)
    value:SetWidth(statCellW - 2)
    value:SetJustifyH("CENTER")
    value:SetFont(value:GetFont(), 13, "")
    value:SetShadowColor(0, 0, 0, 0.85)
    value:SetShadowOffset(1, -1)
    value:SetTextColor(1, 0.9, 0.6)
    value:SetText("—")
    statValues[def.key] = value

    if def.desc then
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(def.label, 1, 0.85, 0.3)
            GameTooltip:AddLine(def.desc, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- 细竖线分隔（最后一格不加）
    if i < #STAT_DEFS then
        local sep = cell:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(0.35, 0.35, 0.4, 0.45)
        sep:SetSize(1, 30)
        sep:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    end

    -- 属性格本身也是拖动把手：按住 Shift 在数值上拖也能移动整个卡片
    MakeDragHandle(cell)
end

-- 上一次在非战斗时读到的值，战斗中被 secret 挡住时拿来顶上
local statCache = {}

-- 尝试直接显示 secret 数值：只做格式化和 SetText，不做比较/运算
local function TryShowSecret(fontString, raw, fmt)
    if fmt then
        local okFmt, text = pcall(string.format, fmt, raw)
        if okFmt then
            if pcall(fontString.SetText, fontString, text) then return true end
        end
    end
    -- 数字直接交给 SetText，让客户端自己转换
    return pcall(fontString.SetText, fontString, raw)
end

-- value = 普通数值；isSecret = true 时 value 为 nil、raw 是 secret 原值
local function ShowStat(key, value, isSecret, raw, fmt)
    local fs = statValues[key]

    if isSecret then
        if TryShowSecret(fs, raw, fmt) then return end
        fs:SetText(statCache[key] or "—")
        return
    end

    if value ~= nil then
        local text
        if fmt then
            text = string.format(fmt, value)
        else
            text = tostring(math.floor(value + 0.5))
        end
        statCache[key] = text
        fs:SetText(text)
    else
        fs:SetText(statCache[key] or "—")
    end
end

local function UpdateStats()
    -- 力量 / 敏捷 / 智力 / 精神
    local v, isSecret, raw = ReadStat(1)
    ShowStat("str", v, isSecret, raw)
    v, isSecret, raw = ReadStat(2)
    ShowStat("agi", v, isSecret, raw)
    v, isSecret, raw = ReadStat(4)
    ShowStat("int", v, isSecret, raw)
    v, isSecret, raw = ReadStat(5)
    ShowStat("spi", v, isSecret, raw)

    -- 回蓝：GetManaRegen 返回每秒回复量，保留一位小数
    local okRegen, regen = pcall(GetManaRegen)
    local regenValue, regenIsSecret, regenRaw
    if okRegen then
        if IsSecretValue(regen) then
            regenIsSecret, regenRaw = true, regen
        elseif type(regen) == "number" then
            regenValue = regen
        end
    end
    ShowStat("mana", regenValue, regenIsSecret, regenRaw, "%.1f")

    -- 护甲：UnitArmor 的第二个返回值是当前有效护甲
    local okArmor, baseArmor, effectiveArmor = pcall(UnitArmor, "player")
    local armorValue, armorIsSecret, armorRaw
    if okArmor then
        if IsSecretValue(effectiveArmor) then
            armorIsSecret, armorRaw = true, effectiveArmor
        elseif type(effectiveArmor) == "number" then
            armorValue = effectiveArmor
        elseif IsSecretValue(baseArmor) then
            armorIsSecret, armorRaw = true, baseArmor
        elseif type(baseArmor) == "number" then
            armorValue = baseArmor
        end
    end
    ShowStat("armor", armorValue, armorIsSecret, armorRaw)

    -- 耐久：只认正常数值，读不到就用上次缓存
    local dura = GetDurabilityPercent()
    if dura then
        local text = string.format("%.0f%%", dura)
        statCache.dura = text
        statValues.dura:SetText(text)
    else
        statValues.dura:SetText(statCache.dura or "—")
    end
end

-- 面板每次显示时立刻刷新
frame:HookScript("OnShow", UpdateStats)

-- 登录时先读一遍：趁通常还在非战斗状态，把数值缓存起来，
-- 这样第一次战斗中打开面板也不会是「—」。
local statsLogin = CreateFrame("Frame")
statsLogin:RegisterEvent("PLAYER_LOGIN")
statsLogin:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    UpdateStats()
end)

-- 面板开着的时候每秒刷新一次：换装备、上 buff、掉耐久都能及时反映
local statElapsed = 0
statsBar:SetScript("OnUpdate", function(_, elapsed)
    statElapsed = statElapsed + elapsed
    if statElapsed < 1 then return end
    statElapsed = 0
    UpdateStats()
    UpdateNameplate() -- 表情面板关掉后名牌仍在，这里顺带保持名字/流派实时
end)

-- ==========================================
-- 姓名下方的小图标：核心 / 技能熟练度 / 属性 / 主界面
-- ==========================================
local MINI_SIZE = 22
local MINI_GAP = 6
local miniRow = CreateFrame("Frame", nil, nameplate)
miniRow:SetSize(MINI_SIZE * 4 + MINI_GAP * 3, MINI_SIZE)
miniRow:SetPoint("TOP", plateFaction, "BOTTOM", 0, -4)

local function MakeMiniButton(index, icon, tooltipText, onClick)
    local btn = CreateFrame("Button", nil, miniRow, "BackdropTemplate")
    btn:SetSize(MINI_SIZE, MINI_SIZE)
    btn:SetPoint("LEFT", miniRow, "LEFT", (index - 1) * (MINI_SIZE + MINI_GAP), 0)
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    btn:SetBackdropColor(0, 0, 0, 0.55)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tex:SetTexture(icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.texture = tex -- 允许之后动态换图标（第一个小图标跟随流派）

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(currentTheme.border[1], currentTheme.border[2], currentTheme.border[3], 0.35)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tooltipText, 1, 0.85, 0.3)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.55)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

-- 1) 核心奥义：图标与当前流派图标一致，点击打开核心页（不播放高光）
coreIcon = MakeMiniButton(1, "Interface\\Icons\\INV_Misc_QuestionMark",
    "核心奥义：打开核心页", function()
        UI.OpenCoreSettings()
    end)

-- 2) 技能熟练度：直接打开「职业流派 → 称谓典籍」页（卡片保持显示，不隐藏）
MakeMiniButton(2, "Interface\\Icons\\INV_Sword_04",
    "技能熟练度：打开称谓典籍", function()
        if AP_FlavorUI and AP_FlavorUI.OpenSkillBook then
            AP_FlavorUI.OpenSkillBook()
        elseif AP_MainFrame then
            AP_MainFrame:Show()
        end
    end)

-- 3) 属性：显示 / 隐藏下面的属性条
MakeMiniButton(3, "Interface\\Icons\\Spell_Nature_Strength",
    "属性：显示 / 隐藏属性条", function(self)
        local show = not statsBar:IsShown()
        statsBar:SetShown(show)
        self:SetAlpha(show and 1 or 0.5)
    end)

-- 4) 主界面：打开 / 关闭 /AP 面板；打开时固定切到「设定」页
MakeMiniButton(4, "Interface\\Icons\\INV_Misc_Book_09",
    "主界面：打开 / 关闭 /AP 面板（默认设定页）", function()
        if AP_MainFrame then
            if AP_MainFrame:IsShown() then
                AP_MainFrame:Hide()
            else
                AP_MainFrame:Show()
                -- 不沿用上次停留的页，固定打开第 1 页「设定」
                if AP_Tabs and AP_Tabs[1] and AP_Tabs[1].Click then
                    AP_Tabs[1]:Click()
                end
            end
        end
    end)

-- 关闭按钮（右上角小叉）
local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
close:SetScale(0.75)

-- 不注册到 UISpecialFrames：按 ESC 不要关闭这张卡片。
-- 需要关闭时用右上角 ×（只关表情面板）或 /ape（整张卡片一起开关）。

-- 「要说的话」的选择列表在下方才创建，这里先声明一下，
-- 这样上面的按钮点击时就能引用到它（Lua 的局部变量要先声明后使用）。
local picker

-- 图标按钮：基础 8 个 + 自定义 2 个，一次性建好 10 个
local buttons = {}

-- 点击任意按钮后，统一让所有按钮转圈冷却
local function StartCooldown()
    lastUse = GetTime()
    for _, b in ipairs(buttons) do
        b.cooldown:SetCooldown(lastUse, GLOBAL_CD)
    end
end

-- 刷新按钮图标（自定义按钮以后想换图标扩展时也能用上）
local function RefreshButtons()
    local list = GetEntries()
    for i, btn in ipairs(buttons) do
        local entry = list[i]
        if entry then
            btn.icon:SetTexture(entry.icon or FALLBACK_ICON)
        end
    end
end
UI.Refresh = RefreshButtons

local initialEntries = GetEntries()
for i = 1, #initialEntries do
    local entry = initialEntries[i] -- 这里只用来决定初始图标
    local col = (i - 1) % COLUMNS
    local row = math.floor((i - 1) / COLUMNS)

    local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PAD + col * (BTN_SIZE + BTN_GAP),
        -(PAD + TITLE_AREA - 8) - row * (BTN_SIZE + BTN_GAP))
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0, 0, 0, 1)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(entry.icon or FALLBACK_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- 冷却转圈
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", 4, -4)
    cd:SetPoint("BOTTOMRIGHT", -4, 4)
    cd:SetDrawEdge(false)
    btn.cooldown = cd

    -- 按下时图标微微下沉
    btn:SetScript("OnMouseDown", function(self)
        self.icon:SetPoint("TOPLEFT", 5, -5)
        self.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.icon:SetPoint("TOPLEFT", 4, -4)
        self.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    end)

    btn:SetScript("OnEnter", function(self)
        -- 每次悬停都重新读一遍，设定页改完自定义内容后会立刻反映在提示里
        local now = GetEntries()[i]
        if not now then return end
        self:SetBackdropBorderColor(currentTheme.border[1], currentTheme.border[2], currentTheme.border[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(now.name, 1, 0.85, 0.3)
        if now.desc then GameTooltip:AddLine(now.desc, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(currentTheme.buttonBorder[1], currentTheme.buttonBorder[2], currentTheme.buttonBorder[3], 1)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if GetTime() - lastUse < GLOBAL_CD then return end
        local now = GetEntries()[i]
        if not now then return end

        -- 「要说的话」和「最近常用」：先弹出列表，选完才算真正使用
        if now.pick or now.recent then
            if picker:IsShown() then
                picker:Hide()
            else
                UI.OpenPicker(now)
            end
            return
        end

        if picker then picker:Hide() end

        -- 自定义按钮但还没填内容：提示去哪儿设置，不进入冷却
        if now.customSlot and (not now.text or now.text == "") then
            print("|cffffd700[AP]|r「" .. now.name ..
                "」还没有内容，请打开 /AP →「设定」→「表情动作」填写。")
            return
        end

        StartCooldown()
        Perform(now)
    end)

    buttons[i] = btn
end

-- ==========================================
-- 选择列表（「要说的话」和「最近常用」共用，点第 1 / 第 2 个按钮时弹出）
-- ==========================================
local PICKER_W = 360
local PICKER_ROW_H = 26
local PICKER_LIST_TOP = 46 -- 顶部标题占掉的高度
local PICKER_MAX_ROWS = 10 -- 一屏最多显示几行，多出来的滚动查看
local PICKER_H = PICKER_LIST_TOP + PICKER_MAX_ROWS * PICKER_ROW_H + 10

picker = CreateFrame("Frame", "AP_EmotePicker", frame, "BackdropTemplate")
picker:SetSize(PICKER_W, PICKER_H)
-- 跟卡片一起留在暴雪窗口下方；只抬高自己的层级，保证浮在卡片之上
picker:SetFrameStrata("MEDIUM")
picker:SetFrameLevel(6000)
picker:SetClampedToScreen(true)
picker:EnableMouse(true) -- 挡住点击，避免点穿到后面的面板
picker:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
picker:SetBackdropColor(0.07, 0.07, 0.08, 0.98)
picker:SetBackdropBorderColor(0.9, 0.72, 0.28, 1)
picker:Hide()

local pickerTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pickerTitle:SetPoint("TOPLEFT", 12, -10)
pickerTitle:SetText("要说的话")
pickerTitle:SetFont(pickerTitle:GetFont(), 16, "OUTLINE")
pickerTitle:SetTextColor(1, 0.85, 0.3)

local pickerClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
pickerClose:SetPoint("TOPRIGHT", picker, "TOPRIGHT", 1, 1)
pickerClose:SetScale(0.7)

-- 话术可能很多，这里用滚动框：固定显示 PICKER_MAX_ROWS 行，其余滚动查看。
local pickerScroll = CreateFrame("ScrollFrame", "AP_EmotePickerScroll", picker, "UIPanelScrollFrameTemplate")
pickerScroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -PICKER_LIST_TOP)
pickerScroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -10, 10)
pickerScroll:EnableMouseWheel(true)

local pickerContent = CreateFrame("Frame", nil, pickerScroll)
pickerContent:SetWidth(PICKER_W - 10 - 10 - 18) -- 右侧给滚动条留位置
pickerContent:SetHeight(1)
pickerScroll:SetScrollChild(pickerContent)

local function PickerScrollBy(delta)
    local maxScroll = pickerScroll:GetVerticalScrollRange()
    local newScroll = pickerScroll:GetVerticalScroll() - delta * (PICKER_ROW_H * 2)
    if newScroll < 0 then
        newScroll = 0
    elseif newScroll > maxScroll then
        newScroll = maxScroll
    end
    pickerScroll:SetVerticalScroll(newScroll)
end

pickerScroll:SetScript("OnMouseWheel", function(_, delta) PickerScrollBy(delta) end)

-- 第 1、2 个按钮右上角的小 ×：列表打开时出现，点一下就收起
local pickerOwnerIndex
local pickerCloseBtns = {}
local function UpdatePickerCloseBtns()
    for i = 1, 2 do
        local closeBtn = pickerCloseBtns[i]
        if closeBtn then
            if picker:IsShown() and pickerOwnerIndex == i then
                closeBtn:Show()
            else
                closeBtn:Hide()
            end
        end
    end
end

for i = 1, 2 do
    -- 自己画一个明显的红色小方块 ×，不依赖客户端模板
    local closeBtn = CreateFrame("Button", nil, buttons[i], "BackdropTemplate")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", buttons[i], "TOPRIGHT", 6, 6)
    closeBtn:SetFrameLevel(buttons[i]:GetFrameLevel() + 20)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.55, 0.12, 0.10, 0.95)
    closeBtn:SetBackdropBorderColor(0.95, 0.80, 0.35, 1)

    local mark = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mark:SetPoint("CENTER", 0, 0)
    mark:SetFont(mark:GetFont(), 14, "OUTLINE")
    mark:SetText("×")
    mark:SetTextColor(1, 0.95, 0.8)

    closeBtn:SetScript("OnClick", function() picker:Hide() end)
    closeBtn:Hide()
    pickerCloseBtns[i] = closeBtn
end

picker:HookScript("OnShow", UpdatePickerCloseBtns)
picker:HookScript("OnHide", UpdatePickerCloseBtns)

-- 按 ESC 也能收起选择列表；卡片本身不注册，避免误关整张卡片
if UISpecialFrames then
    local registered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "AP_EmotePicker" then
            registered = true
            break
        end
    end
    if not registered then
        table.insert(UISpecialFrames, "AP_EmotePicker")
    end
end

-- 列表里的每一行都是按钮，第一次用到时才创建，之后反复复用
local pickerRows = {}

function UI.OpenPicker(entry)
    -- 「要说的话」是句子列表；「最近常用」是表情列表，行点击后直接做表情
    local items
    if entry.recent then
        pickerTitle:SetText("最近常用表情")
        items = GetRecentItems()
    else
        pickerTitle:SetText(entry.name or "要说的话")
        items = {}
        for _, line in ipairs(entry.lines or {}) do
            items[#items + 1] = { text = line }
        end
    end

    -- 内容总高度按条目数量算；超出一屏的部分靠滚动查看
    pickerContent:SetHeight(math.max(#items * PICKER_ROW_H, 1))
    pickerScroll:SetVerticalScroll(0)

    for i = 1, #items do
        local lineBtn = pickerRows[i]
        if not lineBtn then
            lineBtn = CreateFrame("Button", nil, pickerContent, "BackdropTemplate")
            lineBtn:SetHeight(PICKER_ROW_H - 2)
            lineBtn:SetPoint("TOPLEFT", pickerContent, "TOPLEFT", 0, -(i - 1) * PICKER_ROW_H)
            lineBtn:SetPoint("TOPRIGHT", pickerContent, "TOPRIGHT", 0, -(i - 1) * PICKER_ROW_H)
            lineBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            local rowBg = currentTheme.pickerRowBg or { 0.12, 0.12, 0.14, 0.85 }
            lineBtn:SetBackdropColor(rowBg[1], rowBg[2], rowBg[3], rowBg[4])
            lineBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

            local text = lineBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", 8, 0)
            text:SetPoint("RIGHT", lineBtn, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            text:SetFont(text:GetFont(), 13, "")
            local rowText = currentTheme.pickerText or { 1, 1, 1 }
            text:SetTextColor(rowText[1], rowText[2], rowText[3])
            lineBtn.text = text

            -- 同一个按钮会被反复使用，所以点击时读 self.line，
            -- 不要直接捕获循环变量（否则每行都会说最后一句）。
            lineBtn:SetScript("OnClick", function(self)
                if self.item then UI.PickItem(self.item) end
            end)

            -- 鼠标停在句子上也能用滚轮翻列表
            lineBtn:EnableMouseWheel(true)
            lineBtn:SetScript("OnMouseWheel", function(_, delta) PickerScrollBy(delta) end)

            pickerRows[i] = lineBtn
        end

        lineBtn:Show()
        lineBtn.item = items[i]
        lineBtn.text:SetText(items[i].text)
    end

    -- 这次内容比上次少时，把多出来的旧行藏起来
    for i = #items + 1, #pickerRows do
        pickerRows[i]:Hide()
    end

    -- 贴在表情面板左边；屏幕太窄时 SetClampedToScreen 会自动把它拉回屏幕内
    pickerOwnerIndex = entry.recent and 2 or 1
    picker:ClearAllPoints()
    picker:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
    picker:Show()
    UpdatePickerCloseBtns()
end

-- 选好一条：说话或做表情 + 所有按钮进入冷却 + 收起列表。
-- 这里不再检查冷却：点开列表再挑一条本身就已经是明确的动作了，
-- 选中后列表会立刻收起，也不存在连点刷屏的问题。
function UI.PickItem(item)
    if not item then return end
    StartCooldown()
    if item.token then
        -- 最近常用：做表情，并记录到最近列表
        pcall(DoEmote, item.token, FriendlyTargetUnit())
        RecordEmote(item.token)
    else
        SendChatMessage(RP_PREFIX .. item.text, "SAY")
    end
    picker:Hide()
end

-- 主面板或整张卡片收起时，选择列表也一起收起来。
-- 否则下次打开面板，上次没关的列表还会自己冒出来。
frame:HookScript("OnHide", function() picker:Hide() end)
card:HookScript("OnHide", function() picker:Hide() end)

-- ==========================================
-- 把选中的配色套到卡片各部件上
-- ==========================================
local function ApplyTheme(themeID)
    local t = THEMES[themeID] or THEMES.classic
    currentTheme = t

    -- 没有单独配的字段就用深色套装的默认值
    local bodyBg = t.bodyBg or { 0.07, 0.07, 0.08, 0.96 }
    local buttonBg = t.buttonBg or { 0, 0, 0, 1 }
    local muted = t.muted or { 0.65, 0.65, 0.70 }
    local pickerBg = t.pickerBg or { 0.07, 0.07, 0.08, 0.98 }
    local pickerRowBg = t.pickerRowBg or { 0.12, 0.12, 0.14, 0.85 }
    local pickerText = t.pickerText or { 1, 1, 1 }

    -- 表情面板
    frame:SetBackdropColor(bodyBg[1], bodyBg[2], bodyBg[3], bodyBg[4])
    frame:SetBackdropBorderColor(t.frameBorder[1], t.frameBorder[2], t.frameBorder[3], 1)

    -- 标题牌
    title:SetBackdropColor(t.panelBg[1], t.panelBg[2], t.panelBg[3], 1)
    title:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    titleText:SetTextColor(t.accent[1], t.accent[2], t.accent[3])

    -- 名牌
    nameplate:SetBackdropColor(t.panelBg[1], t.panelBg[2], t.panelBg[3], 0.95)
    nameplate:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    plateName:SetTextColor(t.accent[1], t.accent[2], t.accent[3])

    -- 属性条
    statsBar:SetBackdropColor(bodyBg[1], bodyBg[2], bodyBg[3], bodyBg[4])
    statsBar:SetBackdropBorderColor(t.frameBorder[1], t.frameBorder[2], t.frameBorder[3], 1)
    for _, label in pairs(statLabels) do
        label:SetTextColor(muted[1], muted[2], muted[3])
    end
    for _, value in pairs(statValues) do
        value:SetTextColor(t.accent[1], t.accent[2], t.accent[3])
    end

    -- 图标按钮
    for _, btn in ipairs(buttons) do
        btn:SetBackdropColor(buttonBg[1], buttonBg[2], buttonBg[3], buttonBg[4])
        btn:SetBackdropBorderColor(t.buttonBorder[1], t.buttonBorder[2], t.buttonBorder[3], 1)
    end

    -- 话术列表
    picker:SetBackdropColor(pickerBg[1], pickerBg[2], pickerBg[3], pickerBg[4])
    picker:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    pickerTitle:SetTextColor(t.accent[1], t.accent[2], t.accent[3])
    for _, row in ipairs(pickerRows) do
        row:SetBackdropColor(pickerRowBg[1], pickerRowBg[2], pickerRowBg[3], pickerRowBg[4])
        if row.text then
            row.text:SetTextColor(pickerText[1], pickerText[2], pickerText[3])
        end
    end

    -- 浅色主题下流派颜色要重新压暗，立即刷一下名牌
    UpdateNameplate()
end
UI.ApplyTheme = ApplyTheme

-- 加载时先按默认风格铺一遍；SavedVariables 注入后再由登录事件重新套用
ApplyTheme(EnsureEmoteDB().theme)

local themeLogin = CreateFrame("Frame")
themeLogin:RegisterEvent("PLAYER_LOGIN")
themeLogin:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ApplyTheme(EnsureEmoteDB().theme)
end)

-- ==========================================
-- 对外接口 / 斜杠命令
-- ==========================================
function UI.Show()
    ApplyTheme(EnsureEmoteDB().theme)
    UpdateNameplate()
    UpdateStats()
    frame:Show()
    card:Show()
    UI.RefreshModel()
end

-- 从卡片图标直接打开「设定 → 正面形象」页
function UI.OpenModelSettings()
    if AP_CloseDanmakuSettings then AP_CloseDanmakuSettings() end
    if AP_MainFrame then AP_MainFrame:Show() end
    if AP_Tabs and AP_Tabs[1] and AP_Tabs[1].Click then
        AP_Tabs[1]:Click() -- 切到「设定」
    end
    if AP_SelectSettingsTab then AP_SelectSettingsTab("model") end
end

-- 从卡片第一个图标打开「核心奥义」页；只打开页面，不播放高光
function UI.OpenCoreSettings()
    if AP_MainFrame then AP_MainFrame:Show() end
    if AP_SelectTab then
        AP_SelectTab(4) -- 面板 4 = 核心奥义（视觉上排第三个页签）
    end
    if AP_Spotlight and AP_Spotlight.RefreshCoreUI then
        AP_Spotlight.RefreshCoreUI()
    end
end

function UI.Hide()
    if picker then picker:Hide() end
    card:Hide()
end

function UI.Toggle()
    if not card:IsShown() then
        UI.Show()
    elseif not frame:IsShown() then
        -- 只剩名牌和属性条时，再按 /ape 先把表情面板叫回来
        frame:Show()
    else
        UI.Hide()
    end
end

SLASH_APEMOTE1 = "/ape"
SlashCmdList["APEMOTE"] = function() UI.Toggle() end

-- ==========================================
-- 设定页入口：和「聊天弹幕」并排放在一起
-- ==========================================
local settingPanel = AP_Panels and AP_Panels[1]
if settingPanel and settingPanel.LeftPage and settingPanel.RightPage then
    local entryBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
    entryBtn:SetSize(200, 36)
    -- 聊天弹幕的入口按钮在 CENTER (0, 40)，这里紧挨着放在下方
    entryBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, -10)
    entryBtn:SetText("表情动作")
    entryBtn:SetScript("OnClick", function()
        -- 左页按钮只负责切换右页分页，不再直接打开卡片
        if AP_SelectSettingsTab then AP_SelectSettingsTab("emote") end
    end)
    -- 打开弹幕设置子页时，这个入口按钮也要一起藏起来
    if AP_RegisterSettingsEntry then AP_RegisterSettingsEntry(entryBtn) end

    -- 正面形象：同样只切换右页分页，真正的开关在右页 checkbox 里
    local modelBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
    modelBtn:SetSize(200, 36)
    modelBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, -60)
    modelBtn:SetText("正面形象")
    modelBtn:SetScript("OnClick", function()
        if AP_SelectSettingsTab then AP_SelectSettingsTab("model") end
    end)
    if AP_RegisterSettingsEntry then AP_RegisterSettingsEntry(modelBtn) end

    -- ---------- 右侧：风格 → 显示开关 → 5 个自定义槽 ----------
    -- 右页已由 Danmaku.lua 做成分页，这里挂到「表情动作」那一页里
    local page = AP_EmoteSettingsPage or settingPanel.RightPage

    -- 最上面是卡片风格
    local themeRow = CreateFrame("Frame", nil, page)
    themeRow:SetSize(340, 26)
    themeRow:SetPoint("TOP", page, "TOP", 0, -10)

    local themeLabel = themeRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("LEFT", themeRow, "LEFT", 0, 0)
    themeLabel:SetText("卡片风格")
    themeLabel:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

    local themeButtons = {}
    local function RefreshThemeButtons()
        local selected = EnsureEmoteDB().theme
        if not THEMES[selected] then selected = "classic" end
        for id, btn in pairs(themeButtons) do
            btn:SetButtonState(id == selected and "PUSHED" or "NORMAL", id == selected)
        end
    end

    for i, id in ipairs(THEME_ORDER) do
        local btn = CreateFrame("Button", nil, themeRow, "UIPanelButtonTemplate")
        btn:SetSize(44, 22)
        btn:SetPoint("LEFT", themeRow, "LEFT", 60 + (i - 1) * 46, 0)
        btn:SetText(THEMES[id].name)
        btn:SetScript("OnClick", function()
            EnsureEmoteDB().theme = id
            ApplyTheme(id)
            RefreshThemeButtons()
        end)
        themeButtons[id] = btn
    end

    -- ---------- 卡片显示开关 ----------
    local cardToggle = CreateFrame("CheckButton", "AP_EmoteCardToggle", page, "ChatConfigCheckButtonTemplate")
    cardToggle:SetPoint("TOPLEFT", themeRow, "BOTTOMLEFT", 0, -12)
    local cardToggleText = _G[cardToggle:GetName() .. "Text"]
    cardToggleText:SetText("显示表情动作卡片")
    cardToggleText:SetFont(cardToggleText:GetFont(), 14, "")
    cardToggleText:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    cardToggle:SetChecked(card:IsShown())
    cardToggle:SetScript("OnClick", function(self)
        if self:GetChecked() then UI.Show() else UI.Hide() end
    end)
    card:HookScript("OnShow", function()
        cardToggle:SetChecked(true)
        EnsureEmoteDB().cardEnabled = true
    end)
    card:HookScript("OnHide", function()
        cardToggle:SetChecked(false)
        EnsureEmoteDB().cardEnabled = false
    end)

    -- 5 个编辑器的「从存档读入输入框」函数。等存档真正加载完再统一调用。
    local editorLoaders = {}

    -- 一个自定义槽：标签 + 一行输入框 + 保存。
    -- 前 2 个槽是 /e 表情，后 3 个槽是说话。
    local function BuildCustomEditor(slot, anchor)
        local isEmoteSlot = slot <= 2
        local block = CreateFrame("Frame", nil, page, "BackdropTemplate")
        block:SetSize(340, 46)
        if anchor then
            -- 后面的槽跟着上一块往下排，宽度相同，中心自然对齐
            block:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
        else
            -- 第一块直接水平居中挂在右页顶部，避免跟着 checkbox 的窄锚点歪到左页
            block:SetPoint("TOP", page, "TOP", 0, -84)
        end
        block:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        block:SetBackdropColor(0.30, 0.19, 0.09, 0.10)
        block:SetBackdropBorderColor(AP_Theme.line[1], AP_Theme.line[2], AP_Theme.line[3], 0.45)

        local label = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 10, -5)
        label:SetFont(label:GetFont(), 12, "")
        label:SetText(isEmoteSlot and ("自定义表情 " .. slot) or ("自定义说话 " .. (slot - 2)))
        label:SetTextColor(AP_Theme.accent[1], AP_Theme.accent[2], AP_Theme.accent[3])

        local textBox = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
        textBox:SetPoint("TOPLEFT", block, "TOPLEFT", 10, -24)
        textBox:SetPoint("TOPRIGHT", block, "TOPRIGHT", -66, -24)
        textBox:SetHeight(20)
        textBox:SetAutoFocus(false)
        textBox:SetMaxLetters(isEmoteSlot and 80 or 120)
        textBox:SetText("")
        textBox:SetScript("OnEscapePressed", textBox.ClearFocus)

        local save = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
        save:SetSize(50, 20)
        save:SetPoint("TOPRIGHT", block, "TOPRIGHT", -8, -24)
        save:SetText("保存")

        -- 注意不能在文件加载时直接读：那时 SavedVariables 还没注入，读到的会是空表。
        local function LoadFromDB()
            local cfg = GetCustomConfig(slot)
            textBox:SetText(cfg.text or "")
        end
        editorLoaders[#editorLoaders + 1] = LoadFromDB

        local function Save()
            -- 关键：保存时重新取一次存档表。
            local cfg = GetCustomConfig(slot)
            cfg.text = TrimText(textBox:GetText())
            textBox:SetText(cfg.text)
            textBox:SetCursorPosition(0)
            -- 让浮动面板里的按钮提示立刻刷新
            if UI.Refresh then UI.Refresh() end
        end

        save:SetScript("OnClick", Save)
        textBox:SetScript("OnEnterPressed", function(self)
            Save()
            self:ClearFocus()
        end)

        return block
    end

    local lastBlock = BuildCustomEditor(1)
    for slot = 2, CUSTOM_COUNT do
        lastBlock = BuildCustomEditor(slot, lastBlock)
    end

    -- ---------- 正面形象分页 ----------
    local modelPage = AP_ModelSettingsPage or page
    local modelHeader = modelPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modelHeader:SetPoint("TOP", modelPage, "TOP", 0, -18)
    modelHeader:SetText("正面形象")
    modelHeader:SetFont(modelHeader:GetFont(), 20, "")
    modelHeader:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

    local modelToggle = CreateFrame("CheckButton", "AP_ModelToggle", modelPage, "ChatConfigCheckButtonTemplate")
    modelToggle:SetPoint("TOPLEFT", modelPage, "TOPLEFT", 34, -66)
    local modelToggleText = _G[modelToggle:GetName() .. "Text"]
    modelToggleText:SetText("开启正面形象（施法时显示）")
    modelToggleText:SetFont(modelToggleText:GetFont(), 14, "")
    modelToggleText:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    modelToggle:SetChecked(EnsureEmoteDB().showModel and true or false)
    modelToggle:SetScript("OnClick", function(self)
        EnsureEmoteDB().showModel = self:GetChecked() and true or false
        if UI.RefreshModel then UI.RefreshModel() end
    end)

    local modelDesc = modelPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modelDesc:SetPoint("TOPLEFT", modelPage, "TOPLEFT", 34, -100)
    modelDesc:SetWidth(332)
    modelDesc:SetJustifyH("LEFT")
    modelDesc:SetSpacing(6)
    modelDesc:SetFont(modelDesc:GetFont(), 13, "")
    modelDesc:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    modelDesc:SetText("勾选后，进入战斗后的第一次施法时，\n会在姓名卡片上方显示角色正面的 3D 模型。\n\n只在人形态显示；德鲁伊变形、幽魂之狼等非人形态不会出现。\n\n每次战斗只出现一次，结束约 1 秒后自动收起，\n不会常驻占用屏幕。\n\n需要先显示表情动作卡片，模型才会出现。")

    -- SavedVariables 在 Lua 文件执行完之后才注入，所以加载时不要立刻读。
    -- 登录完成后再把存档内容填进两个输入框、套用上次选中的风格。
    local function RefreshCustomEditors()
        for _, load in ipairs(editorLoaders) do load() end
    end

    local function RefreshSettingsPage()
        RefreshCustomEditors()
        ApplyTheme(EnsureEmoteDB().theme)
        RefreshThemeButtons()
        cardToggle:SetChecked(card:IsShown())
        modelToggle:SetChecked(EnsureEmoteDB().showModel and true or false)
    end

    local loginFrame = CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        RefreshSettingsPage()
        if UI.RestoreModelPosition then UI.RestoreModelPosition() end
        -- 上次勾选了「显示表情动作卡片」就自动显示，不用每次重新勾
        if EnsureEmoteDB().cardEnabled then UI.Show() end
    end)

    -- ADDON_LOADED 时 SavedVariables 已经就绪：立刻恢复勾选状态、卡片与模型窗口位置
    local loadedFrame = CreateFrame("Frame")
    loadedFrame:RegisterEvent("ADDON_LOADED")
    loadedFrame:SetScript("OnEvent", function(self, event, addonName)
        if addonName ~= "AzerothParallel" then return end
        self:UnregisterEvent("ADDON_LOADED")
        RefreshSettingsPage()
        if UI.RestorePosition then UI.RestorePosition() end
        if UI.RestoreModelPosition then UI.RestoreModelPosition() end
    end)

    -- 之后每次打开主界面也同步一次，避免别处改了存档后输入框还是旧的
    if AP_MainFrame then
        AP_MainFrame:HookScript("OnShow", RefreshSettingsPage)
    end
end

-- ==========================================
-- 手动输入的表情也记进「最近常用」
-- ==========================================
-- 玩家自己在聊天框敲 /sleep、/dance 时不会经过插件的 DoEmote，
-- 所以在发送前读一下命令，只记录，不改变原来的发送行为。
local function TryRecordSlashEmote(text)
    if type(text) ~= "string" then return end
    local cmd = text:match("^/(%S+)")
    if not cmd then return end
    local token = cmd:upper()
    if EMOTE_NAMES[token] and not IsReservedEmote(token) then
        RecordEmote(token)
    end
end

if type(ChatEdit_SendText) == "function" then
    local originalSendText = ChatEdit_SendText
    ChatEdit_SendText = function(editBox, ...)
        if editBox and editBox.GetText then
            TryRecordSlashEmote(editBox:GetText())
        end
        return originalSendText(editBox, ...)
    end
end
