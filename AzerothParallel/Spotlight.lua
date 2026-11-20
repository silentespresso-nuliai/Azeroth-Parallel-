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
    if type(db.soundIndex) ~= "number" or db.soundIndex < 0 or db.soundIndex > 3 then
        db.soundIndex = 0
    end
    if db.broadcast == nil then db.broadcast = true end
    if db.position ~= "TOPLEFT" and db.position ~= "TOPRIGHT" then
        db.position = "TOPRIGHT"
    end
    -- 自定义大招：只存一个字符串，可以是技能名，也可以是技能 ID（纯数字）。
    -- 留空 = 使用下面写好的默认职业表。
    if type(db.customSpell) ~= "string" then db.customSpell = "" end
    -- 触发时的喊话/动作：文本可以留空；模式 OFF = 不喊
    if type(db.chatText) ~= "string" then db.chatText = "" end
    if db.chatMode ~= "YELL" and db.chatMode ~= "EMOTE" and db.chatMode ~= "OFF" then
        db.chatMode = "OFF"
    end
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

-- 清理广播字段：去掉换行、管道符、颜色代码，并限制长度
local function Sanitize(text, maxLength)
    if text == nil or IsSecret(text) then return "" end
    local ok, result = pcall(function()
        local s = tostring(text)
        s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|\n\r]", "")
        if maxLength and #s > maxLength then s = s:sub(1, maxLength) end
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
local function GetCustomSpell()
    EnsureDB()
    local value = Trim(Sanitize(AP_DB.spotlight.customSpell, 60))
    if value == "" then return nil end
    return value
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
local CUSTOM_SOUNDS = {
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\LOLAzir1.ogg",
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\LOLAzir2.ogg",
    "Interface\\AddOns\\AzerothParallel\\Media\\sounds\\LOLAzir3.ogg",
}

local function PlaySpotSound(kind)
    EnsureDB()
    if not AP_DB.spotlight.sound then return end

    -- 优先随机播放自定义音效；老客户端没有 PlaySoundFile 时才退回内置音
    if type(PlaySoundFile) == "function" and #CUSTOM_SOUNDS > 0 then
        local index = AP_DB.spotlight.soundIndex or 0
        local path
        if index >= 1 and index <= #CUSTOM_SOUNDS then
            path = CUSTOM_SOUNDS[index] -- 玩家自己选的固定音效
        else
            path = CUSTOM_SOUNDS[math.random(#CUSTOM_SOUNDS)] -- 随机
        end
        -- 新版带声道参数，老版没有；失败也保持自定义音，避免和内置音叠在一起
        if not pcall(PlaySoundFile, path, "Master") then
            pcall(PlaySoundFile, path)
        end
        return
    end

    local id
    if kind == "EPIC" then id = SoundKitID("UI_EPICLOOT_TOAST") end
    id = id or SoundKitID("LEVEL_UP") or 888 -- 888 是升级音最常见的 ID，作为最后兜底
    if type(PlaySound) ~= "function" then return end
    -- 新版 PlaySound 第二个参数是声道，老版没有；失败就退回单参数
    if not pcall(PlaySound, id, "Master") then
        pcall(PlaySound, id)
    end
end

-- ==========================================
-- 4. 特效层：一个可复用的 Frame + 贴图 + 动画
-- ==========================================
local spot = CreateFrame("Frame", "AP_SpotlightFrame", UIParent, "BackdropTemplate")
spot:SetSize(520, 180)
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
        spot:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -230)
    else
        spot:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -230)
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
glow:SetSize(190, 190)
glow:SetPoint("LEFT", spot, "LEFT", 42, 0)
glow:SetVertexColor(0.83, 0.69, 0.22, 0.8)

-- 头像本体：用 SetPortraitTexture 临时“拍”一张当前角色头像，不依赖外部图片
local portrait = spot:CreateTexture(nil, "ARTWORK")
portrait:SetSize(110, 110)
portrait:SetPoint("LEFT", spot, "LEFT", 30, 0)
pcall(portrait.SetMaskTexture, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

-- 自定义立绘：叠在头像上面。图片文件不存在时只会透出下面的头像，不会变成空白。
-- 必须是 .tga / .blp；PNG 不会被加载。尺寸与头像一致，保持 110×110。
local portraitImage = spot:CreateTexture(nil, "ARTWORK")
portraitImage:SetSize(110, 110)
portraitImage:SetPoint("LEFT", spot, "LEFT", 30, 0)
portraitImage:Hide()

-- 四角星闪光：旋转 + 淡出，放在头像右上角
local spark = spot:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\Cooldown\\star4")
spark:SetBlendMode("ADD")
spark:SetSize(70, 70)
spark:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 16, 18)
spark:SetVertexColor(1, 0.95, 0.7, 1)

-- 大字：第一行名字，第二行技能短名（技能名用职业色）
local mainText = spot:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
mainText:SetPoint("TOPLEFT", spot, "TOPLEFT", 170, -40)
mainText:SetWidth(325)
mainText:SetJustifyH("CENTER")
mainText:SetFont(mainText:GetFont(), 24, "OUTLINE")
mainText:SetSpacing(8)
mainText:SetText("")

-- 底部小字：装饰用，告诉屏幕前的你“这是高光时刻”
local subText = spot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subText:SetPoint("BOTTOM", spot, "BOTTOM", 92, 20)
subText:SetFont(subText:GetFont(), 12, "OUTLINE")
subText:SetText("|cff888888—— 高 光 时 刻 ——|r")

-- 速度线：纯色细条，每条约自己宽度向左滑动并淡出。
-- 不用旋转贴图（WoW 的纯色纹理旋转后看不出形状），改用“多条错位细线”制造速度感。
local streakLines, streakGroups = {}, {}
for i = 1, 9 do
    local line = spot:CreateTexture(nil, "BORDER")
    line:SetHeight((i % 3 == 0) and 3 or 2)
    local width = 70 + (i * 37) % 170
    line:SetWidth(width)
    line:SetPoint("TOPLEFT", spot, "TOPLEFT", 40 + (i * 53) % 280, -16 - (i - 1) * 17)
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
local function ShowHighlight(name, label, classToken, unitToken, soundKind, imagePath)
    EnsureDB()
    if not AP_DB.spotlight.enabled then return end
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
    PlaySpotSound(soundKind)

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
-- 想整体挪位置只改 REMOTE_SLOT_BASE_Y；想改大小只改宽高和间距。
local REMOTE_SLOTS = 5
local REMOTE_SLOT_WIDTH = 320
local REMOTE_SLOT_HEIGHT = 88
local REMOTE_SLOT_GAP = 8
local REMOTE_SLOT_BASE_Y = -430 -- 主特写（180 高）下沿再往下留一点

local remoteSlots = {}
for i = 1, REMOTE_SLOTS do
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(REMOTE_SLOT_WIDTH, REMOTE_SLOT_HEIGHT)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20,
        REMOTE_SLOT_BASE_Y - (i - 1) * (REMOTE_SLOT_HEIGHT + REMOTE_SLOT_GAP))
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
    portrait:SetSize(64, 64)
    portrait:SetPoint("LEFT", f, "LEFT", 14, 0)
    pcall(portrait.SetMaskTexture, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 90, -16)
    text:SetWidth(REMOTE_SLOT_WIDTH - 104)
    text:SetJustifyH("LEFT")
    text:SetSpacing(4)
    text:SetFont(text:GetFont(), 15, "OUTLINE")

    remoteSlots[i] = {
        frame = f,
        accent = accent,
        portrait = portrait,
        text = text,
        expireAt = 0,
        token = 0,
    }
end

-- 显示一条远程高光：先找空槽，5 个全满就复用最早到期的那个
local function ShowRemoteHighlight(name, label, classToken, unitToken)
    EnsureDB()
    if not AP_DB.spotlight.enabled then return end
    -- 组队限制由 OnAddonMessage 入口处理；调试接口 /run 仍可直接调用

    name = Sanitize(name, 40)
    label = Sanitize(label, 20)
    if name == "" or label == "" then return end

    local color = ClassColor(classToken)
    local now = Now()

    local slot
    for i = 1, REMOTE_SLOTS do
        if not remoteSlots[i].frame:IsShown() then
            slot = remoteSlots[i]
            break
        end
    end
    if not slot then
        slot = remoteSlots[1]
        for i = 2, REMOTE_SLOTS do
            if remoteSlots[i].expireAt < slot.expireAt then slot = remoteSlots[i] end
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
    if not AP_DB.spotlight.enabled then return end
    -- 勾选“只在组队/团队中触发”后，单人状态直接跳过
    if AP_DB.spotlight.groupOnly and not IsInGroupNow() then return end
    if type(prefix) ~= "string" or IsSecret(prefix) or prefix ~= PREFIX then return end
    if type(message) ~= "string" or IsSecret(message) then return end

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

-- 本地触发的默认间隔（秒）：防止月火术这类高频技能每次都弹高光。
-- 想改长短只改这一个数；设为 0 表示不限制。试放按钮不受这个限制。
local TRIGGER_COOLDOWN = 60
local lastTriggerAt = 0

-- 调试日志：默认关闭。游戏里输入 /AP spotlog 可开关。
-- 用来确认“到底有没有收到施法事件、事件里的技能 ID 和名字是什么”。
local debugEnabled = false
local function DebugPrint(text)
    if not debugEnabled then return end
    print("|cffffd700[高光调试]|r " .. tostring(text))
end

-- 按设置喊话或做表情。只在本机真正施放时调用，试放和接收队友消息都不喊。
local function DoSpotChat()
    EnsureDB()
    local mode = AP_DB.spotlight.chatMode
    if mode ~= "YELL" and mode ~= "EMOTE" then return end
    local text = Trim(Sanitize(AP_DB.spotlight.chatText, 120))
    if text == "" then return end
    if type(SendChatMessage) ~= "function" then return end
    pcall(SendChatMessage, text, mode == "EMOTE" and "EMOTE" or "YELL")
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

    if debugEnabled then
        DebugPrint("收到施法：spellID=" .. tostring(spellID)
            .. "，事件名=" .. tostring(eventName)
            .. "，查询名=" .. tostring(FetchSpellName(spellID)))
    end

    EnsureDB()
    if not AP_DB.spotlight.enabled then return end
    -- 勾选“只在组队/团队中触发”后，单人状态直接跳过
    if AP_DB.spotlight.groupOnly and not IsInGroupNow() then return end

    local classToken = CurrentClass()
    if not classToken then return end

    local now = Now()
    local custom = GetCustomSpell()
    local info

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

    -- 默认触发间隔：60 秒内只弹一次，避免高频技能刷屏
    if TRIGGER_COOLDOWN > 0 and lastTriggerAt > 0
        and now - lastTriggerAt < TRIGGER_COOLDOWN then
        if debugEnabled then
            DebugPrint("触发间隔中，剩余约 "
                .. math.ceil(TRIGGER_COOLDOWN - (now - lastTriggerAt)) .. " 秒")
        end
        return
    end

    -- 同一技能 3 秒内只弹一次；全局 0.5 秒内只弹一次（防止连按多个技能时叠在一起）
    local key = spellID or info.id or info.label
    if lastCastAt[key] and now - lastCastAt[key] < 3 then return end
    if now - lastShowAt < 0.5 then return end
    lastCastAt[key] = now
    lastShowAt = now
    lastTriggerAt = now

    -- 高光大字优先用当前流派的专属称呼；广播发的也是这个称呼，队友看到的是你流派的说法
    local displayLabel = ResolveFactionAlias(info.official, info.label)
    -- 本机按技能 ID 找立绘；远程队友不会加载你的图片文件，所以不加进广播
    local imagePath = info.id and PORTRAIT_IMAGES[info.id]
    ShowHighlight(GetDisplayName(), displayLabel, classToken, "player", info.sound, imagePath)
    BroadcastHighlight(classToken, displayLabel)
    DoSpotChat()
end)

-- ==========================================
-- 8. 设置页（第 4 个 Tab：高光特写）
-- ==========================================
-- 先占个名字，面板创建成功后再换成真正的刷新函数（供 /AP 调试和以后扩展调用）
local RefreshSkillList = function() end

local panel = AP_Panels and AP_Panels[4]
if panel and panel.LeftPage and panel.RightPage then
    local left, right = panel.LeftPage, panel.RightPage

    local title = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -30)
    title:SetFont(title:GetFont(), 24, "OUTLINE")
    title:SetText("高光特写")

    local intro = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    intro:SetWidth(340)
    intro:SetJustifyH("LEFT")
    intro:SetSpacing(4)
    intro:SetText("|cffaaaaaa核心爆发技能成功施放时，在屏幕角落切入你的专属特写。\n低等级角色请用下方“自定义大招”指定一个自己会的技能。|r")

    -- 三个开关：启用、音效、广播
    local options = {
        { key = "enabled",   text = "启用技能高光" },
        { key = "sound",     text = "播放高光音效" },
        { key = "broadcast", text = "广播给队友（对方需装插件）" },
    }
    for i, option in ipairs(options) do
        local cb = CreateFrame("CheckButton", "AP_SpotlightCB" .. i, left, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -120 - (i - 1) * 42)
        local label = _G[cb:GetName() .. "Text"]
        if label then
            label:SetText(option.text)
            label:SetFont(label:GetFont(), 18, "OUTLINE")
        end
        cb:SetChecked(AP_DB.spotlight[option.key])
        cb:SetScript("OnClick", function(self)
            AP_DB.spotlight[option.key] = self:GetChecked() and true or false
        end)
    end

    -- ---- 本地音效选择：只影响自己听到的声音 ----
    local soundNames = { "随机", "LOLAzir1", "LOLAzir2", "LOLAzir3" }
    local soundBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    soundBtn:SetSize(130, 24)
    soundBtn:SetPoint("TOPLEFT", left, "TOPLEFT", 200, -164)
    local function SoundButtonText()
        local index = AP_DB.spotlight.soundIndex or 0
        return "音效：" .. (soundNames[index + 1] or "随机")
    end
    soundBtn:SetText(SoundButtonText())
    soundBtn:SetScript("OnClick", function(self)
        local index = (AP_DB.spotlight.soundIndex or 0) + 1
        if index > #CUSTOM_SOUNDS then index = 0 end
        AP_DB.spotlight.soundIndex = index
        self:SetText(SoundButtonText())
        -- 切换时立刻试听一次，方便确认选的是哪个文件
        if AP_DB.spotlight.sound then PlaySpotSound("EPIC") end
    end)
    soundBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("本地高光音效", 1, 0.82, 0.2)
        GameTooltip:AddLine("文件放在 AzerothParallel\\Media\\sounds\\ 下", 1, 1, 1)
        GameTooltip:AddLine("LOLAzir1.ogg / LOLAzir2.ogg / LOLAzir3.ogg", 1, 1, 1)
        GameTooltip:AddLine("只影响你自己听到的声音", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    soundBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---- 自定义大招：整个插件只允许设一个 ----
    -- 用户可以填技能名（支持包含匹配，比如填“化身”就能命中“化身：艾露恩之眷”），
    -- 也可以填纯数字的技能 ID。留空则回到上面那套默认职业表。
    local RefreshCustomStatus -- 先声明，下面的控件回调里会用到

    local customLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLabel:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -246)
    customLabel:SetFont(customLabel:GetFont(), 15, "OUTLINE")
    customLabel:SetText("自定义大招（填技能名或 ID，只设一个）")

    local customInput = CreateFrame("EditBox", nil, left, "BackdropTemplate")
    customInput:SetSize(178, 28)
    customInput:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -270)
    customInput:SetFontObject("GameFontNormal")
    customInput:SetTextColor(1, 0.9, 0.65)
    customInput:SetTextInsets(6, 6, 0, 0)
    customInput:SetAutoFocus(false)
    customInput:SetMaxLetters(60)
    customInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    customInput:SetBackdropColor(0, 0, 0, 0.95)
    customInput:SetBackdropBorderColor(0.83, 0.69, 0.22, 1)
    customInput:SetText(AP_DB.spotlight.customSpell or "")

    local saveBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    saveBtn:SetSize(62, 26)
    saveBtn:SetPoint("LEFT", customInput, "RIGHT", 6, 0)
    saveBtn:SetText("保存")

    local clearBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    clearBtn:SetSize(58, 26)
    clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    clearBtn:SetText("清空")

    local statusText = left:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", customInput, "BOTTOMLEFT", 0, -8)
    statusText:SetWidth(340)
    statusText:SetJustifyH("LEFT")
    statusText:SetFont(statusText:GetFont(), 13, "OUTLINE")

    -- 把输入框内容写进存档（输入为空就是清除自定义，恢复默认表）
    local function SaveCustomSpell(text)
        local value = Trim(Sanitize(text or "", 60))
        AP_DB.spotlight.customSpell = value
        customInput:SetText(value)
        if RefreshCustomStatus then RefreshCustomStatus() end
    end
    saveBtn:SetScript("OnClick", function() SaveCustomSpell(customInput:GetText()) end)
    clearBtn:SetScript("OnClick", function() SaveCustomSpell("") end)
    customInput:SetScript("OnEnterPressed", function(self)
        SaveCustomSpell(self:GetText())
        self:ClearFocus()
    end)

    -- ---- 触发时喊话（可选）----
    local chatLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -336)
    chatLabel:SetFont(chatLabel:GetFont(), 15, "OUTLINE")
    chatLabel:SetText("触发时喊话（留空则关闭）")

    local chatInput = CreateFrame("EditBox", nil, left, "BackdropTemplate")
    chatInput:SetSize(198, 28)
    chatInput:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -360)
    chatInput:SetFontObject("GameFontNormal")
    chatInput:SetTextColor(1, 0.9, 0.65)
    chatInput:SetTextInsets(6, 6, 0, 0)
    chatInput:SetAutoFocus(false)
    chatInput:SetMaxLetters(120)
    chatInput:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    chatInput:SetBackdropColor(0, 0, 0, 0.95)
    chatInput:SetBackdropBorderColor(0.83, 0.69, 0.22, 1)
    chatInput:SetText(AP_DB.spotlight.chatText or "")

    local chatModeBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    chatModeBtn:SetSize(128, 26)
    chatModeBtn:SetPoint("LEFT", chatInput, "RIGHT", 8, 0)

    local function ChatModeLabel()
        local mode = AP_DB.spotlight.chatMode
        if mode == "YELL" then return "模式：大喊" end
        if mode == "EMOTE" then return "模式：表情" end
        return "模式：关闭"
    end
    chatModeBtn:SetText(ChatModeLabel())
    chatModeBtn:SetScript("OnClick", function(self)
        local mode = AP_DB.spotlight.chatMode
        if mode == "YELL" then
            AP_DB.spotlight.chatMode = "EMOTE"
        elseif mode == "EMOTE" then
            AP_DB.spotlight.chatMode = "OFF"
        else
            AP_DB.spotlight.chatMode = "YELL"
        end
        self:SetText(ChatModeLabel())
    end)

    local function SaveChatText()
        local value = Trim(Sanitize(chatInput:GetText() or "", 120))
        AP_DB.spotlight.chatText = value
        chatInput:SetText(value)
    end
    chatInput:SetScript("OnEnterPressed", function(self)
        SaveChatText()
        self:ClearFocus()
    end)
    chatInput:SetScript("OnEditFocusLost", SaveChatText)

    local chatHint = left:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatHint:SetPoint("TOPLEFT", chatInput, "BOTTOMLEFT", 0, -4)
    chatHint:SetFont(chatHint:GetFont(), 12, "OUTLINE")
    chatHint:SetText("|cff888888大喊对周围玩家可见；表情以 /e 动作发送|r")

    -- ---- 只在组队/团队中触发 ----
    local groupOnly = CreateFrame("CheckButton", "AP_SpotlightGroupOnly", left, "ChatConfigCheckButtonTemplate")
    groupOnly:SetPoint("TOPLEFT", left, "TOPLEFT", 30, -418)
    local groupLabel = _G[groupOnly:GetName() .. "Text"]
    if groupLabel then
        groupLabel:SetText("只在组队 / 团队中触发")
        groupLabel:SetFont(groupLabel:GetFont(), 16, "OUTLINE")
    end
    groupOnly:SetChecked(AP_DB.spotlight.groupOnly)
    groupOnly:SetScript("OnClick", function(self)
        AP_DB.spotlight.groupOnly = self:GetChecked() and true or false
    end)

    -- 试放按钮：不用真进战斗，点一下就能看特效（不会喊话）
    local previewBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
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
        -- 试放也走同一个称谓替换和立绘配置，方便直接核对
        local displayLabel = ResolveFactionAlias(official, label)
        ShowHighlight(GetDisplayName(), displayLabel, classToken, "player", "EPIC",
            previewID and PORTRAIT_IMAGES[previewID])
    end)

    -- 位置切换：右上 / 左上
    local posBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    posBtn:SetSize(140, 28)
    posBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 192, 21)
    posBtn:SetText(AP_DB.spotlight.position == "TOPLEFT" and "位置：左上" or "位置：右上")
    posBtn:SetScript("OnClick", function(self)
        AP_DB.spotlight.position = (AP_DB.spotlight.position == "TOPLEFT") and "TOPRIGHT" or "TOPLEFT"
        ApplyPosition()
        self:SetText(AP_DB.spotlight.position == "TOPLEFT" and "位置：左上" or "位置：右上")
    end)

    -- 右页：本职业的触发技能清单（只读）
    local rightTitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    rightTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -30)
    rightTitle:SetFont(rightTitle:GetFont(), 22, "OUTLINE")
    rightTitle:SetText("本职业触发技能")

    local hint = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -10)
    hint:SetFont(hint:GetFont(), 13, "OUTLINE")
    hint:SetText("|cff888888左页可自定义只触发一个大招；留空则用默认表|r")

    local listText = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listText:SetPoint("TOPLEFT", right, "TOPLEFT", 30, -105)
    listText:SetWidth(340)
    listText:SetJustifyH("LEFT")
    listText:SetSpacing(7)
    listText:SetFont(listText:GetFont(), 16, "")

    RefreshSkillList = function()
        -- 自定义大招优先：开了自定义就只显示这一条，避免玩家以为默认表也在生效
        local custom = GetCustomSpell()
        if custom then
            listText:SetText("|cffd4af37自定义大招已启用|r\n\n只会响应这一个技能：\n|cffffffff"
                .. custom .. "|r\n\n|cff888888在左页输入框留空并保存，可恢复默认职业表。|r")
            return
        end

        local classToken = CurrentClass()
        local list = SPELL_DATA[classToken] or {}
        local lines, seen = {}, {}
        for _, info in ipairs(list) do
            if not seen[info.label] then
                seen[info.label] = true
                table.insert(lines, "|cffd4af37•|r " .. info.label
                    .. "  |cff888888" .. (info.official or tostring(info.id)) .. "|r")
            end
        end
        if #lines == 0 then
            listText:SetText("|cff888888当前职业还没有配置高光技能。|r")
        else
            listText:SetText(table.concat(lines, "\n"))
        end
    end

    -- 刷新“自定义大招”的状态文字，同时刷新右页清单
    RefreshCustomStatus = function()
        local custom = GetCustomSpell()
        if custom then
            statusText:SetText("|cffd4af37当前：" .. custom .. "|r  |cff888888（只认这一个技能）|r")
        else
            statusText:SetText("|cff888888未设置，使用本职业默认表。|r")
        end
        RefreshSkillList()
    end
    RefreshCustomStatus()

    -- 职业切换后（比如小号），打开面板时刷新一次清单
    local refreshFrame = CreateFrame("Frame")
    SafeRegister(refreshFrame, "PLAYER_LOGIN")
    refreshFrame:SetScript("OnEvent", RefreshSkillList)
end

-- ==========================================
-- 9. 对外接口（方便调试和以后扩展）
-- ==========================================
AP_Spotlight = {
    Show = ShowHighlight,
    -- 调试用：/run AP_Spotlight.ShowRemote("名字", "技能", "DRUID")
    -- 连续执行 5 次可以检查 1~5 号槽位是否互不重叠
    ShowRemote = ShowRemoteHighlight,
    RefreshList = RefreshSkillList,
    -- /AP spotlog 会调用这个开关；只影响聊天框里的调试输出，不影响正常触发
    ToggleDebug = function()
        debugEnabled = not debugEnabled
        print("|cffffd700[AP]|r 高光调试日志：" .. (debugEnabled and "已开启" or "已关闭"))
    end,
}
