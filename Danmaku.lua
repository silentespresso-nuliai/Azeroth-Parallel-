-- ==========================================
-- Danmaku.lua: 独立人生 - 弹幕子模块 (超大字体版)
-- ==========================================

local dmDB = AP_DB.danmaku
-- 强制把初始时间设为 17，并将字体大小居中设为 25
if type(dmDB.time) ~= "number" or dmDB.time == 12 then
    dmDB.time = 17
end
if type(dmDB.fontSize) ~= "number" then
    dmDB.fontSize = 25
end
dmDB.channels = dmDB.channels or {
    ["SAY"] = true,
    ["YELL"] = false,
    ["PARTY"] = true,
    ["RAID"] = true,
    ["CHANNEL"] = false,
    ["WHISPER"] = true,
    ["GUILD"] = true,
}

-- 弹幕核心逻辑 (保持不变)
local MAX_DANMAKU = 20
local danmakuContainer = CreateFrame("Frame", "AP_DanmakuContainer", UIParent)
danmakuContainer:SetAllPoints(UIParent)
-- 弹幕放在 MEDIUM：既不会被动作条、团队框架等普通 UI 盖住，
-- 又不会像 HIGH/TOOLTIP 那样压住鼠标提示和弹窗。
-- 容器默认不接收鼠标，不会挡住任何点击。
danmakuContainer:SetFrameStrata("MEDIUM")
local activeDanmakuCount = 0

local function CreateDanmaku(text, author, chatType, languageName)
    if activeDanmakuCount >= MAX_DANMAKU then return end
    local danmaku = danmakuContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    danmaku:SetFont(danmaku:GetFont(), dmDB.fontSize, "OUTLINE")

    local colorPrefix = "|cffffffff"
    if chatType == "WHISPER" then
        colorPrefix = "|cffff80ff" -- 密语粉色
    elseif chatType == "GUILD" then
        colorPrefix = "|cff40ff40" -- ★ 强制指定公会聊天为经典亮绿色
    elseif ChatTypeInfo and ChatTypeInfo[chatType] then
        -- 如果系统有 colorStr 就用，没有的话用 RGB 数值拼凑，保证不丢颜色
        if ChatTypeInfo[chatType].colorStr and ChatTypeInfo[chatType].colorStr ~= "" then
            colorPrefix = ChatTypeInfo[chatType].colorStr
        elseif ChatTypeInfo[chatType].r then
            local r, g, b = ChatTypeInfo[chatType].r, ChatTypeInfo[chatType].g, ChatTypeInfo[chatType].b
            colorPrefix = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
        end
    end

    local langPrefix = ""
    if languageName and languageName ~= "" then langPrefix = "[" .. languageName .. "] " end
    local displayAuthor = author or "未知"

    danmaku:SetText(colorPrefix .. langPrefix .. displayAuthor .. ": " .. text .. "|r")
    danmaku:SetJustifyH("LEFT")

    local textWidth = danmaku:GetStringWidth()
    local screenWidth = UIParent:GetWidth()
    local trackIndex = (activeDanmakuCount % 10) + 1
    local yPos = -50 - ((trackIndex - 1) * (dmDB.fontSize + 10))

    danmaku:SetPoint("TOPLEFT", danmakuContainer, "TOPLEFT", screenWidth, yPos)
    activeDanmakuCount = activeDanmakuCount + 1

    local baseDuration = dmDB.time or 12
    local totalDistance = screenWidth + textWidth
    local speedMultiplier = 1
    local thresholdWidth = screenWidth * 0.4
    if textWidth > thresholdWidth then
        speedMultiplier = 1 + ((textWidth - thresholdWidth) / screenWidth) * 1.5
        if speedMultiplier > 2.5 then speedMultiplier = 2.5 end
    end

    local animGroup = danmaku:CreateAnimationGroup()
    local translation = animGroup:CreateAnimation("Translation")
    translation:SetDuration(baseDuration / speedMultiplier)
    translation:SetOffset(-totalDistance, 0)
    translation:SetSmoothing("OUT")

    animGroup:SetScript("OnFinished", function()
        danmaku:Hide()
        danmaku:SetParent(nil)
        activeDanmakuCount = activeDanmakuCount - 1
    end)
    animGroup:Play()
end

local eventFrame = CreateFrame("Frame")
local events = {
    ["CHAT_MSG_SAY"] = "SAY",
    ["CHAT_MSG_YELL"] = "YELL",
    ["CHAT_MSG_PARTY"] = "PARTY",
    ["CHAT_MSG_RAID"] =
    "RAID",
    ["CHAT_MSG_CHANNEL"] = "CHANNEL",
    ["CHAT_MSG_WHISPER"] = "WHISPER",
    ["CHAT_MSG_GUILD"] = "GUILD"
}
for eventName in pairs(events) do eventFrame:RegisterEvent(eventName) end
-- 新客户端会把聊天内容标记成 secret string，插件不能读取、比较或拼接。
-- 这类消息只能安静跳过，否则每次队伍聊天、团队聊天都会刷屏报错。
local hasSecretAPI = type(issecretvalue) == "function"
local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

eventFrame:SetScript("OnEvent", function(self, event, text, author, languageName)
    if IsSecret(text) or IsSecret(author) or IsSecret(languageName) then return end
    if not text or text == "" then return end
    if dmDB.channels[events[event]] then CreateDanmaku(text, author, events[event], languageName) end
end)

-- ==========================================
-- UI：设定页入口 + 弹幕设置子页
-- ==========================================
-- 设定页对应 AP_Panels[1]。第 2 页“职业流派”已经被 Flavor.lua 占用，
-- 所以弹幕设置只能放在这里，否则两套界面会叠在一起。
local settingPanel = AP_Panels[1]

-- 设置子页：透明地盖在设定页上，默认隐藏。
-- 不另画书页背景，露出来的就是 Core.lua 造好的左右两页。
local dmPage = CreateFrame("Frame", "AP_DanmakuPage", settingPanel)
dmPage:SetAllPoints(settingPanel)
-- 抬高一层，确保设置控件盖在左右书页背景之上
dmPage:SetFrameLevel(settingPanel:GetFrameLevel() + 2)
dmPage:Hide()

-- ==========================================
-- 设定页右页分页器：聊天弹幕 / 表情与动作
-- 右页只有一个页面大小，两套说明和编辑框同时铺开会叠在一起，
-- 所以做成两个切换按钮，同一时间只显示其中一页。
-- ==========================================
local rightRoot = settingPanel.RightPage

local tabBar = CreateFrame("Frame", nil, rightRoot)
tabBar:SetSize(340, 28)
tabBar:SetPoint("TOP", rightRoot, "TOP", 0, -12)

local RIGHT_CONTENT_TOP = -48 -- 分页按钮占掉的高度，内容从这条线往下排
local rightPages = {}
local rightTabButtons = {}
local rightTabOrder = {}
local activeRightTab

local function SelectRightTab(key)
    activeRightTab = key
    for k, page in pairs(rightPages) do
        if k == key then page:Show() else page:Hide() end
    end
    for k, btn in pairs(rightTabButtons) do
        if k == key then
            btn:SetButtonState("PUSHED", true)
        else
            btn:SetButtonState("NORMAL", false)
        end
    end
end

local function AddRightTab(key, label)
    local btn = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    btn:SetSize(108, 26) -- 三个分页各 108 宽，正好铺满 340
    if #rightTabOrder == 0 then
        btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    else
        btn:SetPoint("LEFT", rightTabOrder[#rightTabOrder], "RIGHT", 8, 0)
    end
    btn:SetText(label)
    btn:SetScript("OnClick", function() SelectRightTab(key) end)
    rightTabOrder[#rightTabOrder + 1] = btn
    rightTabButtons[key] = btn

    -- 每个分页都是一块透明的容器，大小刚好铺满分页按钮下方
    local page = CreateFrame("Frame", nil, rightRoot)
    page:SetPoint("TOPLEFT", rightRoot, "TOPLEFT", 0, RIGHT_CONTENT_TOP)
    page:SetPoint("BOTTOMRIGHT", rightRoot, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    rightPages[key] = page
    return page
end

local danmakuRightPage = AddRightTab("danmaku", "聊天弹幕")
local emoteRightPage = AddRightTab("emote", "表情动作")
local modelRightPage = AddRightTab("model", "正面形象")

-- 给 Emotes.lua 用：它把说明、开关和自定义编辑框挂到这两个分页里，
-- 并且通过 AP_SelectSettingsTab 切换分页。
AP_EmoteSettingsPage = emoteRightPage
AP_ModelSettingsPage = modelRightPage
AP_SelectSettingsTab = SelectRightTab

-- 打开弹幕设置子页时，整个右页分页区（按钮 + 内容）都要藏起来，
-- 否则会透到弹幕设置控件后面。返回后再按上次选中的分页恢复。
local function SetRightPaneVisible(visible)
    if visible then
        tabBar:Show()
        SelectRightTab(activeRightTab or "emote")
    else
        tabBar:Hide()
        for _, page in pairs(rightPages) do page:Hide() end
    end
end

-- 设定页上各个入口按钮的登记表：打开子页时统一隐藏，返回时恢复。
-- Emotes.lua 加载在后，会通过这个函数把自己的入口按钮也登记进来。
AP_SettingsEntryFrames = AP_SettingsEntryFrames or {}
function AP_RegisterSettingsEntry(frame)
    table.insert(AP_SettingsEntryFrames, frame)
    if dmPage:IsShown() then frame:Hide() end
end

-- 入口控件先声明成 local，后面的 ShowDanmakuPage 才能捕获到它们
local entryBtn, entryHint

local function ShowDanmakuPage(show)
    if show then
        dmPage:Show()
        SetRightPaneVisible(false)
        -- 两个模块的入口按钮一起藏，否则会从子页的空白处透出来
        for _, frame in ipairs(AP_SettingsEntryFrames) do frame:Hide() end
    else
        dmPage:Hide()
        for _, frame in ipairs(AP_SettingsEntryFrames) do frame:Show() end
        SetRightPaneVisible(true)
    end
end

-- 给其他模块用：从卡片图标打开设定页时，先退出弹幕子页
AP_CloseDanmakuSettings = function()
    if dmPage:IsShown() then ShowDanmakuPage(false) end
end

-- 设定页左页：入口按钮
entryBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
entryBtn:SetSize(200, 36)
entryBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, 40)
entryBtn:SetText("聊天弹幕")
entryBtn:SetScript("OnClick", function() ShowDanmakuPage(true) end)
AP_RegisterSettingsEntry(entryBtn)

-- 设定页右页「聊天弹幕」分页：入口说明
entryHint = danmakuRightPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
entryHint:SetPoint("TOP", danmakuRightPage, "TOP", 0, -30)
entryHint:SetWidth(340)
entryHint:SetJustifyH("CENTER")
entryHint:SetFont(entryHint:GetFont(), 18, "")
entryHint:SetSpacing(10)
entryHint:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
entryHint:SetText("|cff8c261a聊天弹幕|r\n\n把小队、团队、公会、密语等聊天消息\n变成从屏幕边缘飘过的弹幕。\n\n点击左侧「聊天弹幕」开始设置。")

-- 默认停在「表情与动作」分页：那里有可以直接编辑的自定义按钮。
-- 想看弹幕说明就点上方分页，或点左侧「聊天弹幕」进入详细设置。
SelectRightTab("emote")

-- 弹幕设置子页 · 左栏：频道过滤
local leftTitle = dmPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
leftTitle:SetPoint("TOPLEFT", dmPage, "TOPLEFT", 50, -40)
leftTitle:SetText("弹幕频道过滤：")
leftTitle:SetFont(leftTitle:GetFont(), 22, "")
leftTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local channelsList = {
    { key = "SAY", name = "说 (/s)" }, { key = "YELL", name = "喊 (/y)" },
    { key = "PARTY", name = "小队 (/p)" }, { key = "RAID", name = "团队 (/ra)" },
    { key = "CHANNEL", name = "频道 (/1, /2)" }, { key = "WHISPER", name = "密语" },
    { key = "GUILD", name = "公会 (/g)" },
}

for i, chan in ipairs(channelsList) do
    local cb = CreateFrame("CheckButton", "AP_CB" .. i, dmPage, "ChatConfigCheckButtonTemplate")
    -- 从 leftTitle 往下 25 像素开始，每行间隔 40
    cb:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -25 - ((i - 1) * 40))
    _G[cb:GetName() .. "Text"]:SetText(chan.name)
    _G[cb:GetName() .. "Text"]:SetFont(_G[cb:GetName() .. "Text"]:GetFont(), 20, "")
    _G[cb:GetName() .. "Text"]:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    cb:SetChecked(dmDB.channels[chan.key])
    cb:SetScript("OnClick", function(self) dmDB.channels[chan.key] = self:GetChecked() end)
end

-- 弹幕设置子页 · 右栏：参数
local rightTitle = dmPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
rightTitle:SetPoint("TOPLEFT", dmPage, "TOPLEFT", 500, -40)
rightTitle:SetText("弹幕参数设置：")
rightTitle:SetFont(rightTitle:GetFont(), 22, "")
rightTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local sliderSpeed = CreateFrame("Slider", "AP_SpeedSlider", dmPage, "OptionsSliderTemplate")
sliderSpeed:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -60)
sliderSpeed:SetWidth(300)
sliderSpeed:SetMinMaxValues(5, 30)
sliderSpeed:SetValueStep(1)
sliderSpeed:SetObeyStepOnDrag(true)
_G[sliderSpeed:GetName() .. "Low"]:SetText("快(5s)")
_G[sliderSpeed:GetName() .. "High"]:SetText("慢(30s)")
_G[sliderSpeed:GetName() .. "Text"]:SetText("飞行时间 (秒)")
_G[sliderSpeed:GetName() .. "Text"]:SetFont(_G[sliderSpeed:GetName() .. "Text"]:GetFont(), 18, "")
for _, suffix in ipairs({ "Low", "High", "Text" }) do
    local fs = _G[sliderSpeed:GetName() .. suffix]
    if fs then fs:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3]) end
end
sliderSpeed:SetValue(dmDB.time)
sliderSpeed:SetScript("OnValueChanged", function(self, value)
    if type(value) == "number" then dmDB.time = value end
end)

local sliderSize = CreateFrame("Slider", "AP_SizeSlider", dmPage, "OptionsSliderTemplate")
sliderSize:SetPoint("TOPLEFT", sliderSpeed, "BOTTOMLEFT", 0, -80)
sliderSize:SetWidth(300)
sliderSize:SetMinMaxValues(10, 40)
sliderSize:SetValueStep(2)
sliderSize:SetObeyStepOnDrag(true)
_G[sliderSize:GetName() .. "Low"]:SetText("小")
_G[sliderSize:GetName() .. "High"]:SetText("大")
_G[sliderSize:GetName() .. "Text"]:SetText("字体大小")
_G[sliderSize:GetName() .. "Text"]:SetFont(_G[sliderSize:GetName() .. "Text"]:GetFont(), 18, "")
for _, suffix in ipairs({ "Low", "High", "Text" }) do
    local fs = _G[sliderSize:GetName() .. suffix]
    if fs then fs:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3]) end
end
sliderSize:SetValue(dmDB.fontSize)
sliderSize:SetScript("OnValueChanged", function(self, value)
    if type(value) == "number" then dmDB.fontSize = value end
end)

local tip = dmPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tip:SetPoint("TOPLEFT", sliderSize, "BOTTOMLEFT", 0, -50)
tip:SetFont(tip:GetFont(), 16, "")
tip:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
tip:SetText("|cff6b5a45提示：调节滑块立即生效。|r")

-- 返回设定页
local backBtn = CreateFrame("Button", nil, dmPage, "UIPanelButtonTemplate")
backBtn:SetSize(120, 28)
backBtn:SetPoint("BOTTOMLEFT", dmPage, "BOTTOMLEFT", 570, 85)
backBtn:SetText("返回设定")
backBtn:SetScript("OnClick", function() ShowDanmakuPage(false) end)
