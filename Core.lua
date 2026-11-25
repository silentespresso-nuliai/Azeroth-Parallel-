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

-- 书本主题花纹：四个 Deco 都是 1024 画布、图案在左上 900×650 区域，
-- 所以使用和 Book.tga 完全相同的 TexCoord 裁切，跟随当前页签切换。
local decoArt = AP_MainFrame:CreateTexture(nil, "BORDER")
decoArt:SetAllPoints()
decoArt:SetTexCoord(0, BOOK_W / TEX_SIZE, 0, BOOK_H / TEX_SIZE)
decoArt:SetTexture(MEDIA .. "Deco_1.tga")
AP_MainFrame.decoArt = decoArt

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
local tabNames = { "设定", "职业流派", "预留", "核心奥义" }
local tabLabels = { "设定", "职业\n流派", "奇遇\n社交", "高光\n特写" }
-- 顺序对应：设定 / 职业流派 / 奇遇社交 / 高光特写
local tabColors = {
    { 0.70, 0.17, 0.15 },   -- 红：设定（龙纹）
    { 0.27, 0.58, 0.34 },   -- 绿：职业流派（藤蔓）
    { 0.48, 0.28, 0.66 },   -- 紫：奇遇社交（巴洛克卷叶）
    { 0.56, 0.56, 0.60 },   -- 蓝灰：高光特写（星芒）
}

-- 页签花纹：按用户指定的 Deco_1..4 对应关系
local tabDeco = {
    "Deco_2.tga", -- 设定：龙纹
    "Deco_1.tga", -- 职业流派：藤蔓
    "Deco_3.tga", -- 奇遇社交：巴洛克卷叶
    "Deco_4.tga", -- 高光特写：星芒
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
    -- 记住最后停留的页签，下次 /AP 打开时回到这一页
    AP_DB.ui = AP_DB.ui or {}
    AP_DB.ui.lastTab = index

    -- 换页签时，整本书的花纹一起换
    if AP_MainFrame.decoArt and tabDeco[index] then
        AP_MainFrame.decoArt:SetTexture(MEDIA .. tabDeco[index])
    end

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

-- ==========================================
-- 设定页左页：插件简介 / 版本 / 作者 / 链接
-- 原来的四个入口按钮已由 Danmaku.lua 统一隐藏（右页顶部的分页按钮已经承担导航）
-- ==========================================
local aboutPage = AP_Panels[1].LeftPage

-- 作者/联系方式区块的签名：用于检测有人改写作者、声明或链接。
-- 如果以后自己改了下面 BRAND 里的内容，用 /AP brand 取新签名，替换 BRAND_SIGNATURE。
local BRAND = {
    author = "怒里哀",
    statement = "原创声明：本插件为「怒里哀」原创作品，仅供角色扮演娱乐使用。未经作者许可，请勿用于商业售卖或付费整合包。",
    nga = "https://bbs.nga.cn/read.php?tid=47965408",
    afd = "https://ifdian.net/a/nuliai",
    xhs = "https://xhslink.cn/o/6OToP5OQrkn",
}
local BRAND_SALT = "AP-nuliai-2026"
local BRAND_SIGNATURE = "48a03e81"

local function BrandHash(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 2147483647
    end
    return string.format("%08x", h)
end

local function GetBrandSignature()
    local text = table.concat({
        BRAND.author, BRAND.statement, BRAND.nga, BRAND.afd, BRAND.xhs, BRAND_SALT,
    }, "|")
    return BrandHash(text)
end

-- 被篡改时显示在左页顶部的红字（软警告，不破坏插件功能）
local brandWarning = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
brandWarning:SetPoint("TOP", aboutPage, "TOP", 0, -2)
brandWarning:SetWidth(360)
brandWarning:SetJustifyH("CENTER")
brandWarning:SetFont(brandWarning:GetFont(), 11, "")
brandWarning:SetTextColor(0.78, 0.08, 0.08)
brandWarning:SetText("")
brandWarning:Hide()

local aboutTitle = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
aboutTitle:SetPoint("TOP", aboutPage, "TOP", 0, -24)
aboutTitle:SetText("艾泽拉斯平行宇宙")
aboutTitle:SetFont(aboutTitle:GetFont(), 26, "OUTLINE")
AP_Theme.Paint(aboutTitle, "accent")

local aboutSub = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aboutSub:SetPoint("TOP", aboutTitle, "BOTTOM", 0, -4)
aboutSub:SetText("Azeroth Parallel")
aboutSub:SetFont(aboutSub:GetFont(), 13, "")
AP_Theme.Paint(aboutSub, "inkSoft")

local aboutIntro = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
aboutIntro:SetPoint("TOP", aboutSub, "BOTTOM", 0, -18)
aboutIntro:SetWidth(330)
aboutIntro:SetJustifyH("LEFT")
aboutIntro:SetSpacing(5)
aboutIntro:SetFont(aboutIntro:GetFont(), 14, "")
aboutIntro:SetText("一套面向角色扮演的界面扩展：把职业、天赋与技能的官方称呼，换成符合角色种族与流派背景的说法；并提供聊天弹幕、称谓典籍、表情动作、同好名录与高光特写。\n\n所有改动只发生在本地界面，不修改服务器数据。RP 名称与流派简称只通过插件消息，在同队/同团/同会且双方都安装插件的人之间共享；可用 /AP net 关闭。")
AP_Theme.Paint(aboutIntro, "ink")

-- 分割线
local aboutLine = aboutPage:CreateTexture(nil, "ARTWORK")
aboutLine:SetSize(330, 1)
aboutLine:SetPoint("TOP", aboutIntro, "BOTTOM", 0, -16)
aboutLine:SetTexture("Interface\\Buttons\\WHITE8x8")
aboutLine:SetVertexColor(AP_Theme.line[1], AP_Theme.line[2], AP_Theme.line[3], 0.6)

-- 版本号优先从 toc 读取，读不到就用当前版本兜底
local addonVersion = "1.0.0-beta.8"
if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, "AzerothParallel", "Version")
    if ok and v then addonVersion = v end
elseif GetAddOnMetadata then
    local ok, v = pcall(GetAddOnMetadata, "AzerothParallel", "Version")
    if ok and v then addonVersion = v end
end

local aboutVersion = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aboutVersion:SetPoint("TOP", aboutLine, "BOTTOM", 0, -12)
aboutVersion:SetText("版本：" .. addonVersion)
aboutVersion:SetFont(aboutVersion:GetFont(), 13, "")
AP_Theme.Paint(aboutVersion, "inkSoft")

local aboutAuthor = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aboutAuthor:SetPoint("TOP", aboutVersion, "BOTTOM", 0, -6)
aboutAuthor:SetText("作者：" .. BRAND.author)
aboutAuthor:SetFont(aboutAuthor:GetFont(), 13, "")
AP_Theme.Paint(aboutAuthor, "inkSoft")

local aboutStatement = aboutPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aboutStatement:SetPoint("TOP", aboutAuthor, "BOTTOM", 0, -14)
aboutStatement:SetWidth(330)
aboutStatement:SetJustifyH("LEFT")
aboutStatement:SetSpacing(4)
aboutStatement:SetFont(aboutStatement:GetFont(), 12, "")
aboutStatement:SetText(BRAND.statement)
AP_Theme.Paint(aboutStatement, "inkSoft")

-- 点击链接：弹出自己的小窗，里面的网址可选中复制
-- （魔兽不允许插件直接打开浏览器；StaticPopup 的 EditBox 在部分客户端会显示空文本，所以自建）
local copyPopup = CreateFrame("Frame", "AP_CopyPopup", UIParent, "BackdropTemplate")
copyPopup:SetSize(440, 158)
copyPopup:SetPoint("CENTER")
copyPopup:SetFrameStrata("DIALOG")
copyPopup:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
copyPopup:SetBackdropColor(0.88, 0.82, 0.70, 0.98)
copyPopup:SetBackdropBorderColor(0.35, 0.22, 0.10, 1)
copyPopup:EnableMouse(true)
copyPopup:Hide()
tinsert(UISpecialFrames, "AP_CopyPopup")

local copyTitle = copyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
copyTitle:SetPoint("TOP", 0, -14)
copyTitle:SetText("复制链接")
copyTitle:SetFont(copyTitle:GetFont(), 18, "")
AP_Theme.Paint(copyTitle, "accent")

local copyBox = CreateFrame("EditBox", nil, copyPopup, "BackdropTemplate")
copyBox:SetSize(390, 28)
copyBox:SetPoint("TOP", copyTitle, "BOTTOM", 0, -12)
copyBox:SetAutoFocus(false)
copyBox:SetFontObject("GameFontNormal")
copyBox:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
copyBox:SetTextInsets(6, 6, 0, 0)
copyBox:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
copyBox:SetBackdropColor(0.97, 0.94, 0.86, 1)
copyBox:SetBackdropBorderColor(0.45, 0.30, 0.14, 1)
copyBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    copyPopup:Hide()
end)
copyBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    copyPopup:Hide()
end)

local copyHint = copyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
copyHint:SetPoint("TOP", copyBox, "BOTTOM", 0, -8)
copyHint:SetText("按 Ctrl+C 复制，Esc 关闭")
copyHint:SetFont(copyHint:GetFont(), 12, "")
AP_Theme.Paint(copyHint, "inkSoft")

local copyClose = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
copyClose:SetSize(90, 24)
copyClose:SetPoint("BOTTOM", 0, 14)
copyClose:SetText("关闭")
copyClose:SetScript("OnClick", function() copyPopup:Hide() end)

copyPopup:SetScript("OnHide", function() copyBox:ClearFocus() end)

local function ShowCopyPopup(url)
    copyPopup:Show()
    copyBox:SetText(url or "")
    copyBox:SetFocus()
    copyBox:HighlightText()
end

local LINK_COLOR = { 0.12, 0.32, 0.58 }
local LINK_HOVER = { 0.20, 0.46, 0.78 }

local function CreateCopyLink(label, url, anchor, yOffset)
    local btn = CreateFrame("Button", nil, aboutPage)
    btn:SetSize(330, 22)
    btn:SetPoint("TOP", anchor, "BOTTOM", 0, yOffset)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", btn, "LEFT", 0, 0)
    fs:SetWidth(330)
    fs:SetJustifyH("LEFT")
    fs:SetFont(fs:GetFont(), 12, "")
    fs:SetText(label .. "：" .. url)
    fs:SetTextColor(LINK_COLOR[1], LINK_COLOR[2], LINK_COLOR[3])

    btn:SetScript("OnEnter", function(self)
        fs:SetTextColor(LINK_HOVER[1], LINK_HOVER[2], LINK_HOVER[3])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("点击复制链接", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        fs:SetTextColor(LINK_COLOR[1], LINK_COLOR[2], LINK_COLOR[3])
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        ShowCopyPopup(url)
    end)
    return btn
end

local ngaLink = CreateCopyLink("NGA", BRAND.nga, aboutStatement, -18)
local afdLink = CreateCopyLink("AFD", BRAND.afd, ngaLink, -4)
local xhsLink = CreateCopyLink("XHS", BRAND.xhs, afdLink, -4)

-- 软防伪：签名不匹配时只警告，不影响插件功能
local function CheckBrand()
    if GetBrandSignature() ~= BRAND_SIGNATURE then
        brandWarning:SetText("此副本的作者/联系方式已被修改，非原作者发布版本。原作者：怒里哀")
        brandWarning:Show()
        print("|cffff2020[AP]|r 检测到作者/联系方式被修改。原作者：怒里哀。")
    end
end
CheckBrand()

-- 首次进入默认打开第 2 页（职业流派）；之后在登录时恢复上次停留页
SelectTab(2)

SLASH_AZEROTHPARALLEL1 = "/AP"
SlashCmdList["AZEROTHPARALLEL"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")

    -- /AP brand：查看作者/联系方式区块的当前签名，方便自己改链接后更新 BRAND_SIGNATURE
    if cmd == "brand" then
        print("|cffffd700[AP]|r 当前作者区块签名：" .. GetBrandSignature())
        print("|cffffd700[AP]|r 期望签名：" .. BRAND_SIGNATURE)
        return
    end

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
    -- /AP spotlog：开关“核心奥义”的调试日志。
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
    -- 存档变量这时已经注入，恢复上次停留的页签
    if AP_DB.ui and tonumber(AP_DB.ui.lastTab) then
        local idx = tonumber(AP_DB.ui.lastTab)
        if AP_Tabs[idx] then SelectTab(idx) end
    end

    print("|cff00ff00++++++++++++++++++++++++|r")
    print("|cff00ff00+|r |cffd4af37AP: Azeroth Parallel|r |cff00ff00+|r")
    print("|cff00ff00+|r |cffffcc00Type /AP to open UI|r  |cff00ff00+|r")
    print("|cff00ff00++++++++++++++++++++++++|r")
end)
