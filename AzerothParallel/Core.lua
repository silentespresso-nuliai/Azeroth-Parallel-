-- ==========================================
-- Core.lua: 核心框架与公共资源
-- ==========================================

AP_DB = AP_DB or {}
AP_DB.danmaku = AP_DB.danmaku or {}
AP_DB.flavor = AP_DB.flavor or {}

AP_MainFrame = CreateFrame("Frame", "AP_MainFrame", UIParent, "BasicFrameTemplateWithInset")
AP_MainFrame:SetSize(900, 650)
AP_MainFrame:SetPoint("CENTER")
AP_MainFrame:SetMovable(true)
AP_MainFrame:EnableMouse(true)
AP_MainFrame:RegisterForDrag("LeftButton")
AP_MainFrame:SetScript("OnDragStart", AP_MainFrame.StartMoving)
AP_MainFrame:SetScript("OnDragStop", AP_MainFrame.StopMovingOrSizing)
AP_MainFrame:Hide()

AP_MainFrame.TitleBg:SetHeight(40)
AP_MainFrame.title = AP_MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
AP_MainFrame.title:SetPoint("CENTER", AP_MainFrame.TitleBg, "CENTER", 0, 0)
AP_MainFrame.title:SetText("艾泽拉斯平行宇宙 (Azeroth Parallel)")
AP_MainFrame.title:SetFont(AP_MainFrame.title:GetFont(), 20, "OUTLINE")

local bookBg = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}

AP_Tabs = {}
AP_Panels = {}
local tabNames = { "设定", "职业流派", "奇遇社交", "高光特写" }

local function SelectTab(index)
    for i = 1, #AP_Tabs do
        if i == index then
            AP_Tabs[i]:SetButtonState("PUSHED", true)
            AP_Panels[i]:Show()
        else
            AP_Tabs[i]:SetButtonState("NORMAL", false)
            AP_Panels[i]:Hide()
        end
    end
end

for i = 1, 4 do
    -- ★ 核心修改：放弃 PanelTabButtonTemplate，改用最干净的 UIPanelButtonTemplate
    local tab = CreateFrame("Button", "AP_Tab" .. i, AP_MainFrame, "UIPanelButtonTemplate")
    tab:SetSize(120, 28)
    tab:SetText(tabNames[i])

    if i == 1 then
        tab:SetPoint("BOTTOMLEFT", AP_MainFrame, "BOTTOMLEFT", 20, -25)
    else
        tab:SetPoint("LEFT", AP_Tabs[i - 1], "RIGHT", 10, 0)
    end
    AP_Tabs[i] = tab

    local panel = CreateFrame("Frame", "AP_Panel" .. i, AP_MainFrame)
    panel:SetAllPoints(AP_MainFrame)
    AP_Panels[i] = panel

    local left = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    left:SetSize(400, 540)
    left:SetPoint("TOPLEFT", 25, -50)
    left:SetBackdrop(bookBg)
    left:SetBackdropColor(0.2, 0.15, 0.1, 1)
    panel.LeftPage = left

    local right = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    right:SetSize(400, 540)
    right:SetPoint("TOPRIGHT", -25, -50)
    right:SetBackdrop(bookBg)
    right:SetBackdropColor(0.2, 0.15, 0.1, 1)
    panel.RightPage = right

    tab:SetScript("OnClick", function() SelectTab(i) end)
end
-- 默认打开第 2 页（职业流派）。第 1 页“设定”目前还是空的，先不做默认页，避免一开面板就是白纸。
SelectTab(2)

SLASH_AZEROTHPARALLEL1 = "/AP"
SlashCmdList["AZEROTHPARALLEL"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "addrep" then
        local amount = tonumber(arg)
        if amount and AP_FlavorManager and AP_FlavorManager.AddReputation then
            AP_FlavorManager.AddReputation(amount)
        end
        return
    end
    -- 如果没加参数，或者输入其他内容，就开关面板
    if AP_MainFrame:IsShown() then AP_MainFrame:Hide() else AP_MainFrame:Show() end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    print("|cff00ff00++++++++++++++++++++++++|r")
    print("|cff00ff00+|r |cffd4af37AP: Azeroth Parallel|r |cff00ff00+|r")
    print("|cff00ff00+|r |cffffcc00Type /AP to open UI|r  |cff00ff00+|r")
    print("|cff00ff00++++++++++++++++++++++++|r")
end)
