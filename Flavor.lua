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
-- 标题在 RightPage -10，副标题行是 -46；和右侧「已修习」同一行
tooltipToggle:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 38, -46)
local toggleText = _G[tooltipToggle:GetName() .. "Text"]
toggleText:SetText("应用到技能名")
toggleText:SetFont(toggleText:GetFont(), 11, "")
toggleText:SetTextColor(THEME.inkSoft[1], THEME.inkSoft[2], THEME.inkSoft[3])
toggleText:ClearAllPoints()
toggleText:SetPoint("LEFT", tooltipToggle, "RIGHT", 4, 0)
toggleText:SetJustifyH("LEFT")
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
-- ==========================================
-- 称谓典籍（新版排版）：固定头部 + 滚动行池 + 详情卡
-- 只做显示层：词条来自 BuildTermList，熟练度来自 skillProf
-- ==========================================
local SB_CONTENT_W = 324
local SB_ROW_H = 32
local SB_ROW_GAP = 2
local SB_CAT_H = 18
local SB_CAT_GAP = 8
local SB_ICON = 20
local SB_BAR_W = 76
local SB_BAR_H = 8
local SB_BAR_SEGMENTS = math.floor((SB_BAR_W - 4) / 5)  -- 14 段

-- 颜色：能对上主题的读 AP_Theme，其余按参考图写死
local SB_COL = {
    title = { THEME.accent[1], THEME.accent[2], THEME.accent[3] },
    ink = { THEME.ink[1], THEME.ink[2], THEME.ink[3] },
    soft = { 118/255, 88/255, 56/255 },
    muted = { 176/255, 150/255, 112/255 },
    line = { 170/255, 132/255, 84/255 },
    green = { 46/255, 104/255, 58/255 },
    gold = { 178/255, 128/255, 46/255 },
    rowEven = { 240/255, 208/255, 154/255 },
    coreRow = { 246/255, 199/255, 188/255 },   -- 核心技能行的淡红底
    cardBg = { 250/255, 228/255, 186/255 },
    barBg = { 214/255, 180/255, 126/255 },
    cream = { 255/255, 244/255, 214/255 },
    barEdge = { 51/255, 31/255, 16/255 },
}

-- 头部：标题 + 双分割线 + 副标题
local spellBookHeader = CreateFrame("Frame", nil, RightPage)
spellBookHeader:SetSize(SB_CONTENT_W, 72)
spellBookHeader:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 38, -10)
spellBookHeader:Hide()

local sbTitle = spellBookHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbTitle:SetPoint("TOPLEFT", 0, 0)
sbTitle:SetJustifyH("LEFT")
sbTitle:SetFont(sbTitle:GetFont(), 17, "")
sbTitle:SetTextColor(SB_COL.title[1], SB_COL.title[2], SB_COL.title[3])

local sbLine1 = spellBookHeader:CreateTexture(nil, "ARTWORK")
sbLine1:SetTexture("Interface\\Buttons\\WHITE8x8")
sbLine1:SetSize(SB_CONTENT_W, 1)
sbLine1:SetPoint("TOPLEFT", 0, -26)
sbLine1:SetVertexColor(SB_COL.line[1], SB_COL.line[2], SB_COL.line[3], 0.9)

local sbLine2 = spellBookHeader:CreateTexture(nil, "ARTWORK")
sbLine2:SetTexture("Interface\\Buttons\\WHITE8x8")
sbLine2:SetSize(SB_CONTENT_W, 1)
sbLine2:SetPoint("TOPLEFT", 0, -29)
sbLine2:SetVertexColor(SB_COL.line[1], SB_COL.line[2], SB_COL.line[3], 0.55)

local sbSubMax = spellBookHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbSubMax:SetPoint("TOPLEFT", 0, -38)
sbSubMax:SetFont(sbSubMax:GetFont(), 11, "")
sbSubMax:SetTextColor(SB_COL.soft[1], SB_COL.soft[2], SB_COL.soft[3])

local sbSubFormula = spellBookHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbSubFormula:SetPoint("LEFT", sbSubMax, "RIGHT", 8, 0)
sbSubFormula:SetFont(sbSubFormula:GetFont(), 11, "")
sbSubFormula:SetTextColor(SB_COL.muted[1], SB_COL.muted[2], SB_COL.muted[3])
sbSubFormula:SetText("= 角色等级 × 5")

local sbSubLearned = spellBookHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbSubLearned:SetPoint("TOPRIGHT", spellBookHeader, "TOPRIGHT", 0, -38)
sbSubLearned:SetJustifyH("RIGHT")
sbSubLearned:SetFont(sbSubLearned:GetFont(), 11, "")
sbSubLearned:SetTextColor(SB_COL.green[1], SB_COL.green[2], SB_COL.green[3])

-- 列表滚动区
local spellScrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
spellScrollFrame:SetSize(360, 300)
spellScrollFrame:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 20, -88)
spellScrollFrame:Hide()

local spellChild = CreateFrame("Frame", nil, spellScrollFrame)
spellScrollFrame:SetScrollChild(spellChild)
spellChild:SetWidth(SB_CONTENT_W + 18) -- 左侧留 18 的内边距
spellChild:SetHeight(1)

local sbEmpty = RightPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbEmpty:SetPoint("TOP", RightPage, "TOP", 0, -130)
sbEmpty:SetWidth(SB_CONTENT_W)
sbEmpty:SetJustifyH("CENTER")
sbEmpty:SetFont(sbEmpty:GetFont(), 13, "")
sbEmpty:SetTextColor(SB_COL.soft[1], SB_COL.soft[2], SB_COL.soft[3])
sbEmpty:SetText("该流派暂时没有词条。")
sbEmpty:Hide()

-- 详情卡（列表下方固定区域）
local detailCard = CreateFrame("Frame", nil, RightPage, "BackdropTemplate")
detailCard:SetSize(SB_CONTENT_W, 70)
detailCard:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 38, -396)
detailCard:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
detailCard:SetBackdropColor(SB_COL.cardBg[1], SB_COL.cardBg[2], SB_COL.cardBg[3], 1)
detailCard:SetBackdropBorderColor(SB_COL.gold[1], SB_COL.gold[2], SB_COL.gold[3], 1)
detailCard:Hide()

local detailIcon = detailCard:CreateTexture(nil, "ARTWORK")
detailIcon:SetSize(32, 32)
detailIcon:SetPoint("LEFT", 8, 0)
detailIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local detailName = detailCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailName:SetPoint("TOPLEFT", 50, -5)
detailName:SetFont(detailName:GetFont(), 14, "")
detailName:SetTextColor(SB_COL.ink[1], SB_COL.ink[2], SB_COL.ink[3])

local detailDesc = detailCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailDesc:SetPoint("TOPLEFT", 50, -24)
detailDesc:SetWidth(SB_CONTENT_W - 58)
detailDesc:SetJustifyH("LEFT")
detailDesc:SetFont(detailDesc:GetFont(), 11, "")
detailDesc:SetTextColor(SB_COL.soft[1], SB_COL.soft[2], SB_COL.soft[3])

local detailFoot = detailCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailFoot:SetPoint("BOTTOMLEFT", 50, 7)
detailFoot:SetWidth(SB_CONTENT_W - 56)
detailFoot:SetJustifyH("LEFT")
detailFoot:SetFont(detailFoot:GetFont(), 9, "")
detailFoot:SetTextColor(SB_COL.muted[1], SB_COL.muted[2], SB_COL.muted[3])

local SB_RANKS = { "见习", "熟手", "精通", "大师", "宗师" }
local sbRows, sbCatBars = {}, {}
local sbCollapsed = {}
local sbLastData
local sbDetailDefault

local SB_ShowDetail -- 先声明，行按钮创建时要用

-- 「隐藏未学」开关：默认隐藏还没练过的称谓，点一下可以展开看全部
local sbHideUnlearned = true

local sbHideBtn = CreateFrame("Button", nil, spellBookHeader)
sbHideBtn:SetSize(80, 14)
-- 第二行：在「应用到提示」下面
sbHideBtn:SetPoint("TOPLEFT", spellBookHeader, "TOPLEFT", 0, -58)
local sbHideText = sbHideBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbHideText:SetAllPoints()
sbHideText:SetJustifyH("LEFT")
sbHideText:SetFont(sbHideText:GetFont(), 10, "")
sbHideBtn:SetScript("OnClick", function()
    sbHideUnlearned = not sbHideUnlearned
    if sbLastData then UI.RefreshSpellBook(sbLastData) end
end)

local function SB_UpdateHideBtn()
    if sbHideUnlearned then
        sbHideText:SetText("隐藏未学：开")
        sbHideText:SetTextColor(SB_COL.green[1], SB_COL.green[2], SB_COL.green[3])
    else
        sbHideText:SetText("隐藏未学：关")
        sbHideText:SetTextColor(SB_COL.muted[1], SB_COL.muted[2], SB_COL.muted[3])
    end
end
SB_UpdateHideBtn()

local function SB_CreateRow()
    local row = CreateFrame("Frame", nil, spellChild)
    row:SetSize(SB_CONTENT_W, SB_ROW_H)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints()
    bg:SetVertexColor(SB_COL.rowEven[1], SB_COL.rowEven[2], SB_COL.rowEven[3], 1)
    row.bg = bg

    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetTexture("Interface\\Buttons\\WHITE8x8")
    mark:SetSize(3, SB_ROW_H)
    mark:SetPoint("LEFT", 0, 0)
    mark:SetVertexColor(SB_COL.gold[1], SB_COL.gold[2], SB_COL.gold[3], 1)
    row.mark = mark

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SB_ICON, SB_ICON)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", 34, 0)
    name:SetWidth(78)
    name:SetJustifyH("LEFT")
    name:SetFont(name:GetFont(), 13, "")
    row.name = name

    local official = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    official:SetPoint("LEFT", 116, 0)
    official:SetWidth(72)
    official:SetJustifyH("LEFT")
    official:SetFont(official:GetFont(), 10, "")
    row.official = official

    local bar = CreateFrame("Frame", nil, row, "BackdropTemplate")
    bar:SetSize(SB_BAR_W, SB_BAR_H)
    bar:SetPoint("LEFT", 192, 0)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    bar:SetBackdropColor(SB_COL.barBg[1], SB_COL.barBg[2], SB_COL.barBg[3], 1)
    bar:SetBackdropBorderColor(SB_COL.barEdge[1], SB_COL.barEdge[2], SB_COL.barEdge[3], 1)
    bar.segs = {}
    for i = 1, SB_BAR_SEGMENTS do
        local seg = bar:CreateTexture(nil, "ARTWORK")
        seg:SetSize(5, SB_BAR_H - 2)
        seg:SetPoint("LEFT", 3 + (i - 1) * 5, 0)
        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bar.segs[i] = seg
    end
    row.bar = bar

    local num = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    num:SetPoint("LEFT", 272, 0)
    num:SetWidth(24)
    num:SetJustifyH("LEFT")
    num:SetFont(num:GetFont(), 12, "")
    row.num = num

    local tier = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tier:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    tier:SetWidth(28)
    tier:SetJustifyH("RIGHT")
    tier:SetFont(tier:GetFont(), 10, "")
    row.tier = tier

    row:SetScript("OnEnter", function(self)
        if self.data and SB_ShowDetail then SB_ShowDetail(self.data) end
    end)
    row:SetScript("OnLeave", function()
        if SB_ShowDetail then SB_ShowDetail(sbDetailDefault) end
    end)

    return row
end

local function SB_CreateCatBar()
    local bar = CreateFrame("Button", nil, spellChild)
    bar:SetSize(SB_CONTENT_W, SB_CAT_H)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints()
    bg:SetVertexColor(SB_COL.green[1], SB_COL.green[2], SB_COL.green[3], 1)

    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", 6, 0)
    name:SetFont(name:GetFont(), 11, "")
    name:SetTextColor(SB_COL.cream[1], SB_COL.cream[2], SB_COL.cream[3])
    bar.name = name

    local function MakeCol(text, xOffset)
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", xOffset, 0)
        fs:SetFont(fs:GetFont(), 10, "")
        fs:SetTextColor(SB_COL.cream[1], SB_COL.cream[2], SB_COL.cream[3], 0.9)
        fs:SetText(text)
        return fs
    end
    bar.colName = MakeCol("称谓", 34)
    bar.colOfficial = MakeCol("官方", 116)
    bar.colBar = MakeCol("熟练度", 192)

    local colTier = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colTier:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    colTier:SetJustifyH("RIGHT")
    colTier:SetFont(colTier:GetFont(), 10, "")
    colTier:SetTextColor(SB_COL.cream[1], SB_COL.cream[2], SB_COL.cream[3], 0.9)
    colTier:SetText("阶位")
    bar.colTier = colTier

    bar:SetScript("OnClick", function(self)
        if not self.category then return end
        sbCollapsed[self.category] = not sbCollapsed[self.category]
        if sbLastData then UI.RefreshSpellBook(sbLastData) end
    end)

    return bar
end

function SB_ShowDetail(item)
    if not item then
        detailCard:Hide()
        return
    end
    detailCard:Show()
    detailIcon:SetTexture(item.icon or FALLBACK_ICON)
    detailName:SetText(item.name or "?")
    detailDesc:SetText((item.note and item.note ~= "") and item.note or "尚未留下称谓之语。")
    local foot = "官方：" .. (item.official or "?") ..
        "  ·  " .. (item.prof or 0) .. "/" .. (item.maxProf or 0)
    if item.rankIndex and item.rankIndex >= 5 then
        foot = foot .. "  ·  已达宗师"
    elseif item.nextRankName then
        foot = foot .. "  ·  再积累 " .. (item.remainToNext or 1) ..
            " 点升到「" .. item.nextRankName .. "」"
    end
    detailFoot:SetText(foot)
end

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

local sbIconCache = {}
local function SB_GetTexture(official)
    if not official then return FALLBACK_ICON end
    if sbIconCache[official] ~= nil then return sbIconCache[official] end
    local tex
    if type(GetSpellTexture) == "function" then
        local ok, value = pcall(GetSpellTexture, official)
        if ok and value then tex = value end
    end
    if not tex and C_Spell and C_Spell.GetSpellTexture then
        local spellID
        if type(GetSpellInfo) == "function" then
            local okID, _, _, _, _, _, _, id = pcall(GetSpellInfo, official)
            if okID and type(id) == "number" then spellID = id end
        end
        if spellID then
            local ok, value = pcall(C_Spell.GetSpellTexture, spellID)
            if ok and value then tex = value end
        end
    end
    tex = tex or FALLBACK_ICON
    sbIconCache[official] = tex
    return tex
end

-- 阶位：<20% 见习，<50% 熟手，<80% 精通，<100% 大师，=100% 宗师
local function SB_RankInfo(prof, maxProf)
    if maxProf <= 0 then return nil end
    if prof <= 0 then
        return nil, "见习", math.max(1, math.ceil(maxProf * 0.2) - prof)
    end
    local ratio = prof / maxProf
    if ratio >= 1 then return 5 end
    local index, threshold
    if ratio < 0.2 then index, threshold = 1, 0.2
    elseif ratio < 0.5 then index, threshold = 2, 0.5
    elseif ratio < 0.8 then index, threshold = 3, 0.8
    else index, threshold = 4, 1.0 end
    return index, SB_RANKS[index + 1], math.max(1, math.ceil(maxProf * threshold) - prof)
end

function UI.RefreshSpellBook(previewData)
    sbLastData = previewData
    if not previewData then
        sbEmpty:Show()
        sbEmpty:SetText("暂无数据。")
        spellBookHeader:Hide()
        spellScrollFrame:Hide()
        detailCard:Hide()
        return
    end
    spellBookHeader:Show()

    local showProf = (AP_DB.flavor.previewClass == AP_DB.flavor.currentClass)
    local maxProf = GetMaxSkillProf()
    sbTitle:SetText(previewData.name .. " · 称谓典籍")
    -- 等级上限说明不要了，副标题行左边让给「应用到提示」复选框
    sbSubMax:Hide()
    sbSubFormula:Hide()

    -- 回收所有行和分类条，后面按需复用
    for _, row in ipairs(sbRows) do row:Hide() end
    for _, bar in ipairs(sbCatBars) do bar:Hide() end

    local terms = BuildTermList(AP_DB.flavor.previewClass, previewData.id)
    if not terms or #terms == 0 then
        sbEmpty:Show()
        sbEmpty:SetText("该流派暂时没有词条。\n词条库按“职业 → 流派”整理，其他职业会陆续补上。")
        spellScrollFrame:Hide()
        detailCard:Hide()
        sbSubLearned:SetText(showProf and "已修习 0 / 0" or "")
        return
    end
    sbEmpty:Hide()
    spellScrollFrame:Show()
    SB_UpdateHideBtn()

    local spotlightDB = AP_DB.spotlight
    local coreOfficial = spotlightDB and spotlightDB.coreSpell
    local groups, groupMap = {}, {}
    local learned, total = 0, #terms

    for order, term in ipairs(terms) do
        local official = term.official or "?"
        local prof = showProf and GetSkillProf(official) or 0
        if prof > 0 then learned = learned + 1 end

        local displayName = term.alias or official
        if showProf and coreOfficial == official
            and type(spotlightDB.coreAlias) == "string" and spotlightDB.coreAlias ~= "" then
            displayName = spotlightDB.coreAlias
        end

        local rankIndex, nextRankName, remainToNext = SB_RankInfo(prof, maxProf)
        local item = {
            name = displayName,
            official = official,
            note = term.note,
            prof = prof,
            maxProf = maxProf,
            order = order,
            isCore = showProf and coreOfficial == official,
            rankIndex = rankIndex,
            nextRankName = nextRankName,
            remainToNext = remainToNext,
            icon = SB_GetTexture(official),
        }
        local category = term.category or "其他"
        local group = groupMap[category]
        if not group then
            group = { category = category, items = {} }
            groupMap[category] = group
            groups[#groups + 1] = group
        end
        group.items[#group.items + 1] = item
    end

    -- 分类内按熟练度降序；并列时用原顺序（order）做第二关键字，保证稳定
    for _, group in ipairs(groups) do
        table.sort(group.items, function(a, b)
            if a.prof ~= b.prof then return a.prof > b.prof end
            return a.order < b.order
        end)
    end

    -- 德鲁伊的「变形」分类默认放到最后，其他分类保持原顺序
    for i, group in ipairs(groups) do group.order = i end
    if AP_DB.flavor.previewClass == "DRUID" then
        table.sort(groups, function(a, b)
            local am = (a.category == "变形")
            local bm = (b.category == "变形")
            if am ~= bm then return not am end
            return a.order < b.order
        end)
    end

    sbSubLearned:SetText(showProf and ("已修习 " .. learned .. " / " .. total) or "")

    local y = 0
    local rowCount, catCount = 0, 0
    local firstItem

    for _, group in ipairs(groups) do
        local catLearned = 0
        for _, item in ipairs(group.items) do
            if item.prof > 0 then catLearned = catLearned + 1 end
        end
        local collapsed = sbCollapsed[group.category] and true or false

        -- 隐藏未学时，整个分类都没练过就直接跳过
        if not (sbHideUnlearned and catLearned == 0) then
            catCount = catCount + 1
            local catBar = sbCatBars[catCount]
            if not catBar then
                catBar = SB_CreateCatBar()
                sbCatBars[catCount] = catBar
            end
            catBar.category = group.category
            catBar.name:SetText(group.category .. (collapsed
                and ("  " .. catLearned .. "/" .. #group.items) or ""))
            catBar.colName:SetShown(not collapsed)
            catBar.colOfficial:SetShown(not collapsed)
            catBar.colBar:SetShown(not collapsed)
            catBar.colTier:SetShown(not collapsed)
            catBar:SetPoint("TOPLEFT", spellChild, "TOPLEFT", 18, -y)
            catBar:Show()
            y = y + SB_CAT_H + 4

            if not collapsed then
                for _, item in ipairs(group.items) do
                    if not (sbHideUnlearned and item.prof <= 0) then
                        rowCount = rowCount + 1
                        local row = sbRows[rowCount]
                        if not row then
                            row = SB_CreateRow()
                            sbRows[rowCount] = row
                        end
                        row.data = item
                        row:SetPoint("TOPLEFT", spellChild, "TOPLEFT", 18, -y)
                        row:Show()

                        -- 核心技能行用淡红底；其余按偶数行底色
                        if item.isCore then
                            row.bg:SetVertexColor(SB_COL.coreRow[1], SB_COL.coreRow[2], SB_COL.coreRow[3], 1)
                            row.bg:Show()
                        elseif rowCount % 2 == 0 then
                            row.bg:SetVertexColor(SB_COL.rowEven[1], SB_COL.rowEven[2], SB_COL.rowEven[3], 1)
                            row.bg:Show()
                        else
                            row.bg:Hide()
                        end
                        row.mark:SetShown(item.prof > 0)

                        row.icon:SetTexture(item.icon)
                        row.icon:SetDesaturated(not (item.prof > 0))
                        row.icon:SetAlpha(item.prof > 0 and 1 or 0.6)

                        row.name:SetText(item.name or "?")
                        row.name:SetTextColor(
                            item.prof > 0 and SB_COL.ink[1] or SB_COL.soft[1],
                            item.prof > 0 and SB_COL.ink[2] or SB_COL.soft[2],
                            item.prof > 0 and SB_COL.ink[3] or SB_COL.soft[3])

                        row.official:SetText(item.official or "?")
                        row.official:SetTextColor(SB_COL.soft[1], SB_COL.soft[2], SB_COL.soft[3])

                        local ratio = (maxProf > 0) and (item.prof / maxProf) or 0
                        local filled = math.floor(ratio * SB_BAR_SEGMENTS + 0.5)
                        if item.prof > 0 and filled < 1 then filled = 1 end
                        if filled > SB_BAR_SEGMENTS then filled = SB_BAR_SEGMENTS end
                        local fillColor = (item.prof > 0) and SB_COL.green or SB_COL.muted
                        for i = 1, SB_BAR_SEGMENTS do
                            local seg = row.bar.segs[i]
                            if i <= filled then
                                seg:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], 1)
                                seg:Show()
                            else
                                seg:Hide()
                            end
                        end

                        row.num:SetText(tostring(item.prof or 0))
                        row.num:SetTextColor(
                            item.prof > 0 and SB_COL.green[1] or SB_COL.muted[1],
                            item.prof > 0 and SB_COL.green[2] or SB_COL.muted[2],
                            item.prof > 0 and SB_COL.green[3] or SB_COL.muted[3])

                        if item.rankIndex then
                            row.tier:SetText(SB_RANKS[item.rankIndex])
                            row.tier:SetTextColor(SB_COL.gold[1], SB_COL.gold[2], SB_COL.gold[3])
                        else
                            row.tier:SetText("—")
                            row.tier:SetTextColor(SB_COL.muted[1], SB_COL.muted[2], SB_COL.muted[3])
                        end

                        if not firstItem then firstItem = item end
                        y = y + SB_ROW_H + SB_ROW_GAP
                    end
                end
            end
            y = y + SB_CAT_GAP
        end
    end

    for i = rowCount + 1, #sbRows do sbRows[i]:Hide() end
    for i = catCount + 1, #sbCatBars do sbCatBars[i]:Hide() end

    spellChild:SetHeight(math.max(1, y + 6))

    -- 隐藏未学后一个分类都不剩时给个提示，避免以为页面坏了
    if catCount == 0 then
        sbEmpty:Show()
        sbEmpty:SetText("还没有修习任何称谓。\n在战斗中使用技能可以积累熟练度。")
    end

    -- 详情卡默认显示排序后的第一项
    sbDetailDefault = firstItem
    if firstItem then
        SB_ShowDetail(firstItem)
    else
        detailCard:Hide()
    end

    local key = tostring(AP_DB.flavor.previewClass) .. ":" .. tostring(previewData.id)
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
        spellBookHeader:Show()
        spellScrollFrame:Show()
        detailCard:Show()
        sbEmpty:Hide()

        if canToggleAlias then
            tooltipToggle:Show()
        else
            tooltipToggle:Hide()
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
        spellBookHeader:Hide()
        spellScrollFrame:Hide()
        detailCard:Hide()
        sbEmpty:Hide()
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
