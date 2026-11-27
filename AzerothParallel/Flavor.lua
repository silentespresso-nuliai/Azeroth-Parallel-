-- ==========================================
-- Flavor.lua: 职业流派 (全职业大图鉴 & 无限制预览版)
-- ==========================================
local playerFaction = UnitFactionGroup("player")
-- 职业流派 UI 挂在第 2 个面板（对应顶部“职业流派” Tab），不是第 1 个“设定”页
local p1 = AP_Panels[2]
local LeftPage = p1.LeftPage
local RightPage = p1.RightPage

-- 强制校验数据
AP_DB.flavor = AP_DB.flavor or {}
AP_DB.flavor.rep = AP_DB.flavor.rep or {}
AP_DB.flavor.history = AP_DB.flavor.history or {}

local _, realClassToken = UnitClass("player")
AP_DB.flavor.currentClass = realClassToken
AP_DB.flavor.previewClass = AP_DB.flavor.previewClass or realClassToken

-- 是否把称谓反映到游戏内的鼠标提示（只改 tooltip 第一行，安全开关）
-- 默认开启一次；旧存档里的 false 会迁移成 true，之后尊重玩家自己的开关。
if AP_DB.flavor.aliasDefaultApplied ~= true then
    AP_DB.flavor.tooltipAlias = true
    AP_DB.flavor.aliasDefaultApplied = true
elseif AP_DB.flavor.tooltipAlias == nil then
    AP_DB.flavor.tooltipAlias = true
end

if not AP_DB.flavor.currentFaction or AP_DB.flavor.currentFaction == "" then
    AP_DB.flavor.currentFaction = "Nightclaw"
end
AP_DB.flavor.previewFaction = AP_DB.flavor.previewFaction or AP_DB.flavor.currentFaction
if not AP_DB.flavor.customName or AP_DB.flavor.customName == "" then
    AP_DB.flavor.customName = UnitName("player")
end

-- 换角色时默认回到自己的职业，避免上次预览别的职业导致“第一页不是自己”；
-- 同一个角色重载时保留上次预览的职业。
if AP_DB.flavor.lastClass ~= realClassToken then
    AP_DB.flavor.lastClass = realClassToken
    AP_DB.flavor.previewClass = realClassToken
    AP_DB.flavor.previewFaction = AP_DB.flavor.currentFaction
end

-- 数据层已经抽到 Data.lua（表名 AP_FlavorData）。
-- 这里保留同名局部引用，下面所有逻辑和 UI 代码不需要改。
local FlavorData = AP_FlavorData

-- 所有职业流派对所有角色开放；跨阵营选择会走“异类”确认，并在成长上减半。

-- 书页是浅色羊皮纸，正文要用深色“墨水”才能看清。
-- 颜色统一从 Core.lua 的 AP_Theme 取；万一 Core 还没定义，就用下面这份兜底。
local THEME = AP_Theme or {
    ink = { 0.20, 0.12, 0.06 }, inkSoft = { 0.36, 0.25, 0.14 },
    accent = { 0.55, 0.15, 0.10 }, cream = { 1, 0.95, 0.82 }, line = { 0.30, 0.20, 0.10 },
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- 是否属于“跨阵营流派”：联盟选部落流派，或部落选联盟流派。
-- 中立流派不触发异类惩罚。
local function IsCrossFaction(f)
    if not f then return false end
    if f.reqFaction == "Alliance" and playerFaction == "Horde" then return true end
    if f.reqFaction == "Horde" and playerFaction == "Alliance" then return true end
    return false
end

local function FindFaction(classData, factionID)
    if not classData or not classData.factions then return nil end
    for _, f in ipairs(classData.factions) do
        if f.id == factionID then return f end
    end
    return nil
end

-- 数据自检：保证 previewClass / currentFaction / previewFaction 都指向真实存在的数据
if not FlavorData[AP_DB.flavor.previewClass] then
    AP_DB.flavor.previewClass = FlavorData[realClassToken] and realClassToken or "DRUID"
end

do
    local ownData = FlavorData[AP_DB.flavor.currentClass]
    if ownData then
        local cur = FindFaction(ownData, AP_DB.flavor.currentFaction)
        -- 只有流派 id 失效（例如旧存档）时才回退；不再限制阵营/种族
        if not cur then
            AP_DB.flavor.currentFaction = ownData.factions[1].id
        end
    end

    -- 预览允许看所有流派；转投也不再受阵营/种族限制
    local previewClassData = FlavorData[AP_DB.flavor.previewClass]
    if previewClassData and previewClassData.factions then
        if not FindFaction(previewClassData, AP_DB.flavor.previewFaction) then
            AP_DB.flavor.previewFaction = previewClassData.factions[1].id
        end
    end
end

-- ==========================================
-- 2. 逻辑层 (Manager Layer)
-- ==========================================
local FlavorManager = {}

function FlavorManager.GetCurrentFactionData()
    local classData = FlavorData[AP_DB.flavor.currentClass]
    if not classData or not classData.factions then return nil, nil end

    return FindFaction(classData, AP_DB.flavor.currentFaction) or classData.factions[1], classData
end

function FlavorManager.GetPreviewFactionData()
    local classData = FlavorData[AP_DB.flavor.previewClass]
    if not classData or not classData.factions then return nil, classData end
    return FindFaction(classData, AP_DB.flavor.previewFaction) or classData.factions[1], classData
end

function FlavorManager.GetTierInfo(selectedData)
    if not selectedData or not selectedData.tiers then return nil, nil, 0 end
    local currentRep = AP_DB.flavor.rep[selectedData.id] or 0
    local currentTier = selectedData.tiers[1]
    local nextTier = nil
    for i, tier in ipairs(selectedData.tiers) do
        if currentRep >= (tier.exp or 0) then
            currentTier = tier
            nextTier = selectedData.tiers[i + 1]
        end
    end
    return currentTier, nextTier, currentRep
end

function FlavorManager.AddHistory(text)
    -- 和上一条完全相同时不重复记录（比如反复进出同一区域）
    if AP_DB.flavor.history[1] == text then return end
    table.insert(AP_DB.flavor.history, 1, text)
    while #AP_DB.flavor.history > 5 do table.remove(AP_DB.flavor.history) end
    if AP_FlavorUI and AP_FlavorUI.RefreshHistory then AP_FlavorUI.RefreshHistory() end
end

function FlavorManager.ConvertFaction(newFactionID)
    if newFactionID == AP_DB.flavor.currentFaction then return end
    -- 本职业下所有流派都可转投；跨阵营的减速在声望/熟练度成长时结算
    local newData = FindFaction(FlavorData[AP_DB.flavor.currentClass], newFactionID)
    if not newData then return end

    AP_DB.flavor.currentFaction = newFactionID
    AP_DB.flavor.rep[newFactionID] = 0
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd700[AP]|r 你已正式转投 " .. newData.name .. "，声望已清零。")
    UIErrorsFrame:AddMessage("你已转投 " .. newData.name, 1, 0.82, 0, 1)
    FlavorManager.AddHistory("转投了 " .. newData.name)
    if AP_FlavorUI and AP_FlavorUI.Refresh then AP_FlavorUI.Refresh() end
end

function FlavorManager.AddReputation(amount)
    local selectedData = FlavorManager.GetCurrentFactionData()
    if not selectedData then return end

    -- 异类惩罚：跨阵营流派的声望成长减半（只作用于正向收益）
    local gain = amount
    if amount > 0 and IsCrossFaction(selectedData) then
        gain = math.max(1, math.floor(amount * 0.5))
    end

    local oldTier = FlavorManager.GetTierInfo(selectedData)
    AP_DB.flavor.rep[selectedData.id] = (AP_DB.flavor.rep[selectedData.id] or 0) + gain
    local newTier = FlavorManager.GetTierInfo(selectedData)

    DEFAULT_CHAT_FRAME:AddMessage("|cff0070dd你获得了 " .. gain .. " 点 [" .. selectedData.name .. "] 声望。|r")
    local repMsg = "你获得了 " .. gain .. " 点 [" .. selectedData.name .. "] 声望"
    if AP_EmoteUI and AP_EmoteUI.Notify then
        AP_EmoteUI.Notify(repMsg, 0, 0.5, 1)
    else
        UIErrorsFrame:AddMessage(repMsg, 0, 0.5, 1, 1)
    end

    if oldTier and newTier and oldTier.level < newTier.level then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd700[AP]|r 你的 [" ..
            selectedData.name .. "] 头衔已变更为：|cffffd700" .. newTier.name .. "|r")
        UIErrorsFrame:AddMessage("[" .. selectedData.name .. "] 头衔提升：" .. newTier.name, 1, 0.82, 0, 1)
        FlavorManager.AddHistory("头衔变更为 " .. newTier.name)
    end
    if AP_FlavorUI and AP_FlavorUI.Refresh then AP_FlavorUI.Refresh() end
end

AP_FlavorManager = FlavorManager

-- 转化流派前弹出确认框（声望清零不可逆）
StaticPopupDialogs["AP_FLAVOR_CONVERT_CONFIRM"] = {
    text = "确定要转投 |cffffd700%s|r 吗？\n\n你在当前流派的声望将会清零。",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        if data then FlavorManager.ConvertFaction(data) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- 跨阵营转投：额外弹“异类”确认，之后声望/熟练度成长减半
StaticPopupDialogs["AP_FLAVOR_HERETIC_CONFIRM"] = {
    text = "|cffff2020异类！|r\n\n你做出了一个非同常人的选择。\n你在该流派的熟练度以及声望成长将会更加困难，确定吗？\n\n|cff888888（转投后，当前流派声望仍会清零）|r\n\n|cffffd700%s|r",
    button1 = "我确定",
    button2 = CANCEL,
    OnAccept = function(self, data)
        if data then FlavorManager.ConvertFaction(data) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ==========================================
-- 3. 表现层 (UI Layer)
-- ==========================================
local UI = {}
AP_FlavorUI = UI

-- 职业书签顺序：默认和游戏内一致（战士、圣骑士、猎人、潜行者、牧师、萨满、法师、术士、德鲁伊），
-- 但玩家自己的职业永远排在第一枚，其余按上面的顺序往后串。
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local classesList = {}
do
    -- 玩家职业如果在图鉴里有数据，就第一个放；没有（例如数据还没做的职业）就退回德鲁伊打头
    local firstClass = FlavorData[realClassToken] and realClassToken or "DRUID"
    table.insert(classesList, firstClass)
    for _, token in ipairs(CLASS_ORDER) do
        if token ~= firstClass then table.insert(classesList, token) end
    end
end

-- ==========================================
-- 职业书签：彩旗状丝带，从书页左缘垂出
-- 丝带贴图是白灰色的燕尾旗 (Media/Ribbon.tga)，运行时用职业色上色
-- ==========================================
local RIBBON_TEXTURE = "Interface\\AddOns\\AzerothParallel\\Media\\Ribbon.tga"
local RIBBON_W, RIBBON_H, RIBBON_STEP = 124, 44, 48 -- 丝带尺寸 / 纵向间距
local RIBBON_BASE_X = 15                            -- 丝带压进书页的长度（越大越“插”进书里）
local RIBBON_POP_SELECTED, RIBBON_POP_HOVER = 12, 6 -- 选中 / 悬停时向外拉出的距离
local ribbonButtons = {}

local function ApplyRibbonLayout(btn)
    local pop = 0
    if btn.isSelected then
        pop = RIBBON_POP_SELECTED
    elseif btn.isHover then
        pop = RIBBON_POP_HOVER
    end
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", LeftPage, "TOPLEFT", RIBBON_BASE_X - pop, btn.baseY)
    btn.body:SetAlpha(btn.isSelected and 1 or 0.88)
    btn:SetFrameLevel(p1:GetFrameLevel() + (btn.isSelected and 6 or 3))
end

for i, classID in ipairs(classesList) do
    local data = FlavorData[classID]
    local c = data.classColor or RAID_CLASS_COLORS[classID] or { r = 0.5, g = 0.5, b = 0.5 }

    local btn = CreateFrame("Button", nil, p1)
    btn:SetSize(RIBBON_W, RIBBON_H)
    btn.baseY = -24 - (i - 1) * RIBBON_STEP

    -- 投在书页上的阴影（同一张贴图染成黑色，向右下偏一点）
    local shadow = btn:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(RIBBON_TEXTURE)
    shadow:SetVertexColor(0, 0, 0, 0.4)
    shadow:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)

    -- 丝带本体
    local body = btn:CreateTexture(nil, "ARTWORK")
    body:SetTexture(RIBBON_TEXTURE)
    body:SetAllPoints()
    body:SetVertexColor(c.r, c.g, c.b)
    btn.body = body

    -- 悬停时微微提亮
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(RIBBON_TEXTURE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.3)
    hl:SetBlendMode("ADD")

    -- 文字：玩家自己的职业用浅色描边字高亮，其余职业统一深色字。
    -- 之前按丝带亮度判断，导致萨满/术士这类深色丝带也变成白字，
    -- 看起来像“只有自己的职业特殊”，所以改成按职业 token 判断。
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", 2, 0)
    text:SetText(data.className)
    local fontPath = text:GetFont()
    if classID == realClassToken then
        text:SetFont(fontPath, 15, "OUTLINE")
        text:SetTextColor(1, 0.96, 0.84)
    else
        text:SetFont(fontPath, 15, "")
        text:SetTextColor(0.16, 0.09, 0.03)
    end

    btn:SetScript("OnEnter", function(self)
        self.isHover = true; ApplyRibbonLayout(self)
    end)
    btn:SetScript("OnLeave", function(self)
        self.isHover = false; ApplyRibbonLayout(self)
    end)
    btn:SetScript("OnClick", function()
        AP_DB.flavor.previewClass = classID
        local newClassData = FlavorData[classID]
        if newClassData and newClassData.factions then
            -- 预览职业切换时，优先定位到玩家自己当前流派（如果是同一职业），否则第一个
            local target = newClassData.factions[1].id
            if classID == AP_DB.flavor.currentClass then
                target = AP_DB.flavor.currentFaction
            end
            AP_DB.flavor.previewFaction = target
        end
        UI.Refresh()
    end)

    ribbonButtons[classID] = btn
    ApplyRibbonLayout(btn)
end

function UI.RefreshRibbons()
    for classID, btn in pairs(ribbonButtons) do
        btn.isSelected = (classID == AP_DB.flavor.previewClass)
        ApplyRibbonLayout(btn)
    end
end

-- 左页内容区：统一宽度并相对 LeftPage 水平居中
-- 名牌 / 流派 Tab / 声望条都挂在它上面，左右边缘自然对齐；想整体左右微调就改下面的 offsetX
local CONTENT_WIDTH = 340
local leftContent = CreateFrame("Frame", nil, LeftPage)
leftContent:SetSize(CONTENT_WIDTH, 400)
leftContent:SetPoint("TOP", LeftPage, "TOP", 0, 0)

-- 名牌区域
-- 书页本身就是浅色羊皮纸，所以不再画深色底框：只留墨水字 + 一条细分割线。
local namePlate = CreateFrame("Frame", nil, leftContent, "BackdropTemplate")
namePlate:SetSize(CONTENT_WIDTH, 44)
namePlate:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -15)

local nameLine = namePlate:CreateTexture(nil, "ARTWORK")
nameLine:SetTexture("Interface\\Buttons\\WHITE8x8")
nameLine:SetHeight(1)
nameLine:SetPoint("BOTTOMLEFT", namePlate, "BOTTOMLEFT", 0, 2)
nameLine:SetPoint("BOTTOMRIGHT", namePlate, "BOTTOMRIGHT", 0, 2)
nameLine:SetVertexColor(THEME.line[1], THEME.line[2], THEME.line[3], 0.45)

local nameLabel = namePlate:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
nameLabel:SetPoint("LEFT", 2, 2)
nameLabel:SetJustifyH("LEFT")
nameLabel:SetFont(nameLabel:GetFont(), 26, "")
nameLabel:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])
nameLabel:SetText(AP_DB.flavor.customName)

local nameInput = CreateFrame("EditBox", nil, namePlate)
nameInput:SetSize(240, 30)
nameInput:SetPoint("LEFT", 2, 2)
nameInput:SetFontObject("GameFontNormalLarge")
nameInput:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])
nameInput:SetAutoFocus(false)
nameInput:SetMaxLetters(12) -- 限制名字长度，避免超出名牌
nameInput:Hide()
nameInput:SetScript("OnEnterPressed", function(self)
    if self:GetText() ~= "" then AP_DB.flavor.customName = self:GetText() end
    nameLabel:SetText(AP_DB.flavor.customName)
    self:Hide(); nameLabel:Show(); self:ClearFocus()
    -- 名字改了就立刻广播给装了插件的人（没装/不在同队的人收不到）
    if AP_Network and AP_Network.Broadcast then AP_Network.Broadcast() end
end)
nameInput:SetScript("OnEscapePressed", function(self)
    self:Hide(); nameLabel:Show(); self:ClearFocus()
end)

-- 进入改名状态的统一入口：点羽毛笔按钮、点名字本身都可以
local function StartEditName()
    nameLabel:Hide()
    nameInput:Show()
    nameInput:SetText(AP_DB.flavor.customName)
    nameInput:SetCursorPosition(0)
    nameInput:SetFocus()
    nameInput:HighlightText()
end

-- 名牌本身也能点，不用先找到右边那支羽毛笔
namePlate:EnableMouse(true)
namePlate:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then StartEditName() end
end)

-- 羽毛笔：书页上不再套金边底框，只留一枚小图标，落在名字右侧
local pencilBtn = CreateFrame("Button", nil, namePlate)
pencilBtn:SetSize(24, 24)
pencilBtn:SetPoint("RIGHT", -2, 2)
local pencilIcon = pencilBtn:CreateTexture(nil, "ARTWORK")
pencilIcon:SetAllPoints()
pencilIcon:SetTexture("Interface\\Icons\\INV_Misc_Quill_01")
pencilBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
pencilBtn:SetScript("OnClick", StartEditName)
pencilBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("修改名字", 1, 0.82, 0)
    GameTooltip:AddLine("点击后输入你的 RP 名字。", 1, 1, 1)
    GameTooltip:Show()
end)
pencilBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local factionTabContainer = CreateFrame("Frame", nil, leftContent)
factionTabContainer:SetSize(CONTENT_WIDTH, 35)
factionTabContainer:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -65)

-- ★ 流派 Tab 按钮池：按钮只创建一次，之后每次 Refresh 复用
local TAB_MAX_WIDTH, TAB_HEIGHT, TAB_GAP, TAB_PADDING = 110, 26, 4, 14
local TAB_FONT_SIZE, TAB_MIN_FONT_SIZE = 13, 9
local tabPool = {}

-- 选中 / 未选中的样式：选中 = 暗红底 + 米色字；未选 = 半透明羊皮纸底 + 墨水字
local function StyleTab(tab, selected)
    if selected then
        tab:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        tab:SetBackdropBorderColor(0.30, 0.09, 0.05, 1)
        tab.label:SetTextColor(THEME.cream[1], THEME.cream[2], THEME.cream[3])
    else
        tab:SetBackdropColor(0.80, 0.68, 0.46, 0.35)
        tab:SetBackdropBorderColor(THEME.line[1], THEME.line[2], THEME.line[3], 0.7)
        tab.label:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])
    end
end

local function AcquireTab(index)
    local tab = tabPool[index]
    if not tab then
        -- 匿名按钮 (name = nil)，所以不能用 _G[tab:GetName() .. "Text"]，统一用 label 自己记
        tab = CreateFrame("Button", nil, factionTabContainer, "BackdropTemplate")
        tab:SetHeight(TAB_HEIGHT)
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })

        local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 0, 0)
        tab.label = fs
        -- 保持和原按钮一样的用法：tab:SetText / tab:GetFontString
        tab.SetText = function(self, t) self.label:SetText(t) end
        tab.GetFontString = function(self) return self.label end

        tab.apFontPath = fs:GetFont() -- 记下字体路径，后面按需调整字号
        if tab.apFontPath then
            fs:SetFont(tab.apFontPath, TAB_FONT_SIZE, "")
        end
        fs:SetWordWrap(false) -- 不折行

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        hl:SetAllPoints()
        hl:SetVertexColor(1, 1, 1, 0.18)

        tabPool[index] = tab
    end
    return tab
end

local levelDisplay = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
levelDisplay:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -105)
levelDisplay:SetFont(levelDisplay:GetFont(), 20, "")
levelDisplay:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])

-- 声望条：暗红进度 + 羊皮纸色底 + 细墨线边框
local repBar = CreateFrame("StatusBar", nil, leftContent, "BackdropTemplate")
repBar:SetSize(CONTENT_WIDTH, 20)
repBar:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -140)
repBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
repBar:SetStatusBarColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
repBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
repBar:SetBackdropColor(0.35, 0.24, 0.12, 0.30)
repBar:SetBackdropBorderColor(THEME.line[1], THEME.line[2], THEME.line[3], 0.8)

local repText = repBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
repText:SetPoint("CENTER")
repText:SetFont(repText:GetFont(), 12, "OUTLINE")

local nextTierDisplay = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nextTierDisplay:SetPoint("TOP", repBar, "BOTTOM", 0, -5)
nextTierDisplay:SetFont(nextTierDisplay:GetFont(), 14, "")
nextTierDisplay:SetTextColor(THEME.inkSoft[1], THEME.inkSoft[2], THEME.inkSoft[3])

local historyTitle = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
historyTitle:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -190)
historyTitle:SetText("|cff8c261a最近履历：|r")

local historyText = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
historyText:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -210)
historyText:SetWidth(CONTENT_WIDTH)
historyText:SetJustifyH("LEFT")
historyText:SetSpacing(5)
historyText:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])

local convertBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
convertBtn:SetSize(180, 30)
convertBtn:SetPoint("TOP", leftContent, "TOP", 0, -330)
convertBtn:SetText("转化流派 (声望清零)")
convertBtn:SetScript("OnClick", function()
    local data = FindFaction(FlavorData[AP_DB.flavor.currentClass], AP_DB.flavor.previewFaction)
    if not data then return end
    -- 跨阵营走“异类”确认；同阵营/中立走普通确认
    if IsCrossFaction(data) then
        StaticPopup_Show("AP_FLAVOR_HERETIC_CONFIRM", data.name, nil, data.id)
    else
        StaticPopup_Show("AP_FLAVOR_CONVERT_CONFIRM", data.name, nil, data.id)
    end
end)

-- ★ 称谓典籍按钮：点一下，右页从“流派介绍”切换成“技能/天赋称呼对照表”
-- 这个开关只是本插件内部的一页，不会改动游戏里的任何技能名，别人完全看不到。
local showingSpellBook = false
local spellBookBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
spellBookBtn:SetSize(180, 30)
spellBookBtn:SetPoint("TOP", leftContent, "TOP", 0, -368)
spellBookBtn:SetText("称谓典籍")
spellBookBtn:SetScript("OnClick", function()
    showingSpellBook = not showingSpellBook
    UI.Refresh()
end)

local iconFrame = CreateFrame("Frame", nil, RightPage, "BackdropTemplate")
iconFrame:SetSize(80, 80)
iconFrame:SetPoint("TOP", RightPage, "TOP", 0, -20)
iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
iconFrame:SetBackdropColor(0, 0, 0, 1)
iconFrame:SetBackdropBorderColor(0.36, 0.22, 0.10, 1)
local badgeIcon = iconFrame:CreateTexture(nil, "ARTWORK")
badgeIcon:SetAllPoints()

local scrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(310, 400)
scrollFrame:SetPoint("TOPLEFT", 55, -120)
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(280)
scrollChild:SetHeight(1)

local descText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
descText:SetPoint("TOPLEFT", 0, 0)
descText:SetWidth(280)
descText:SetJustifyH("LEFT")
descText:SetSpacing(12)
descText:SetFont(descText:GetFont(), 18, "")
descText:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])

-- “反映到游戏内提示”的开关：勾选后，鼠标悬停技能时第一行显示本流派的称呼。
-- 只包装 tooltip 的显示函数，不碰 GetSpellInfo，别人看不到，也不会影响其他插件。
local tooltipToggle = CreateFrame("CheckButton", "AP_TooltipAliasToggle", RightPage, "ChatConfigCheckButtonTemplate")
tooltipToggle:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 50, -32)
local toggleText = _G[tooltipToggle:GetName() .. "Text"]
toggleText:SetText("应用到游戏内提示/施法条（仅自己可见）")
toggleText:SetFont(toggleText:GetFont(), 14, "")
toggleText:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])
tooltipToggle:SetChecked(AP_DB.flavor.tooltipAlias and true or false)
tooltipToggle:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    AP_DB.flavor.tooltipAlias = on
    if AP_TooltipAlias then AP_TooltipAlias.SetEnabled(on) end
end)
tooltipToggle:Hide() -- 只在“称谓典籍”模式下显示

-- 登录后再同步一次：防止存档在 UI 创建之后才注入，导致复选框显示成未勾选
local aliasSyncFrame = CreateFrame("Frame")
aliasSyncFrame:RegisterEvent("PLAYER_LOGIN")
aliasSyncFrame:SetScript("OnEvent", function()
    if AP_DB.flavor.aliasDefaultApplied ~= true then
        AP_DB.flavor.tooltipAlias = true
        AP_DB.flavor.aliasDefaultApplied = true
    elseif AP_DB.flavor.tooltipAlias == nil then
        AP_DB.flavor.tooltipAlias = true
    end
    tooltipToggle:SetChecked(AP_DB.flavor.tooltipAlias and true or false)
    if AP_TooltipAlias then AP_TooltipAlias.SetEnabled(AP_DB.flavor.tooltipAlias) end
end)

-- 称谓典籍的滚动区：和“流派介绍”共用右页，同一时间只显示其中一个。
-- 顶部要给上面的开关留位置，所以从 -72 开始。
local spellScrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
spellScrollFrame:SetSize(310, 400)
spellScrollFrame:SetPoint("TOPLEFT", 55, -72)
local spellChild = CreateFrame("Frame", nil, spellScrollFrame)
spellScrollFrame:SetScrollChild(spellChild)
spellChild:SetWidth(280)
spellChild:SetHeight(1)

local spellText = spellChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
spellText:SetPoint("TOPLEFT", 0, 0)
spellText:SetWidth(280)
spellText:SetJustifyH("LEFT")
spellText:SetSpacing(8)
spellText:SetFont(spellText:GetFont(), 16, "")
spellText:SetTextColor(THEME.ink[1], THEME.ink[2], THEME.ink[3])
spellScrollFrame:Hide()

-- 称谓典籍 → 核心培养：点一下直接切到第 4 个「核心」页
local coreJumpBtn = CreateFrame("Button", nil, RightPage, "UIPanelButtonTemplate")
coreJumpBtn:SetSize(260, 26)
coreJumpBtn:SetPoint("BOTTOM", RightPage, "BOTTOM", 0, 26)
coreJumpBtn:SetText("前往核心培养")
coreJumpBtn:Hide()
coreJumpBtn:SetScript("OnClick", function()
    if AP_MainFrame then AP_MainFrame:Show() end
    if AP_SelectTab then AP_SelectTab(4) end
end)

-- 流派介绍 → 特效预览：收起书本，显示当前预览流派的特效 1.5 秒后恢复
local auraPreviewBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
auraPreviewBtn:SetSize(180, 30)
auraPreviewBtn:SetPoint("TOP", spellBookBtn, "BOTTOM", 0, -10)
auraPreviewBtn:SetText("特效预览")
auraPreviewBtn:SetScript("OnClick", function()
    local classToken = AP_DB.flavor.previewClass
    local factionID = AP_DB.flavor.previewFaction
    if AP_MainFrame then AP_MainFrame:Hide() end
    if AP_Aura and AP_Aura.Preview then
        AP_Aura.Preview(classToken, factionID, 1.5)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(1.6, function()
            if AP_MainFrame then AP_MainFrame:Show() end
        end)
    else
        if AP_MainFrame then AP_MainFrame:Show() end
    end
end)

-- 未实装职业提示：玩家自己的职业还没有流派数据时，在右页底部说明一句，
-- 避免让人以为插件坏了或者列表空了。默认隐藏，由 UI.Refresh 控制。
local classNotice = RightPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
classNotice:SetPoint("BOTTOM", RightPage, "BOTTOM", 0, 18)
classNotice:SetWidth(340)
classNotice:SetJustifyH("CENTER")
classNotice:SetFont(classNotice:GetFont(), 13, "")
classNotice:SetText("|cff8c261a你的职业「" .. (select(1, UnitClass("player")) or "未知")
    .. "」的流派设定仍在撰写中|r\n|cff6b5a45当前展示德鲁伊示例，后续版本会补齐。|r")
classNotice:Hide()

-- 记住上一次显示的是哪个流派，切流派时把滚动条拉回顶部
local lastSpellKey

-- 把“职业通用词条”和“流派专属覆盖”合成一份完整列表：
--   AP_Terms[职业]._common = 该职业所有技能/天赋的默认称呼
--   AP_Terms[职业][流派id] = 只写这个流派叫法不同的条目，用来覆盖同名的通用词条
-- 这样不用把同一个技能在 3~5 个流派里各抄一遍，改一个技能也只需要改通用那份。
local function BuildTermList(classToken, factionID)
    local classTerms = AP_Terms and AP_Terms[classToken]
    if not classTerms then return nil end

    local list, byOfficial = {}, {}
    local function Add(term)
        if not term or not term.official then return end
        local existing = byOfficial[term.official]
        if existing then
            -- 同名技能：流派覆盖的那一份只替换称呼/备注
            if term.alias then existing.alias = term.alias end
            if term.note then existing.note = term.note end
            if term.category then existing.category = term.category end
        else
            -- 拷贝一份再放进结果表，避免运行时修改到 AP_Terms 里的原始数据
            local copy = {
                category = term.category,
                official = term.official,
                alias = term.alias,
                note = term.note,
            }
            table.insert(list, copy)
            byOfficial[term.official] = copy
        end
    end

    if classTerms._common then
        for _, term in ipairs(classTerms._common) do Add(term) end
    end
    local factionTerms = classTerms[factionID]
    if factionTerms then
        for _, term in ipairs(factionTerms) do Add(term) end
    end

    if #list == 0 then return nil end
    return list
end

-- 导出给 Overrides.lua 用：它需要知道“当前流派有哪些称呼”，才能改鼠标提示。
AP_FlavorManager.GetTermList = BuildTermList

-- ==========================================
-- 技能熟练度（模仿魔兽自带的武器熟练度）
-- ==========================================
-- 规则：
--   * 每次成功施放技能有概率 +1 点；等级越高、越接近上限越难涨。
--   * 上限 = 角色等级 × 5，60 级就是 300，所以基本要练到 60 级才可能满。
--   * 只统计「称谓典籍」里非天赋的条目，按官方技能名存档。
local playerLevel = 1

local function IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

local function RefreshPlayerLevel()
    local ok, level = pcall(UnitLevel, "player")
    if ok and type(level) == "number" and not IsSecret(level) and level > 0 then
        playerLevel = level
    end
end
RefreshPlayerLevel()

local function GetSkillProfTable()
    AP_DB.flavor = AP_DB.flavor or {}
    AP_DB.flavor.skillProf = AP_DB.flavor.skillProf or {}
    return AP_DB.flavor.skillProf
end

local function GetSkillProf(official)
    return GetSkillProfTable()[official] or 0
end

local function GetMaxSkillProf()
    return math.max(5, playerLevel * 5)
end

-- 文字版熟练度条：绿色已练部分 + 灰色未练部分
local function FormatProfBar(current, maxProf)
    local ratio = (maxProf > 0) and (current / maxProf) or 0
    local filled = math.floor(ratio * 10 + 0.5)
    if filled < 0 then filled = 0 end
    if filled > 10 then filled = 10 end
    return "|cff3f6b2e" .. current .. "|r|cff6b5a45/" .. maxProf .. "|r  "
        .. "|cff3f6b2e" .. string.rep("=", filled) .. "|r"
        .. "|cff9a8a72" .. string.rep("-", 10 - filled) .. "|r"
end

-- 当前职业/流派里可以练的条目：官方技能名 -> 词条
local profTermMap, profTermMapKey
local function GetProfTermMap()
    local key = tostring(AP_DB.flavor.currentClass) .. ":" .. tostring(AP_DB.flavor.currentFaction)
    if profTermMapKey == key then return profTermMap end

    profTermMapKey, profTermMap = key, {}
    local terms = BuildTermList(AP_DB.flavor.currentClass, AP_DB.flavor.currentFaction)
    if terms then
        for _, term in ipairs(terms) do
            -- 天赋是被动，不参与熟练度；其余可施放条目都记录
            if term.category ~= "天赋" then
                profTermMap[term.official] = term
            end
        end
    end
    return profTermMap
end

local function GetSpellNameByID(spellID)
    local ok, name
    if C_Spell and C_Spell.GetSpellInfo then
        ok, name = pcall(function()
            local info = C_Spell.GetSpellInfo(spellID)
            return info and info.name
        end)
    else
        ok, name = pcall(GetSpellInfo, spellID)
    end
    if not ok or type(name) ~= "string" then return nil end
    if IsSecret(name) then return nil end
    return name
end

-- 技能典籍开着时，熟练度上涨后延迟刷新，避免每次施法都重排整页文字
local profRefreshPending = false
local function QueueSpellBookRefresh()
    if not showingSpellBook or profRefreshPending then return end
    profRefreshPending = true
    local function DoRefresh()
        profRefreshPending = false
        if showingSpellBook then
            UI.RefreshSpellBook(select(1, FlavorManager.GetPreviewFactionData()))
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(1.0, DoRefresh)
    else
        DoRefresh()
    end
end

-- 施法成功：按概率涨一点熟练度
local profFrame = CreateFrame("Frame")
if profFrame.RegisterUnitEvent then
    profFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    -- 老内核没有 RegisterUnitEvent，退回普通注册，再在回调里过滤单位
    profFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
profFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not spellID then return end
    local spellName = GetSpellNameByID(spellID)
    if not spellName then return end

    local term = GetProfTermMap()[spellName]
    if not term then return end

    local db = GetSkillProfTable()
    local current = db[term.official] or 0
    local maxProf = GetMaxSkillProf()
    if current >= maxProf then return end

    -- 越接近上限越难涨：<100 30%，<200 20%，再往上 10%
    local chance
    if current < 100 then
        chance = 0.30
    elseif current < 200 then
        chance = 0.20
    else
        chance = 0.10
    end

    -- 异类惩罚：跨阵营流派时，熟练度成长概率减半（核心等级由熟练度换算，也会同步变慢）
    local factionData = FlavorManager.GetCurrentFactionData()
    if IsCrossFaction(factionData) then
        chance = chance * 0.5
    end

    if math.random() > chance then return end

    current = current + 1
    db[term.official] = current

    -- 和流派声望提示同色（蓝），并显示在卡片上方
    local profMsg = "熟练度提升：" .. (term.alias or term.official) ..
        "  " .. current .. "/" .. maxProf
    if AP_EmoteUI and AP_EmoteUI.Notify then
        -- 熟练度提示比声望提示更醒目：颜色更深、字号大一点、停留 4.5 秒
        AP_EmoteUI.Notify(profMsg, 0, 0.38, 0.78, 17, 4.5)
    else
        UIErrorsFrame:AddMessage(profMsg, 0, 0.5, 1, 1)
    end
    QueueSpellBookRefresh()
end)

-- 登录 / 升级时更新缓存的角色等级（上限 = 等级 × 5）
local levelFrame = CreateFrame("Frame")
levelFrame:RegisterEvent("PLAYER_LOGIN")
levelFrame:RegisterEvent("PLAYER_LEVEL_UP")
levelFrame:SetScript("OnEvent", function(self, event)
    RefreshPlayerLevel()
    if event == "PLAYER_LEVEL_UP" then QueueSpellBookRefresh() end
end)

function UI.RefreshSpellBook(previewData)
    if not previewData then
        spellText:SetText("|cff6b5a45暂无数据|r")
        return
    end

    -- 词条 = 职业通用 + 流派覆盖，具体合并规则见上面的 BuildTermList
    local terms = BuildTermList(AP_DB.flavor.previewClass, previewData.id)
    local key = tostring(AP_DB.flavor.previewClass) .. ":" .. tostring(previewData.id)

    if not terms or #terms == 0 then
        spellText:SetText("|cff8c261a" .. previewData.name .. " · 称谓典籍|r\n\n" ..
            "|cff6b5a45该流派暂时没有词条。\n\n词条库按“职业 → 流派”整理，目前只有德鲁伊的三个流派有初稿，其他职业会陆续补上。|r")
    else
        -- 只有预览自己的职业时才显示熟练度；预览别的职业没有参考意义
        local showProf = (AP_DB.flavor.previewClass == AP_DB.flavor.currentClass)

        local lines = { "|cff8c261a" .. previewData.name .. " · 称谓典籍|r" }
        if showProf then
            table.insert(lines, "|cff6b5a45熟练度上限：" .. GetMaxSkillProf() .. "（角色等级 × 5）|r")
        end
        table.insert(lines, "")
        local lastCategory
        for _, term in ipairs(terms) do
            -- 换了分类就插一条金色小标题（同分类的条目自动归在一起）
            if term.category and term.category ~= lastCategory then
                table.insert(lines, (lastCategory and "\n" or "") .. "|cff8c261a【" .. term.category .. "】|r")
                lastCategory = term.category
            end
            -- 核心技能 15 级后改过的名字，同步显示在称谓典籍里
            local displayAlias = term.alias
            local coreLevelForTerm
            local spotlightDB = AP_DB.spotlight
            if showProf and spotlightDB and spotlightDB.coreSpell == term.official then
                local prof = AP_DB.flavor.skillProf or {}
                coreLevelForTerm = math.min(30, math.floor(((prof[term.official] or 0) / 10)) + 1)
                if type(spotlightDB.coreAlias) == "string" and spotlightDB.coreAlias ~= "" then
                    displayAlias = spotlightDB.coreAlias
                end
            end

            -- 一行：绿色 = 本流派称呼，灰色 = 官方原名，方便对照
            table.insert(lines, "|cff3f6b2e" .. (displayAlias or "?") .. "|r |cff6b5a45（官方：" .. (term.official or "?") .. "）|r")
            -- 有备注的话，缩进一行灰字补一句说明
            if term.note and term.note ~= "" then
                table.insert(lines, "|cff6b5a45　　" .. term.note .. "|r")
            end
            -- 熟练度（天赋是被动的，不显示；预览别的职业时也不显示）
            if showProf and term.category ~= "天赋" then
                local coreTag = coreLevelForTerm
                    and ("  |cff8c261a核心 Lv." .. coreLevelForTerm .. "|r") or ""
                table.insert(lines, "|cff6b5a45　　熟练度：|r" ..
                    FormatProfBar(GetSkillProf(term.official), GetMaxSkillProf()) .. coreTag)
            end
        end
        spellText:SetText(table.concat(lines, "\n"))
    end

    spellChild:SetHeight(spellText:GetStringHeight() + 30)
    if lastSpellKey ~= key then
        spellScrollFrame:SetVerticalScroll(0)
        lastSpellKey = key
    end
end

function UI.RefreshHistory()
    local lines = {}
    for _, text in ipairs(AP_DB.flavor.history) do table.insert(lines, "• " .. text) end
    if #lines == 0 then
        historyText:SetText("|cff8a7a62暂无履历，去冒险吧。|r")
    else
        historyText:SetText(table.concat(lines, "\n"))
    end
end

local lastShownFactionID = nil

function UI.Refresh()
    -- 按钮文字跟着右页模式走：已经在典籍里，就提示可以返回
    spellBookBtn:SetText(showingSpellBook and "返回流派介绍" or "称谓典籍")

    -- 自己的职业没有数据时，右页底部显示“撰写中”提示
    if classNotice then
        if FlavorData[realClassToken] then
            classNotice:Hide()
        else
            classNotice:Show()
        end
    end

    UI.RefreshRibbons() -- 选中的职业书签向外拉出一截
    local previewData, previewClassData = FlavorManager.GetPreviewFactionData()

    -- 先把池子里的按钮全部隐藏，下面按需 Show
    for _, tab in ipairs(tabPool) do tab:Hide() end

    -- 动态渲染 Tab (复用按钮池，宽度按流派数量自适应，保证不超出容器)
    if previewClassData and previewClassData.factions then
        local count = #previewClassData.factions
        local selectedID = previewData and previewData.id or AP_DB.flavor.previewFaction
        local containerWidth = factionTabContainer:GetWidth()
        local avail = containerWidth - TAB_GAP * (count - 1)

        -- 第一遍：按文字实际宽度算出每个按钮需要多宽（"月之女祭司"这类长名字不会再被截断）
        local widths, textWidths, sum = {}, {}, 0
        for i, faction in ipairs(previewClassData.factions) do
            local tab = AcquireTab(i)
            local fs = tab:GetFontString()
            if fs and tab.apFontPath then
                -- 先恢复标准字号、自动宽度，再量文字真实宽度
                fs:SetFont(tab.apFontPath, TAB_FONT_SIZE, "")
                fs:SetWidth(0)
            end
            tab:SetText(faction.name)
            textWidths[i] = fs and fs:GetStringWidth() or 60
            widths[i] = textWidths[i] + TAB_PADDING
            sum = sum + widths[i]
        end

        -- 放不下就等比缩小；有富余就平均加宽（单个按钮不超过 TAB_MAX_WIDTH）
        if sum > avail then
            local scale = avail / sum
            for i = 1, count do widths[i] = widths[i] * scale end
        else
            local extra = (avail - sum) / count
            for i = 1, count do widths[i] = math.min(TAB_MAX_WIDTH, widths[i] + extra) end
        end

        local total = TAB_GAP * (count - 1)
        for i = 1, count do total = total + widths[i] end
        local x = (containerWidth - total) / 2 -- 整行在容器内居中

        -- 第二遍：定位、上色、绑定点击
        for i, faction in ipairs(previewClassData.factions) do
            local tab = tabPool[i]
            tab:SetWidth(widths[i])
            local fs = tab:GetFontString()
            if fs then
                -- 按钮被压窄、放不下标准字号时，自动缩小字号（最小 TAB_MIN_FONT_SIZE），不再出现 "..."
                local space = widths[i] - 6
                local size = TAB_FONT_SIZE
                if textWidths[i] > space then
                    size = math.max(TAB_MIN_FONT_SIZE, math.floor(TAB_FONT_SIZE * space / textWidths[i]))
                end
                if tab.apFontPath then fs:SetFont(tab.apFontPath, size, "") end
                fs:SetWidth(widths[i] - 2)
            end

            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", factionTabContainer, "TOPLEFT", x, 0)
            x = x + widths[i] + TAB_GAP

            -- 选中 = 暗红底 + 米色字；未选 = 半透明羊皮纸底 + 墨水字
            tab:SetText(faction.name)
            StyleTab(tab, selectedID == faction.id)

            tab:SetScript("OnClick", function()
                AP_DB.flavor.previewFaction = faction.id
                UI.Refresh()
            end)

            tab:Show()
        end
    end

    local canConvert = false
    if AP_DB.flavor.previewClass == AP_DB.flavor.currentClass and previewData
        and previewData.id ~= AP_DB.flavor.currentFaction then
        canConvert = true
    end

    if canConvert then
        convertBtn:Show()
    else
        convertBtn:Hide()
    end

    if not previewData then return end

    -- 只有“当前职业 + 当前激活流派”才显示 tooltip 开关。
    -- 预览别的职业/流派时开关不生效（它永远作用于 AP_DB.flavor.currentFaction），
    -- 显示出来只会误导，所以直接隐藏。
    local canToggleAlias = (AP_DB.flavor.previewClass == AP_DB.flavor.currentClass
        and previewData.id == AP_DB.flavor.currentFaction)

    -- 右页两种模式二选一：流派介绍（默认） / 称谓典籍
    if showingSpellBook then
        iconFrame:Hide()
        scrollFrame:Hide()
        spellScrollFrame:Show()

        if canToggleAlias then
            tooltipToggle:Show()
            spellScrollFrame:ClearAllPoints()
            spellScrollFrame:SetPoint("TOPLEFT", 55, -72)
        else
            tooltipToggle:Hide()
            -- 开关藏起来后把典籍上移，避免顶部空一块
            spellScrollFrame:ClearAllPoints()
            spellScrollFrame:SetPoint("TOPLEFT", 55, -30)
        end

        UI.RefreshSpellBook(previewData)

        -- 只有预览自己职业、且已经选了核心技能时，才显示跳转入口
        local spotlightDB = AP_DB.spotlight
        if spotlightDB and spotlightDB.coreSpell and spotlightDB.coreSpell ~= ""
            and AP_DB.flavor.previewClass == AP_DB.flavor.currentClass then
            coreJumpBtn:SetText("核心培养：" .. spotlightDB.coreSpell .. " →")
            coreJumpBtn:Show()
        else
            coreJumpBtn:Hide()
        end
    else
        iconFrame:Show()
        scrollFrame:Show()
        spellScrollFrame:Hide()
        tooltipToggle:Hide()
        coreJumpBtn:Hide()
    end

    badgeIcon:SetTexture(previewData.icon or FALLBACK_ICON)
    descText:SetText(previewData.description or "")
    scrollChild:SetHeight(descText:GetStringHeight() + 40)

    -- 切换到不同流派时，说明文字滚回顶部（声望变化触发的刷新不重置）
    if lastShownFactionID ~= previewData.id then
        scrollFrame:SetVerticalScroll(0)
        lastShownFactionID = previewData.id
    end

    -- 只有“正在看自己当前流派”才算当前身份。
    -- 预览别的流派/职业时，声望条显示的是那个流派自己的存档数据，并用灰色区分。
    local isOwn = (AP_DB.flavor.previewClass == AP_DB.flavor.currentClass
        and previewData.id == AP_DB.flavor.currentFaction)
    if isOwn then
        repBar:SetStatusBarColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    else
        repBar:SetStatusBarColor(0.50, 0.44, 0.36)
    end

    local tier, nextTier, rep = FlavorManager.GetTierInfo(previewData)
    if tier then
        if isOwn then
            levelDisplay:SetText("|cff5c3f23当前身份：|r" .. tier.name)
        else
            levelDisplay:SetText("|cff7a6a55预览：" .. previewData.name .. " · " .. tier.name .. "|r")
        end
        if nextTier then
            local prevExp = tier.exp or 0
            local nextExp = nextTier.exp
            repBar:SetMinMaxValues(prevExp, nextExp)
            repBar:SetValue(rep)
            repText:SetText(string.format("%d / %d", rep, nextExp))
            if isOwn then
                nextTierDisplay:SetText("下一阶级：" .. nextTier.name .. " (还需 " .. (nextExp - rep) .. ")")
            else
                nextTierDisplay:SetText("|cff7a6a55预览下一阶级：" .. nextTier.name .. " (还需 " .. (nextExp - rep) .. ")|r")
            end
        else
            repBar:SetMinMaxValues(0, 1)
            repBar:SetValue(1)
            repText:SetText("崇拜")
            nextTierDisplay:SetText(isOwn and "已到达最高阶级。" or "|cff7a6a55该流派已达最高阶级。|r")
        end
    end
end

-- ==========================================
-- 4. 事件层 (安全版修复)
-- ==========================================
local repFrame = CreateFrame("Frame")
repFrame:RegisterEvent("QUEST_TURNED_IN")
repFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

repFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "QUEST_TURNED_IN" then
        FlavorManager.AddReputation(100)
        -- 兼容处理：新一点的内核用 C_QuestLog，老内核（1.12 / 3.3.5 私服常见）没有这个接口。
        -- 拿不到名字时退回“未知任务”，绝不让一个报错打断加声望。
        local title = "未知任务"
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, t = pcall(C_QuestLog.GetTitleForQuestID, arg1)
            if ok and t then title = t end
        elseif GetQuestLogTitle then
            local ok, t = pcall(GetQuestLogTitle, arg1)
            if ok and t then title = t end
        end
        FlavorManager.AddHistory("完成任务：" .. title)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local zoneName = GetZoneText()
        if zoneName and zoneName ~= "" and zoneName ~= GetRealZoneText() then
            FlavorManager.AddHistory("抵达了 " .. zoneName)
        end
    end
end)

UI.RefreshHistory()
UI.Refresh()

-- ==========================================
-- 对外接口：从其他模块直接打开「技能典籍（熟练度）」页
-- ==========================================
function UI.OpenSkillBook()
    -- 强制回到自己的当前职业/流派
    AP_DB.flavor.previewClass = AP_DB.flavor.currentClass
    AP_DB.flavor.previewFaction = AP_DB.flavor.currentFaction
    showingSpellBook = true

    if AP_MainFrame then AP_MainFrame:Show() end
    if AP_Tabs and AP_Tabs[2] and AP_Tabs[2].Click then
        AP_Tabs[2]:Click() -- 切到「职业流派」Tab
    end

    UI.Refresh()
end
