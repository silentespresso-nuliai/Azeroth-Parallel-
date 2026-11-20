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

-- 入口控件先声明成 local，后面的 ShowDanmakuPage 才能捕获到它们
local entryBtn, entryHint

local function ShowDanmakuPage(show)
    if show then
        dmPage:Show()
        entryBtn:Hide()
        entryHint:Hide()
    else
        dmPage:Hide()
        entryBtn:Show()
        entryHint:Show()
    end
end

-- 设定页左页：入口按钮
entryBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
entryBtn:SetSize(200, 36)
entryBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, 40)
entryBtn:SetText("聊天弹幕")
entryBtn:SetScript("OnClick", function() ShowDanmakuPage(true) end)

-- 设定页右页：入口说明
entryHint = settingPanel.RightPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
entryHint:SetPoint("TOP", settingPanel.RightPage, "TOP", 0, -120)
entryHint:SetWidth(300)
entryHint:SetJustifyH("CENTER")
entryHint:SetFont(entryHint:GetFont(), 18, "")
entryHint:SetSpacing(10)
entryHint:SetText("|cffd4af37聊天弹幕|r\n\n把小队、团队、公会、密语等聊天消息\n变成从屏幕边缘飘过的弹幕。\n\n点击左侧「聊天弹幕」开始设置。")

-- 弹幕设置子页 · 左栏：频道过滤
local leftTitle = dmPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
leftTitle:SetPoint("TOPLEFT", dmPage, "TOPLEFT", 50, -40)
leftTitle:SetText("弹幕频道过滤：")
leftTitle:SetFont(leftTitle:GetFont(), 22, "OUTLINE")

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
    _G[cb:GetName() .. "Text"]:SetFont(_G[cb:GetName() .. "Text"]:GetFont(), 20, "OUTLINE")
    cb:SetChecked(dmDB.channels[chan.key])
    cb:SetScript("OnClick", function(self) dmDB.channels[chan.key] = self:GetChecked() end)
end

-- 弹幕设置子页 · 右栏：参数
local rightTitle = dmPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
rightTitle:SetPoint("TOPLEFT", dmPage, "TOPLEFT", 500, -40)
rightTitle:SetText("弹幕参数设置：")
rightTitle:SetFont(rightTitle:GetFont(), 22, "OUTLINE")

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
sliderSize:SetValue(dmDB.fontSize)
sliderSize:SetScript("OnValueChanged", function(self, value)
    if type(value) == "number" then dmDB.fontSize = value end
end)

local tip = dmPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tip:SetPoint("TOPLEFT", sliderSize, "BOTTOMLEFT", 0, -50)
tip:SetFont(tip:GetFont(), 16, "OUTLINE")
tip:SetText("|cffaaaaaa提示：调节滑块立即生效。|r")

-- 返回设定页
local backBtn = CreateFrame("Button", nil, dmPage, "UIPanelButtonTemplate")
backBtn:SetSize(120, 28)
backBtn:SetPoint("BOTTOMLEFT", dmPage, "BOTTOMLEFT", 570, 85)
backBtn:SetText("返回设定")
backBtn:SetScript("OnClick", function() ShowDanmakuPage(false) end)
