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
-- UI：设定页入口 + 右页分页
-- ==========================================
-- 所有设定入口统一成：点左页按钮，只切换右页分页，左侧保持不变。
local settingPanel = AP_Panels[1]
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
    btn:SetSize(78, 26) -- 四个分页各 78 宽，加间距正好铺满 340
    local fs = btn:GetFontString()
    if fs then fs:SetFont(fs:GetFont(), 12, "") end
    if #rightTabOrder == 0 then
        btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    else
        btn:SetPoint("LEFT", rightTabOrder[#rightTabOrder], "RIGHT", 8, 0)
    end
    btn:SetText(label)
    btn:SetScript("OnClick", function() SelectRightTab(key) end)
    rightTabOrder[#rightTabOrder + 1] = btn
    rightTabButtons[key] = btn

    -- 每个分页都是一块透明容器，大小铺满分页按钮下方
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
local peersRightPage = AddRightTab("peers", "奇遇社交")

-- 给 Emotes.lua / Peers.lua 用：它们把内容挂到对应分页里。
AP_EmoteSettingsPage = emoteRightPage
AP_ModelSettingsPage = modelRightPage
AP_PeersSettingsPage = peersRightPage
AP_SelectSettingsTab = SelectRightTab

-- 入口按钮登记表保留，但不再隐藏入口；所有按钮都只切右页。
AP_SettingsEntryFrames = AP_SettingsEntryFrames or {}
function AP_RegisterSettingsEntry(frame)
    table.insert(AP_SettingsEntryFrames, frame)
end
AP_CloseDanmakuSettings = function() end

-- 设定页左页：四个入口统一只切换右页分页
local entryBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
entryBtn:SetSize(200, 36)
entryBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, 40)
entryBtn:SetText("聊天弹幕")
entryBtn:SetScript("OnClick", function() SelectRightTab("danmaku") end)
AP_RegisterSettingsEntry(entryBtn)

-- ---------- 聊天弹幕分页内容 ----------
local dmTitle = danmakuRightPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
dmTitle:SetPoint("TOPLEFT", danmakuRightPage, "TOPLEFT", 30, -2)
dmTitle:SetText("聊天弹幕")
dmTitle:SetFont(dmTitle:GetFont(), 20, "")
dmTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local channelsTitle = danmakuRightPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
channelsTitle:SetPoint("TOPLEFT", danmakuRightPage, "TOPLEFT", 30, -36)
channelsTitle:SetText("频道过滤")
channelsTitle:SetFont(channelsTitle:GetFont(), 14, "")
channelsTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local channelsList = {
    { key = "SAY", name = "说 (/s)" }, { key = "YELL", name = "喊 (/y)" },
    { key = "PARTY", name = "小队 (/p)" }, { key = "RAID", name = "团队 (/ra)" },
    { key = "CHANNEL", name = "频道 (/1, /2)" }, { key = "WHISPER", name = "密语" },
    { key = "GUILD", name = "公会 (/g)" },
}

for i, chan in ipairs(channelsList) do
    local cb = CreateFrame("CheckButton", "AP_CB" .. i, danmakuRightPage, "ChatConfigCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", danmakuRightPage, "TOPLEFT", 30, -62 - ((i - 1) * 30))
    _G[cb:GetName() .. "Text"]:SetText(chan.name)
    _G[cb:GetName() .. "Text"]:SetFont(_G[cb:GetName() .. "Text"]:GetFont(), 15, "")
    _G[cb:GetName() .. "Text"]:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
    cb:SetChecked(dmDB.channels[chan.key])
    cb:SetScript("OnClick", function(self) dmDB.channels[chan.key] = self:GetChecked() end)
end

local paramTitle = danmakuRightPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
paramTitle:SetPoint("TOPLEFT", danmakuRightPage, "TOPLEFT", 30, -276)
paramTitle:SetText("参数")
paramTitle:SetFont(paramTitle:GetFont(), 14, "")
paramTitle:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local sliderSpeed = CreateFrame("Slider", "AP_SpeedSlider", danmakuRightPage, "OptionsSliderTemplate")
sliderSpeed:SetPoint("TOPLEFT", danmakuRightPage, "TOPLEFT", 30, -316)
sliderSpeed:SetWidth(300)
sliderSpeed:SetMinMaxValues(5, 30)
sliderSpeed:SetValueStep(1)
sliderSpeed:SetObeyStepOnDrag(true)
_G[sliderSpeed:GetName() .. "Low"]:SetText("快(5s)")
_G[sliderSpeed:GetName() .. "High"]:SetText("慢(30s)")
_G[sliderSpeed:GetName() .. "Text"]:SetText("飞行时间 (秒)")
_G[sliderSpeed:GetName() .. "Text"]:SetFont(_G[sliderSpeed:GetName() .. "Text"]:GetFont(), 15, "")
for _, suffix in ipairs({ "Low", "High", "Text" }) do
    local fs = _G[sliderSpeed:GetName() .. suffix]
    if fs then fs:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3]) end
end
sliderSpeed:SetValue(dmDB.time)
sliderSpeed:SetScript("OnValueChanged", function(self, value)
    if type(value) == "number" then dmDB.time = value end
end)

local sliderSize = CreateFrame("Slider", "AP_SizeSlider", danmakuRightPage, "OptionsSliderTemplate")
sliderSize:SetPoint("TOPLEFT", sliderSpeed, "BOTTOMLEFT", 0, -60)
sliderSize:SetWidth(300)
sliderSize:SetMinMaxValues(10, 40)
sliderSize:SetValueStep(2)
sliderSize:SetObeyStepOnDrag(true)
_G[sliderSize:GetName() .. "Low"]:SetText("小")
_G[sliderSize:GetName() .. "High"]:SetText("大")
_G[sliderSize:GetName() .. "Text"]:SetText("字体大小")
_G[sliderSize:GetName() .. "Text"]:SetFont(_G[sliderSize:GetName() .. "Text"]:GetFont(), 15, "")
for _, suffix in ipairs({ "Low", "High", "Text" }) do
    local fs = _G[sliderSize:GetName() .. suffix]
    if fs then fs:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3]) end
end
sliderSize:SetValue(dmDB.fontSize)
sliderSize:SetScript("OnValueChanged", function(self, value)
    if type(value) == "number" then dmDB.fontSize = value end
end)

local tip = danmakuRightPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tip:SetPoint("TOPLEFT", sliderSize, "BOTTOMLEFT", 0, -36)
tip:SetFont(tip:GetFont(), 13, "")
tip:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
tip:SetText("|cff6b5a45提示：调节滑块立即生效。|r")

-- 默认停在「表情与动作」分页
SelectRightTab("emote")
