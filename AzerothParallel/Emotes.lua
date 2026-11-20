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

-- ---------- 可调参数 ----------
local COLUMNS = 5     -- 每行几个图标（基础 8 个 + 自定义 2 个 = 10 个，正好两行）
local BTN_SIZE = 44   -- 图标大小
local BTN_GAP = 6     -- 图标间距
local PAD = 14        -- 面板内边距
local GLOBAL_CD = 1.5 -- 点一次后所有按钮冷却几秒，防止刷屏
local PANEL_TITLE = "表情与动作"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CUSTOM_COUNT = 2 -- 末尾固定保留两个「自定义」按钮（内容在设定页里填）

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
}

-- ---------- 基础动作列表（固定 8 个） ----------
-- emote = "TOKEN"        -> 调用游戏内置表情（等同于输入 /joke /dance 等）
-- lines = { ... }        -> 说话用的句子；pick = true 时弹出列表让玩家自己挑
-- icon 都是 Interface\Icons 下的图标，哪个显示成绿块/问号就换一个名字
local EMOTES = {
    {
        name = "讲笑话",
        desc = "做出「讲笑话」的表情，角色会自己说一句。",
        emote = "JOKE",
        icon = "Interface\\Icons\\Spell_Nature_Polymorph"
    },
    {
        name = "要说的话",
        desc = "点开话术列表，挑一句在说话频道说出来。",
        lines = PHRASES,
        pick = true, -- 关键：不随机说，而是先弹出「一览」让玩家自己挑
        icon = "Interface\\Icons\\INV_Misc_Note_01"
    },
    {
        name = "大笑",
        desc = "哈哈哈哈哈！",
        emote = "LAUGH",
        icon = "Interface\\Icons\\INV_Misc_Mask_01"
    },
    {
        name = "跳舞",
        desc = "来一段即兴舞蹈。",
        emote = "DANCE",
        icon = "Interface\\Icons\\INV_Misc_Drum_01"
    },
    {
        name = "欢呼",
        desc = "大声欢呼！",
        emote = "CHEER",
        icon = "Interface\\Icons\\Ability_Warrior_RallyingCry"
    },
    {
        name = "秀肌肉",
        desc = "展示你结实的肱二头肌。",
        emote = "FLEX",
        icon = "Interface\\Icons\\Spell_Nature_Strength"
    },
    {
        name = "飞吻",
        desc = "向目标送出一个飞吻。",
        emote = "BLOWKISS",
        icon = "Interface\\Icons\\INV_ValentinesCandy"
    },
    {
        name = "咆哮",
        desc = "仰天长啸。",
        emote = "ROAR",
        icon = "Interface\\Icons\\Ability_Druid_DemoralizingRoar"
    },
}

-- 两个自定义按钮的默认图标（想让它们更好认，可以换成别的图标名字）
local CUSTOM_ICONS = {
    "Interface\\Icons\\INV_Misc_Note_02",
    "Interface\\Icons\\INV_Misc_Note_03",
}

-- 读取（必要时先建立）第 i 个自定义槽的存档。
-- 存档长这样：AP_DB.emote.custom[1] = { name = "打个招呼", text = "你好呀。" }
local function GetCustomConfig(i)
    local db = EnsureEmoteDB()
    db.custom = db.custom or {}
    db.custom[i] = db.custom[i] or {}
    return db.custom[i]
end

-- 把「基础 8 个 + 自定义 2 个」拼成当前要显示的完整列表。
-- 每次调用都重新读存档，所以设定页里一保存，按钮提示就会立刻更新。
local function GetEntries()
    local list = {}
    for i = 1, #EMOTES do
        list[i] = EMOTES[i]
    end

    for i = 1, CUSTOM_COUNT do
        local cfg = GetCustomConfig(i)
        local name = cfg.name
        if not name or name == "" then name = "自定义 " .. i end

        local desc
        if cfg.text and cfg.text ~= "" then
            desc = "说：" .. cfg.text
        else
            desc = "还没有设置内容，请到「设定 → 表情与动作」里填写。"
        end

        list[#list + 1] = {
            name = name,
            desc = desc,
            text = cfg.text,
            customSlot = i, -- 记下这是第几个自定义槽，点击时用来判断有没有填内容
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

local function Perform(entry)
    if entry.emote then
        -- 有友方玩家目标时，表情会带上目标（比如对着某人飞吻）
        pcall(DoEmote, entry.emote, FriendlyTargetUnit())
    elseif entry.text and entry.text ~= "" then
        -- 自定义按钮：直接说出玩家在设定页里写的那句话
        SendChatMessage(entry.text, "SAY")
    elseif entry.lines and #entry.lines > 0 then
        -- 兜底：随机挑一句，并且不和上一句重复（「要说的话」实际走的是选择列表）
        local n = #entry.lines
        local i = math.random(n)
        if n > 1 and i == entry.lastIndex then i = (i % n) + 1 end
        entry.lastIndex = i
        SendChatMessage(entry.lines[i], entry.channel or "SAY")
    end
end

-- ==========================================
-- 界面
-- ==========================================
local UI = {}
AP_EmoteUI = UI

local rows = math.ceil((#EMOTES + CUSTOM_COUNT) / COLUMNS) -- 总格数 = 基础 8 + 自定义 2
local gridW = COLUMNS * BTN_SIZE + (COLUMNS - 1) * BTN_GAP
local gridH = rows * BTN_SIZE + (rows - 1) * BTN_GAP
local TITLE_AREA = 34

local frame = CreateFrame("Frame", "AP_EmoteFrame", UIParent, "BackdropTemplate")
frame:SetSize(gridW + PAD * 2, gridH + PAD * 2 + TITLE_AREA - 8)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
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
frame:Hide()
UI.frame = frame

-- 位置：读取上次保存的，没有就放在屏幕中间偏右
local function RestorePosition()
    frame:ClearAllPoints()
    local pos = EnsureEmoteDB().pos
    if pos and pos[1] then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
end
RestorePosition()

-- 移动方式：必须按住 Shift 再拖动，避免平时点来点去把面板拖跑。
-- 名牌、属性条、标题牌也会被加进同一套拖动逻辑（见下面 MakeDragHandle）。
local function StopAndSavePosition()
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    EnsureEmoteDB().pos = { point, relPoint, x, y }
end

local function StartShiftMove()
    if IsShiftKeyDown() then
        frame:StartMoving()
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
title:SetSize(gridW + PAD * 2 - 36, 26)
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
titleText:SetFont(titleText:GetFont(), 15, "OUTLINE")
titleText:SetTextColor(1, 0.85, 0.3)
MakeDragHandle(title)

-- ==========================================
-- 顶部名牌：RP 名 + 当前职业流派
-- 第一行是「职业流派」里设置的名字（如：珀耳塞福涅·黑檀），
-- 第二行是当前流派名（如：<夜爪德鲁伊>），并染上该流派的主题色。
-- ==========================================
local nameplate = CreateFrame("Frame", nil, frame, "BackdropTemplate")
nameplate:SetSize(frame:GetWidth(), 54)
-- 向上抬高：先给下面的属性条留出位置（属性条高 50 + 间隔 6）
nameplate:SetPoint("BOTTOM", frame, "TOP", 0, 78)
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
plateName:SetWidth(frame:GetWidth() - 16)
plateName:SetJustifyH("CENTER")
plateName:SetFont(plateName:GetFont(), 18, "OUTLINE")
plateName:SetTextColor(1, 0.85, 0.3)

local plateFaction = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
plateFaction:SetPoint("TOP", plateName, "BOTTOM", 0, -1)
plateFaction:SetWidth(frame:GetWidth() - 16)
plateFaction:SetJustifyH("CENTER")
plateFaction:SetFont(plateFaction:GetFont(), 13, "")

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

    -- 第二行：当前职业流派名 + 颜色
    local factionName, color
    local classData = AP_FlavorData and AP_FlavorData[flavor.currentClass]
    if classData then
        for _, f in ipairs(classData.factions or {}) do
            if f.id == flavor.currentFaction then
                factionName = f.name
                color = f.themeColor or f.color
                break
            end
        end
        -- 存档里的流派对不上时，退回本职业的第一个流派
        if not factionName then
            local first = (classData.factions or {})[1]
            if first then
                factionName = first.name
                color = first.themeColor or first.color
            end
        end
        color = color or classData.classColor
        factionName = factionName or classData.className
    end

    if not factionName then factionName = "冒险者" end
    if not color then color = { r = 1, g = 0.85, b = 0.3 } end

    plateName:SetText(rpName)
    plateFaction:SetText("<" .. factionName .. ">")
    plateFaction:SetTextColor(color.r, color.g, color.b)
end

-- 每次面板显示时都刷新一遍：在职业流派页改名或转投后，下次打开就是新的
frame:HookScript("OnShow", UpdateNameplate)

-- ==========================================
-- 属性条：力量 / 敏捷 / 智力 / 精神 / 回蓝 / 护甲 / 耐久
-- 夹在名牌和「表情与动作」标题之间，打开面板时立刻读数，之后每秒刷新。
-- ==========================================
local statsBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
statsBar:SetSize(frame:GetWidth(), 50)
-- 标题牌顶端在面板上方 12 像素，这里再留 10 像素间隙
statsBar:SetPoint("BOTTOM", frame, "TOP", 0, 22)
statsBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
statsBar:SetBackdropColor(0.07, 0.07, 0.08, 0.96)
statsBar:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
MakeDragHandle(statsBar)

-- 新客户端会把部分数值标记成 secret（不能读取、比较或运算）。
-- 这里统一过滤：拿不到就显示「—」，避免刷报错。
local function SafeNum(value)
    if value == nil then return nil end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then return nil end
    end
    if type(value) ~= "number" then return nil end
    return value
end

local function ReadStat(index)
    local ok, value = pcall(UnitStat, "player", index)
    if not ok then return nil end
    return SafeNum(value)
end

-- 已装备物品的耐久度平均值（戒指、饰品这类没有耐久的会自动跳过）
local function GetDurabilityPercent()
    local total, count = 0, 0
    for slot = 1, 19 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok then
            cur, max = SafeNum(cur), SafeNum(max)
            if cur and max and max > 0 then
                total = total + (cur / max)
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
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
local STAT_INNER = 4
local statCellW = (frame:GetWidth() - STAT_INNER * 2) / #STAT_DEFS

for i, def in ipairs(STAT_DEFS) do
    local cell = CreateFrame("Button", nil, statsBar)
    cell:SetSize(statCellW, 42)
    cell:SetPoint("TOPLEFT", statsBar, "TOPLEFT", STAT_INNER + (i - 1) * statCellW, -4)

    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", cell, "TOP", 0, 0)
    label:SetWidth(statCellW - 2)
    label:SetJustifyH("CENTER")
    label:SetFont(label:GetFont(), 11, "")
    label:SetTextColor(0.65, 0.65, 0.7)
    label:SetText(def.label)

    local value = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOP", label, "BOTTOM", 0, -3)
    value:SetWidth(statCellW - 2)
    value:SetJustifyH("CENTER")
    value:SetFont(value:GetFont(), 12, "OUTLINE")
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

local function UpdateStats()
    local function Int(value)
        if not value then return "—" end
        return tostring(math.floor(value + 0.5))
    end

    statValues.str:SetText(Int(ReadStat(1)))
    statValues.agi:SetText(Int(ReadStat(2)))
    statValues.int:SetText(Int(ReadStat(4)))
    statValues.spi:SetText(Int(ReadStat(5)))

    -- 回蓝：GetManaRegen 返回每秒回复量，保留一位小数
    local okRegen, regen = pcall(GetManaRegen)
    regen = okRegen and SafeNum(regen) or nil
    statValues.mana:SetText(regen and string.format("%.1f", regen) or "—")

    -- 护甲：UnitArmor 的第二个返回值是当前有效护甲
    local okArmor, baseArmor, effectiveArmor = pcall(UnitArmor, "player")
    local armor = okArmor and SafeNum(effectiveArmor or baseArmor) or nil
    statValues.armor:SetText(Int(armor))

    local dura = GetDurabilityPercent()
    statValues.dura:SetText(dura and string.format("%.0f%%", dura) or "—")
end

-- 面板每次显示时立刻刷新
frame:HookScript("OnShow", UpdateStats)

-- 面板开着的时候每秒刷新一次：换装备、上 buff、掉耐久都能及时反映
local statElapsed = 0
statsBar:SetScript("OnUpdate", function(_, elapsed)
    statElapsed = statElapsed + elapsed
    if statElapsed < 1 then return end
    statElapsed = 0
    UpdateStats()
end)

-- 关闭按钮（右上角小叉）
local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
close:SetScale(0.75)

-- ESC 关闭
tinsert(UISpecialFrames, "AP_EmoteFrame")

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
        self:SetBackdropBorderColor(0.9, 0.72, 0.28, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(now.name, 1, 0.85, 0.3)
        if now.desc then GameTooltip:AddLine(now.desc, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if GetTime() - lastUse < GLOBAL_CD then return end
        local now = GetEntries()[i]
        if not now then return end

        -- 「要说的话」：先弹出列表，选完那一句才算真正使用
        if now.pick then
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
            print("|cffffd700[AP]|r 自定义 " .. now.customSlot ..
                " 还没有内容，请打开 /AP →「设定」→「表情与动作」填写。")
            return
        end

        StartCooldown()
        Perform(now)
    end)

    buttons[i] = btn
end

-- ==========================================
-- 「要说的话」选择列表（点第 2 个按钮时弹出）
-- ==========================================
local PICKER_W = 360
local PICKER_ROW_H = 24
local PICKER_LIST_TOP = 44 -- 顶部标题占掉的高度

picker = CreateFrame("Frame", "AP_EmotePicker", frame, "BackdropTemplate")
picker:SetSize(PICKER_W, 120)
picker:SetFrameStrata("DIALOG")
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
pickerTitle:SetFont(pickerTitle:GetFont(), 14, "OUTLINE")
pickerTitle:SetTextColor(1, 0.85, 0.3)

local pickerClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
pickerClose:SetPoint("TOPRIGHT", picker, "TOPRIGHT", 1, 1)
pickerClose:SetScale(0.7)

-- 列表里的每一行都是按钮，第一次用到时才创建，之后反复复用
local pickerRows = {}

function UI.OpenPicker(entry)
    local lines = entry.lines or {}

    -- 高度 = 顶部标题 + 每句一行 + 底部留白
    picker:SetHeight(PICKER_LIST_TOP + #lines * PICKER_ROW_H + 10)

    for i = 1, #lines do
        local lineBtn = pickerRows[i]
        if not lineBtn then
            lineBtn = CreateFrame("Button", nil, picker, "BackdropTemplate")
            lineBtn:SetHeight(PICKER_ROW_H - 2)
            lineBtn:SetPoint("TOPLEFT", picker, "TOPLEFT", 10, -(PICKER_LIST_TOP + (i - 1) * PICKER_ROW_H))
            lineBtn:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -10, -(PICKER_LIST_TOP + (i - 1) * PICKER_ROW_H))
            lineBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            lineBtn:SetBackdropColor(0.12, 0.12, 0.14, 0.85)
            lineBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

            local text = lineBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", 8, 0)
            text:SetPoint("RIGHT", lineBtn, "RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            lineBtn.text = text

            -- 同一个按钮会被反复使用，所以点击时读 self.line，
            -- 不要直接捕获循环变量（否则每行都会说最后一句）。
            lineBtn:SetScript("OnClick", function(self)
                if self.line then UI.PickLine(self.line) end
            end)

            pickerRows[i] = lineBtn
        end

        lineBtn:Show()
        lineBtn.line = lines[i]
        lineBtn.text:SetText(lines[i])
    end

    -- 这次内容比上次少时，把多出来的旧行藏起来
    for i = #lines + 1, #pickerRows do
        pickerRows[i]:Hide()
    end

    -- 贴在表情面板左边；屏幕太窄时 SetClampedToScreen 会自动把它拉回屏幕内
    picker:ClearAllPoints()
    picker:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
    picker:Show()
end

-- 选好一句：说出来 + 所有按钮进入冷却 + 收起列表。
-- 这里不再检查冷却：点开列表再挑一句本身就已经是明确的动作了，
-- 选中后列表会立刻收起，也不存在连点刷屏的问题。
function UI.PickLine(line)
    StartCooldown()
    SendChatMessage(line, "SAY")
    picker:Hide()
end

-- 主面板收起时，选择列表也一起收起来。
-- 否则下次打开面板，上次没关的列表还会自己冒出来。
frame:HookScript("OnHide", function() picker:Hide() end)

-- ==========================================
-- 对外接口 / 斜杠命令
-- ==========================================
function UI.Show()
    UpdateNameplate()
    UpdateStats()
    frame:Show()
end

function UI.Hide() frame:Hide() end

function UI.Toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
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
    entryBtn:SetText("表情与动作")
    entryBtn:SetScript("OnClick", function()
        -- 顺便把右页切到「表情与动作」分页，下次打开设定页就能直接看到自定义栏
        if AP_SelectSettingsTab then AP_SelectSettingsTab("emote") end
        -- 这是独立浮动面板，先把书本主面板收起来，避免互相遮挡
        if AP_MainFrame and AP_MainFrame:IsShown() then AP_MainFrame:Hide() end
        UI.Show()
    end)

    -- 打开弹幕设置子页时，这个入口按钮也要一起藏起来
    if AP_RegisterSettingsEntry then AP_RegisterSettingsEntry(entryBtn) end

    -- ---------- 右侧：使用说明 + 两个自定义按钮的编辑 ----------
    -- 右页已由 Danmaku.lua 做成分页，这里挂到「表情与动作」那一页里
    local page = AP_EmoteSettingsPage or settingPanel.RightPage

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", page, "TOP", 0, -6)
    header:SetText("自定义按钮")
    header:SetFont(header:GetFont(), 20, "OUTLINE")
    header:SetTextColor(1, 0.85, 0.3)

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", header, "BOTTOM", 0, -8)
    hint:SetWidth(340)
    hint:SetJustifyH("CENTER")
    hint:SetFont(hint:GetFont(), 13, "")
    hint:SetSpacing(5)
    hint:SetTextColor(0.85, 0.85, 0.85)
    hint:SetText("左侧「表情与动作」按钮可以打开图标面板。\n在下方填写第 9、10 个按钮要说的话。")

    -- 一个自定义槽的编辑器：名称 + 要说的话 + 保存。
    -- anchor 是它上方的元素，编辑器会挂在 anchor 下面，两个槽自然排成一列。
    local function BuildCustomEditor(slot, anchor)
        local cfg = GetCustomConfig(slot)

        local block = CreateFrame("Frame", nil, page, "BackdropTemplate")
        block:SetSize(340, 118)
        block:SetPoint("TOP", anchor, "BOTTOM", 0, -12)
        block:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        block:SetBackdropColor(0, 0, 0, 0.35)
        block:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

        local label = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 12, -10)
        label:SetText("自定义 " .. slot)
        label:SetTextColor(1, 0.85, 0.3)

        -- 名称：显示在鼠标提示的标题上，留空就是「自定义 N」
        local nameBox = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
        nameBox:SetSize(170, 22)
        nameBox:SetPoint("TOPRIGHT", block, "TOPRIGHT", -12, -6)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(24)
        nameBox:SetText(cfg.name or "")
        nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

        local nameLabel = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("RIGHT", nameBox, "LEFT", -8, 0)
        nameLabel:SetText("名称")
        nameLabel:SetTextColor(0.85, 0.85, 0.85)

        local contentLabel = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        contentLabel:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -42)
        contentLabel:SetText("要说的话")
        contentLabel:SetTextColor(0.85, 0.85, 0.85)

        local textBox = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
        textBox:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -62)
        textBox:SetPoint("TOPRIGHT", block, "TOPRIGHT", -12, -62)
        textBox:SetHeight(22)
        textBox:SetAutoFocus(false)
        textBox:SetMaxLetters(120)
        textBox:SetText(cfg.text or "")
        textBox:SetScript("OnEscapePressed", textBox.ClearFocus)

        local save = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
        save:SetSize(68, 22)
        save:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -12, 10)
        save:SetText("保存")

        local status = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        status:SetPoint("RIGHT", save, "LEFT", -10, 0)
        status:SetJustifyH("RIGHT")
        status:SetTextColor(0.4, 1, 0.4)

        local function Save()
            cfg.name = strtrim(nameBox:GetText() or "")
            cfg.text = strtrim(textBox:GetText() or "")
            status:SetText("已保存")
            -- 让浮动面板里的按钮提示立刻刷新
            if UI.Refresh then UI.Refresh() end
        end

        save:SetScript("OnClick", Save)
        nameBox:SetScript("OnEnterPressed", function(self)
            Save()
            self:ClearFocus()
        end)
        textBox:SetScript("OnEnterPressed", function(self)
            Save()
            self:ClearFocus()
        end)

        return block
    end

    local firstBlock = BuildCustomEditor(1, hint)
    BuildCustomEditor(2, firstBlock)
end
