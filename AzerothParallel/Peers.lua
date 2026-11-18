-- ==========================================
-- Peers.lua: 同好名录（奇遇社交页）
-- ==========================================
-- 只读取 Network.lua 收到的 RP 名字缓存（AP_DB.peers），
-- 全部控件都是本插件自己创建的，不碰暴雪姓名版/单位框架，
-- 所以不会产生 secret/taint 问题。

local panel = AP_Panels[3]
local LeftPage = panel.LeftPage
local RightPage = panel.RightPage

-- 左页：标题与说明
local title = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", LeftPage, "TOPLEFT", 20, -20)
title:SetText("同好名录")
title:SetFont(title:GetFont(), 26, "OUTLINE")

local desc = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
desc:SetPoint("TOPLEFT", LeftPage, "TOPLEFT", 20, -65)
desc:SetWidth(360)
desc:SetJustifyH("LEFT")
desc:SetSpacing(8)
desc:SetFont(desc:GetFont(), 15, "")
desc:SetText("这里会列出：装了本插件、并且和你在同一个小队/团队/公会里出现过的玩家。\n\n" ..
    "名字和流派来自对方插件广播的数据；对方没装插件、或不在同一聊天范围时不会出现。\n\n" ..
    "|cff888888仅保存在本机，不会上传到任何服务器。|r")

-- 开关：和 /AP net 共用同一个状态
local toggle = CreateFrame("CheckButton", "AP_PeersToggle", LeftPage, "ChatConfigCheckButtonTemplate")
toggle:SetPoint("TOPLEFT", LeftPage, "TOPLEFT", 20, -275)
local toggleText = _G[toggle:GetName() .. "Text"]
toggleText:SetText("接收同好名录")
toggleText:SetFont(toggleText:GetFont(), 16, "OUTLINE")
toggle:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if AP_Network and AP_Network.SetEnabled then
        AP_Network.SetEnabled(on)
    end
end)

-- 统计与提示
local status = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", LeftPage, "TOPLEFT", 20, -320)
status:SetWidth(360)
status:SetJustifyH("LEFT")
status:SetFont(status:GetFont(), 14, "")

local hint = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("TOPLEFT", LeftPage, "TOPLEFT", 20, -360)
hint:SetWidth(360)
hint:SetJustifyH("LEFT")
hint:SetFont(hint:GetFont(), 13, "")
hint:SetText("|cff888888可输入 /AP net on 或 /AP net off 快速切换。\n" ..
    "姓名版改写在新客户端会被系统禁止，所以改用这份名录展示。|r")

-- 右页：可滚动列表
local scrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(340, 480)
scrollFrame:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 30, -30)
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(300)
scrollChild:SetHeight(1)

local listText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listText:SetPoint("TOPLEFT", 0, 0)
listText:SetWidth(300)
listText:SetJustifyH("LEFT")
listText:SetSpacing(10)
listText:SetFont(listText:GetFont(), 16, "")

local function GetDisplay(peer)
    local name = peer.name or "?"
    name = name:gsub("%s+", "·")
    if peer.faction and peer.faction ~= "" then
        return name .. "·" .. peer.faction
    end
    return name
end

local function Refresh()
    -- 复选框跟着真实状态走（/AP net 改过也能同步）
    local netEnabled = true
    if AP_DB.network and AP_DB.network.enabled == false then netEnabled = false end
    toggle:SetChecked(netEnabled)

    local list = {}
    local peers = (AP_DB and AP_DB.peers) or {}
    for key, peer in pairs(peers) do
        if type(peer) == "table" and peer.name and peer.name ~= "" then
            table.insert(list, { key = key, peer = peer })
        end
    end

    -- 最近见到的排前面
    table.sort(list, function(a, b)
        local ta = a.peer.updated or 0
        local tb = b.peer.updated or 0
        if ta == tb then return tostring(a.key) < tostring(b.key) end
        return ta > tb
    end)

    if #list == 0 then
        listText:SetText("|cff888888还没有同好数据。\n\n" ..
            "和装了本插件的朋友组队、进同一个公会，登录或队伍变化后就会自动交换名字。|r")
    else
        local lines = {}
        for _, item in ipairs(list) do
            local peer = item.peer
            local whenText = ""
            if peer.updated and peer.updated > 0 and date then
                local ok, t = pcall(date, "%m-%d %H:%M", peer.updated)
                if ok and t then whenText = "  |cff777777" .. t .. "|r" end
            end
            table.insert(lines,
                "|cffd4af37" .. GetDisplay(peer) .. "|r" ..
                "  |cff888888(" .. tostring(item.key) .. ")|r" .. whenText)
        end
        listText:SetText(table.concat(lines, "\n"))
    end

    scrollChild:SetHeight(math.max(1, listText:GetStringHeight() + 20))
    status:SetText(string.format("已记录 %d 位同好。", #list))
end

-- 每次切到“奇遇社交”页时自动刷新
panel:SetScript("OnShow", function()
    Refresh()
end)

AP_PeersUI = { Refresh = Refresh }

-- 首次加载先渲染一次
Refresh()
