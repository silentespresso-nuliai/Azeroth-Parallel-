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
danmakuContainer:SetFrameStrata("BACKGROUND")
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
eventFrame:SetScript("OnEvent", function(self, event, text, author, languageName)
    if not text or text == "" then return end
    if dmDB.channels[events[event]] then CreateDanmaku(text, author, events[event], languageName) end
end)

-- ==========================================
-- UI 排版 (挂载到 p2 的左右页)
-- ==========================================
local p2 = AP_Panels[2]
local LeftPage = p2.LeftPage
local RightPage = p2.RightPage

-- 左页
local leftTitle = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
leftTitle:SetPoint("TOPLEFT", 20, -20) -- 这里改成 50， -20
leftTitle:SetText("弹幕频道过滤：")
leftTitle:SetFont(leftTitle:GetFont(), 22, "OUTLINE")

local channelsList = {
    { key = "SAY", name = "说 (/s)" }, { key = "YELL", name = "喊 (/y)" },
    { key = "PARTY", name = "小队 (/p)" }, { key = "RAID", name = "团队 (/ra)" },
    { key = "CHANNEL", name = "频道 (/1, /2)" }, { key = "WHISPER", name = "密语" },
    { key = "GUILD", name = "公会 (/g)" },
}

for i, chan in ipairs(channelsList) do
    local cb = CreateFrame("CheckButton", "AP_CB" .. i, LeftPage, "ChatConfigCheckButtonTemplate")
    -- 从 leftTitle 往下 25 像素开始，每行间隔 40
    cb:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -25 - ((i - 1) * 40))
    _G[cb:GetName() .. "Text"]:SetText(chan.name)
    _G[cb:GetName() .. "Text"]:SetFont(_G[cb:GetName() .. "Text"]:GetFont(), 20, "OUTLINE") -- 字号顶到 20
    cb:SetChecked(dmDB.channels[chan.key])
    cb:SetScript("OnClick", function(self) dmDB.channels[chan.key] = self:GetChecked() end)
end

-- 右页
local rightTitle = RightPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
rightTitle:SetPoint("TOPLEFT", 55, -30) -- X 从 35 改为 55
rightTitle:SetText("弹幕参数设置：")
rightTitle:SetFont(rightTitle:GetFont(), 22, "OUTLINE")

local sliderSpeed = CreateFrame("Slider", "AP_SpeedSlider", RightPage, "OptionsSliderTemplate")
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

local sliderSize = CreateFrame("Slider", "AP_SizeSlider", RightPage, "OptionsSliderTemplate")
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

local tip = RightPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tip:SetPoint("TOPLEFT", sliderSize, "BOTTOMLEFT", 0, -50)
tip:SetFont(tip:GetFont(), 16, "OUTLINE")
tip:SetText("|cffaaaaaa提示：调节滑块立即生效。|r")
