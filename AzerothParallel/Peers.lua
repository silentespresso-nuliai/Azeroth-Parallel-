-- ==========================================
-- Peers.lua: 同好名录（设定页 →「奇遇社交」分页）
-- ==========================================
-- 只读取 Network.lua 收到的 RP 名字缓存（AP_DB.peers），
-- 全部控件都是本插件自己创建的，不碰暴雪姓名版/单位框架，
-- 所以不会产生 secret/taint 问题。

local settingPanel = AP_Panels and AP_Panels[1]
local page = AP_PeersSettingsPage
if not (settingPanel and page) then return end

-- ---------- 设定页左页入口 ----------
local entryBtn = CreateFrame("Button", nil, settingPanel.LeftPage, "UIPanelButtonTemplate")
entryBtn:SetSize(200, 36)
-- 聊天弹幕 40、表情动作 -10、正面形象 -60，这里排在第四个
entryBtn:SetPoint("CENTER", settingPanel.LeftPage, "CENTER", 0, -110)
entryBtn:SetText("奇遇社交")
entryBtn:SetScript("OnClick", function()
    if AP_SelectSettingsTab then AP_SelectSettingsTab("peers") end
end)
if AP_RegisterSettingsEntry then AP_RegisterSettingsEntry(entryBtn) end

-- ---------- 右页「奇遇社交」分页 ----------
local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -2)
title:SetText("同好名录")
title:SetFont(title:GetFont(), 20, "")
title:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local desc = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
desc:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -34)
desc:SetWidth(340)
desc:SetJustifyH("LEFT")
desc:SetSpacing(5)
desc:SetFont(desc:GetFont(), 13, "")
desc:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
desc:SetText("装了本插件、并且和你在同一个小队 / 团队 / 公会里出现过的玩家会列在这里。\n" ..
    "|cff6b5a45名字和流派来自对方插件的广播；仅保存在本机，不会上传。|r")

-- 开关：和 /AP net 共用同一个状态
local toggle = CreateFrame("CheckButton", "AP_PeersToggle", page, "ChatConfigCheckButtonTemplate")
toggle:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -96)
local toggleText = _G[toggle:GetName() .. "Text"]
toggleText:SetText("接收同好名录")
toggleText:SetFont(toggleText:GetFont(), 15, "")
toggleText:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])
toggle:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if AP_Network and AP_Network.SetEnabled then
        AP_Network.SetEnabled(on)
    end
end)

local status = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -132)
status:SetWidth(340)
status:SetJustifyH("LEFT")
status:SetFont(status:GetFont(), 12, "")
status:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])

local scrollFrame = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(340, 300)
scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 30, -158)
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(300)
scrollChild:SetHeight(1)

local listText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listText:SetPoint("TOPLEFT", 0, 0)
listText:SetWidth(300)
listText:SetJustifyH("LEFT")
listText:SetSpacing(8)
listText:SetFont(listText:GetFont(), 15, "")
listText:SetTextColor(AP_Theme.ink[1], AP_Theme.ink[2], AP_Theme.ink[3])

local hint = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 30, 10)
hint:SetWidth(340)
hint:SetJustifyH("LEFT")
hint:SetFont(hint:GetFont(), 11, "")
hint:SetTextColor(AP_Theme.inkSoft[1], AP_Theme.inkSoft[2], AP_Theme.inkSoft[3])
hint:SetText("|cff6b5a45可在上面的开关里快速切换同好广播。|r")

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
        listText:SetText("|cff6b5a45还没有同好数据。\n\n" ..
            "和装了本插件的朋友组队、进同一个公会，登录或队伍变化后就会自动交换名字。|r")
    else
        local lines = {}
        for _, item in ipairs(list) do
            local peer = item.peer
            local whenText = ""
            if peer.updated and peer.updated > 0 and date then
                local ok, t = pcall(date, "%m-%d %H:%M", peer.updated)
                if ok and t then whenText = "  |cff7a6a55" .. t .. "|r" end
            end
            table.insert(lines,
                "|cff8c261a" .. GetDisplay(peer) .. "|r" ..
                "  |cff6b5a45(" .. tostring(item.key) .. ")|r" .. whenText)
        end
        listText:SetText(table.concat(lines, "\n"))
    end

    scrollChild:SetHeight(math.max(1, listText:GetStringHeight() + 20))
    status:SetText(string.format("已记录 %d 位同好。", #list))
end

-- 每次切到「奇遇社交」分页时自动刷新
page:SetScript("OnShow", Refresh)

AP_PeersUI = { Refresh = Refresh }

-- 首次加载先渲染一次
Refresh()
