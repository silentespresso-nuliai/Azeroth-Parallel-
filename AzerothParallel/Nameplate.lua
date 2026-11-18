-- ==========================================
-- Nameplate.lua: 在姓名版上显示“RP 名·流派”
-- ==========================================
-- 原理：只替换姓名版名字 FontString 的 SetText 输入，不改任何单位数据。
-- 只有客户端提供姓名版接口时才启用；没有就安静退出，不影响其他功能。
-- 显示的是对方插件广播过来的名字，所以双方都要装本插件。

local GetPlateForUnit
if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    -- 8.0+ / 现代 Classic
    GetPlateForUnit = C_NamePlate.GetNamePlateForUnit
elseif type(GetNamePlateForUnit) == "function" then
    -- 少数旧内核保留的全局接口
    GetPlateForUnit = GetNamePlateForUnit
end

-- 新版客户端的 secret/taint 机制：
-- 改写暴雪姓名版自己的 FontString 会把整个姓名版标记为“受污染”，
-- 随后暴雪自己的血量/治疗预估代码会报 “attempt to compare a secret number value”。
-- 为了不破坏游戏界面，这类客户端上直接停用姓名版改写，只保留其他功能。
local secretClient = type(issecretvalue) == "function"

AP_Nameplate = { supported = GetPlateForUnit ~= nil and not secretClient }

-- 客户端没有姓名版接口，或属于 secret 客户端：静默降级，不注册任何事件
if not AP_Nameplate.supported then return end

-- 弱键表：姓名版消失后自动清理，不积累内存
local plateUnits = setmetatable({}, { __mode = "k" })
local hookedText = setmetatable({}, { __mode = "k" })

local function FindNameText(plate)
    local uf = plate.UnitFrame or plate
    if not uf then return nil end
    return uf.name or uf.Name or uf.nameText
end

local hasSecretAPI = type(issecretvalue) == "function"

-- 新版客户端可能把单位名标记成 secret，遇到就不读
local function IsSecret(value)
    if not hasSecretAPI then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret
end

local function GetDisplayName(unit)
    if not unit then return nil end

    -- 整个查询过程套 pcall：任何 secret/接口差异都当作“没有数据”处理
    local ok, display = pcall(function()
        if not UnitIsPlayer(unit) then return nil end
        if UnitIsUnit(unit, "player") then return nil end

        local name = UnitName(unit)
        if not name or IsSecret(name) then return nil end

        -- 姓名版 token 的 UnitName 可能带服务器后缀，两边都试一次
        local key = name:match("^([^%-]+)") or name
        local peer = AP_DB.peers and (AP_DB.peers[key] or AP_DB.peers[name])
        if not peer or not peer.name or peer.name == "" then return nil end

        -- 输入时用空格分隔的“名 姓”，显示时统一成间隔号
        local rpName = peer.name:gsub("%s+", "·")
        if peer.faction and peer.faction ~= "" then
            return rpName .. "·" .. peer.faction
        end
        return rpName
    end)

    if ok then return display end
    return nil
end

local function HookPlate(plate, unit)
    if not plate then return end
    plateUnits[plate] = unit

    local fs = FindNameText(plate)
    if not fs or hookedText[fs] or type(fs.SetText) ~= "function" then return end
    hookedText[fs] = true

    local origSetText = fs.SetText
    fs.SetText = function(self, text)
        local display = GetDisplayName(plateUnits[plate])
        if display then text = display end
        return origSetText(self, text)
    end
end

local frame = CreateFrame("Frame")
local function SafeRegister(event)
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("NAME_PLATE_UNIT_REMOVED")
SafeRegister("UNIT_NAME_UPDATE")
SafeRegister("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" then
        if not unit then return end
        local plate = GetPlateForUnit(unit)
        if plate then HookPlate(plate, unit) end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- 登录时已经存在的姓名版补一次 hook
        for i = 1, 40 do
            local nameplateUnit = "nameplate" .. i
            local plate = GetPlateForUnit(nameplateUnit)
            if plate then HookPlate(plate, nameplateUnit) end
        end
    end
end)

-- 收到新的 RP 数据时，把已经显示的姓名版刷新一遍
function AP_Nameplate.RefreshAll()
    for plate in pairs(plateUnits) do
        local fs = FindNameText(plate)
        if fs then
            -- 读到的名字也可能是 secret string，读不了就跳过这一块
            pcall(function()
                local current = fs:GetText()
                if current and not IsSecret(current) then
                    fs:SetText(current)
                end
            end)
        end
    end
end
