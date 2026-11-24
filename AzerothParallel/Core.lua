-- ==========================================
-- Core.lua: 核心框架与公共资源（翻开的冒险日记）
-- ==========================================

AP_DB = AP_DB or {}
AP_DB.danmaku = AP_DB.danmaku or {}
AP_DB.flavor = AP_DB.flavor or {}

local MEDIA = "Interface\\AddOns\\AzerothParallel\\Media\\"

-- ------------------------------------------
-- 公共主题：书页是浅色羊皮纸，文字要用深色“墨水”色，
-- 别的模块（弹幕、社交、高光）想和书页统一，直接读这张表就行
-- ------------------------------------------
AP_Theme = {
    media    = MEDIA,
    ink      = { 0.20, 0.13, 0.06 },   -- 正文墨水（柔和深棕，避免发黑）
    inkSoft  = { 0.34, 0.24, 0.13 },   -- 次要文字
    accent   = { 0.55, 0.15, 0.10 },   -- 强调色（暗红，用于标题、选中）
    cream    = { 1.00, 0.95, 0.82 },   -- 深色底上的浅色字
    line     = { 0.24, 0.15, 0.07 },   -- 分割线、描边
}
-- 方便给文字上色：AP_Theme.Paint(fontString, "ink" | "inkSoft" | "accent" | "cream")
function AP_Theme.Paint(fs, key)
    local c = AP_Theme[key or "ink"] or AP_Theme.ink
    fs:SetTextColor(c[1], c[2], c[3])
end

-- ------------------------------------------
-- 主窗口：一本书
-- ------------------------------------------
local BOOK_W, BOOK_H = 900, 650
local TEX_SIZE = 1024   -- Book.tga 的画布大小（书在左上角 900x650）

AP_MainFrame = CreateFrame("Frame", "AP_MainFrame", UIParent)
AP_MainFrame:SetSize(BOOK_W, BOOK_H)
AP_MainFrame:SetPoint("CENTER")
AP_MainFrame:SetMovable(true)
AP_MainFrame:EnableMouse(true)
AP_MainFrame:SetClampedToScreen(true)
AP_MainFrame:RegisterForDrag("LeftButton")
AP_MainFrame:SetScript("OnDragStart", AP_MainFrame.StartMoving)
AP_MainFrame:SetScript("OnDragStop", AP_MainFrame.StopMovingOrSizing)
AP_MainFrame:Hide()
tinsert(UISpecialFrames, "AP_MainFrame") -- ESC 关闭

local bookArt = AP_MainFrame:CreateTexture(nil, "BACKGROUND")
bookArt:SetAllPoints()
bookArt:SetTexture(MEDIA .. "Book.tga")
bookArt:SetTexCoord(0, BOOK_W / TEX_SIZE, 0, BOOK_H / TEX_SIZE)
-- 原图偏亮，压暗并略偏暖，浅色字/纹理不会发白刺眼
bookArt:SetVertexColor(0.84, 0.78, 0.70)
AP_MainFrame.bookArt = bookArt

-- 兼容旧代码：以前的 BasicFrameTemplate 带有 TitleBg / title / CloseButton，
-- 其他文件如果引用过，这里给出隐藏的替身，避免报 nil
AP_MainFrame.TitleBg = AP_MainFrame:CreateTexture(nil, "BACKGROUND")
AP_MainFrame.TitleBg:Hide()
AP_MainFrame.title = AP_MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
AP_MainFrame.title:SetText("艾泽拉斯平行宇宙 (Azeroth Parallel)")
AP_MainFrame.title:Hide()

-- 右上角关闭按钮（金色小叉，压在书角上）
local closeBtn = CreateFrame("Button", nil, AP_MainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", AP_MainFrame, "TOPRIGHT", 6, 6)
closeBtn:SetFrameLevel(AP_MainFrame:GetFrameLevel() + 40)
AP_MainFrame.CloseButton = closeBtn

-- ------------------------------------------
-- 页签 = 从书底垂下来的彩色书签丝带
-- 贴图是 Media/Ribbon.tga（燕尾缺口在左），这里用 SetTexCoord 旋转 90° 让缺口朝下
-- ------------------------------------------
AP_Tabs = {}
AP_Panels = {}
local tabNames = { "设定", "职业流派", "奇遇社交", "核心" }
local tabLabels = { "设定", "职业\n流派", "奇遇\n社交", "高光\n特写" }
local tabColors = {
    { 0.27, 0.58, 0.34 },   -- 绿
    { 0.70, 0.17, 0.15 },   -- 红
    { 0.48, 0.28, 0.66 },   -- 紫
    { 0.56, 0.56, 0.60 },   -- 灰
}

local TAB_W, TAB_H = 46, 104
local TAB_TUCK = 16            -- 丝带缝进书里的长度
local TAB_POP_SELECTED = 12    -- 选中的丝带多垂下多少
local TAB_POP_HOVER = 6
local TAB_X0, TAB_STEP = 110, 54

local ROT_UL_X, ROT_UL_Y, ROT_LL_X, ROT_LL_Y, ROT_UR_X, ROT_UR_Y, ROT_LR_X, ROT_LR_Y = 1, 0, 0, 0, 1, 1, 0, 1

local function ApplyTabLayout(tab)
    local pop = 0
    if tab.isSelected then
        pop = TAB_POP_SELECTED
    elseif tab.isHover then
        pop = TAB_POP_HOVER
    end
    tab:ClearAllPoints()
    tab:SetPoint("TOP", AP_MainFrame, "BOTTOMLEFT", tab.baseX, TAB_TUCK - pop)
    tab.body:SetAlpha(tab.isSelected and 1 or 0.9)
end

local function SelectTab(index)
    for i = 1, #AP_Tabs do
        AP_Tabs[i].isSelected = (i == index)
        ApplyTabLayout(AP_Tabs[i])
        if i == index then
            AP_Panels[i]:Show()
        else
            AP_Panels[i]:Hide()
        end
    end
end

-- 给其他模块（例如称谓典籍里的“前往核心培养”按钮）切页用
AP_SelectTab = SelectTab

for i = 1, 4 do
    local c = tabColors[i]
    local tab = CreateFrame("Button", "AP_Tab" .. i, AP_MainFrame)
    tab:SetSize(TAB_W, TAB_H)
    tab:SetFrameLevel(AP_MainFrame:GetFrameLevel() + 30)
    tab.baseX = TAB_X0 + (i - 1) * TAB_STEP
    tab.tabName = tabNames[i]

    -- 阴影
    local shadow = tab:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(MEDIA .. "Ribbon.tga")
    shadow:SetTexCoord(ROT_UL_X, ROT_UL_Y, ROT_LL_X, ROT_LL_Y, ROT_UR_X, ROT_UR_Y, ROT_LR_X, ROT_LR_Y)
    shadow:SetVertexColor(0, 0, 0, 0.4)
    shadow:SetPoint("TOPLEFT", tab, "TOPLEFT", 3, -3)
    shadow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 3, -3)

    -- 丝带
    local body = tab:CreateTexture(nil, "ARTWORK")
    body:SetTexture(MEDIA .. "Ribbon.tga")
    body:SetTexCoord(ROT_UL_X, ROT_UL_Y, ROT_LL_X, ROT_LL_Y, ROT_UR_X, ROT_UR_Y, ROT_LR_X, ROT_LR_Y)
    body:SetAllPoints()
    body:SetVertexColor(c[1], c[2], c[3])
    tab.body = body

    -- 悬停提亮
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(MEDIA .. "Ribbon.tga")
    hl:SetTexCoord(ROT_UL_X, ROT_UL_Y, ROT_LL_X, ROT_LL_Y, ROT_UR_X, ROT_UR_Y, ROT_LR_X, ROT_LR_Y)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.3)
    hl:SetBlendMode("ADD")

    -- 文字：每行两个字，竖着排
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 2)
    label:SetJustifyH("CENTER")
    label:SetSpacing(2)
    label:SetText(tabLabels[i])
    local fontPath = label:GetFont()
    label:SetFont(fontPath, 14, "OUTLINE")
    label:SetTextColor(1, 0.96, 0.86)
    tab.label = label

    tab:SetScript("OnEnter", function(self) self.isHover = true; ApplyTabLayout(self) end)
    tab:SetScript("OnLeave", function(self) self.isHover = false; ApplyTabLayout(self) end)
    tab:SetScript("OnClick", function() SelectTab(i) end)
    AP_Tabs[i] = tab
    ApplyTabLayout(tab)

    -- 每一页：覆盖整本书，左右两页是透明的容器（书页的底图由 Book.tga 统一提供）
    local panel = CreateFrame("Frame", "AP_Panel" .. i, AP_MainFrame)
    panel:SetAllPoints(AP_MainFrame)
    AP_Panels[i] = panel

    local left = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    left:SetSize(400, 540)
    left:SetPoint("TOPLEFT", 25, -50)
    panel.LeftPage = left

    local right = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    right:SetSize(400, 540)
    right:SetPoint("TOPRIGHT", -25, -50)
    panel.RightPage = right
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
    -- /AP emote：开关“表情动作”图标面板（也可以直接输入 /ape）
    if cmd == "emote" then
        if AP_EmoteUI and AP_EmoteUI.Toggle then
            AP_EmoteUI.Toggle()
        else
            print("|cffffd700[AP]|r 表情模块未加载。")
        end
        return
    end
    -- /AP net on|off：开关“和其他装了本插件的人互相显示 RP 名”的网络功能。
    -- 不带参数就是切换。默认开启，只在小队/团队/公会里广播。
    -- /AP castbar：排查施法条改写是否找到框架，只打印诊断信息
    if cmd == "castbar" then
        if AP_CastBar and AP_CastBar.Debug then
            AP_CastBar.Debug()
        else
            print("|cffffd700[AP]|r 施法条模块未加载。")
        end
        return
    end
    if cmd == "net" then
        if AP_Network and AP_Network.SetEnabled then
            local value
            if arg == "on" then value = true
            elseif arg == "off" then value = false end
            AP_Network.SetEnabled(value)
        else
            print("|cffffd700[AP]|r 网络模块未加载。")
        end
        return
    end
    -- /AP spotlog：开关“高光特写”的调试日志。
    -- 开启后每次成功施法都会在聊天框打印技能 ID 和名字，用来校对高光技能表。
    if cmd == "spotlog" then
        if AP_Spotlight and AP_Spotlight.ToggleDebug then
            AP_Spotlight.ToggleDebug()
        else
            print("|cffffd700[AP]|r 高光模块未加载。")
        end
        return
    end
    -- /AP spotprof N：给当前核心技能加 N 点熟练度（调试用）。
    -- 例：/AP spotprof 200 直接验证 20 级高光解锁。
    if cmd == "spotprof" then
        if AP_Spotlight and AP_Spotlight.AddCoreProf then
            AP_Spotlight.AddCoreProf(tonumber(arg) or 10)
        else
            print("|cffffd700[AP]|r 高光模块未加载。")
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
