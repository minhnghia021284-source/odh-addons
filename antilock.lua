--[[
    ANTI-AIM V4 - MM2/MMV EDITION (NO FLING, SMART TRIGGER)
    - Không gây fling người khác
    - Tự động tắt khi có người ở gần
    - Chỉ kích hoạt khi bị nhắm
    - Sử dụng kết hợp Velocity + Network Desync
--]]

local shared = odh_shared_plugins

-- Tạo tab và section trong menu của Overdrive H
local my_own_tab = shared.CreateTab("Anti Aim", "/popora4ka/Disablerendering/refs/heads/main/Antiaim")
local my_own_section = my_own_tab:AddSection("Anti Aim V4", "MM2/MMV - NO FLING - SMART")

-- Services
local run_service = game:GetService("RunService")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer
local camera = workspace.CurrentCamera

-- Các biến toàn cục
local anti_aim = {}
local local_parts = {}
local stomping = false
local purchasing = nil
local render_stepped = run_service.RenderStepped
local render_stepped_wait = render_stepped.Wait

-- Cấu hình có thể thay đổi
local velocity_desync_type = "stealth"
local SAFE_RADIUS = 10
local TRIGGER_ANGLE = 30
local DESYNC_POWER = 150
local PACKET_RATE = "2"

-- Lưu trữ FFlag gốc
local fake_position_sender_rate_old
pcall(function()
    fake_position_sender_rate_old = getfflag("S2PhysicsSenderRate")
end)

-- Hàm tiện ích
local function remove(tbl, index)
    local length = #tbl
    for i = index, length - 1 do
        tbl[i] = tbl[i + 1]
    end
    tbl[length] = nil
end

local function has_nearby_player(hrp, radius)
    radius = radius or SAFE_RADIUS
    for _, plr in ipairs(players_service:GetPlayers()) do
        if plr ~= local_player and plr.Character then
            local other_hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if other_hrp then
                local dist = (other_hrp.Position - hrp.Position).Magnitude
                if dist <= radius then
                    return true
                end
            end
        end
    end
    return false
end

-- Kiểm tra xem có ai đang nhắm vào mình không
local function is_being_aimed_at(hrp)
    for _, plr in ipairs(players_service:GetPlayers()) do
        if plr ~= local_player and plr.Character then
            local other_head = plr.Character:FindFirstChild("Head")
            local other_hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if other_head and other_hrp then
                local to_me = (hrp.Position - other_head.Position).Unit
                local look = other_hrp.CFrame.LookVector
                local dot = look:Dot(to_me)
                local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
                if angle <= TRIGGER_ANGLE then
                    return true
                end
            end
        end
    end
    return false
end

-- =============================================
-- CORE: SMART DESYNC (Không fling)
-- =============================================
local function do_smart_desync(dt, hrp)
    if not hrp or stomping or purchasing then return end
    if (getgenv().FLING_ACTIVE or 0) ~= 0 then return end

    -- 1. Không desync nếu có người ở gần (tránh fling)
    if has_nearby_player(hrp, SAFE_RADIUS) then return end

    -- 2. Chỉ kích hoạt khi bị nhắm
    if not is_being_aimed_at(hrp) then return end

    -- 3. Bắt đầu desync
    pcall(function() setfflag("S2PhysicsSenderRate", PACKET_RATE) end)
    pcall(function() sethiddenproperty(hrp, "NetworkIsSleeping", false) end)

    local old_lin = hrp.AssemblyLinearVelocity
    local old_ang = hrp.AssemblyAngularVelocity
    local old_collide = hrp.CanCollide

    -- 4. Tạo vận tốc desync (Y = 0 để không bay)
    local vel
    if velocity_desync_type == "stealth" then
        vel = Vector3.new(
            math.random(-DESYNC_POWER, DESYNC_POWER),
            0,
            math.random(-DESYNC_POWER, DESYNC_POWER)
        )
    elseif velocity_desync_type == "jitter" then
        vel = Vector3.new(
            math.random(1,2) == 1 and -DESYNC_POWER or DESYNC_POWER,
            0,
            math.random(1,2) == 1 and -DESYNC_POWER or DESYNC_POWER
        )
    else
        vel = Vector3.new(
            math.random(-DESYNC_POWER, DESYNC_POWER),
            0,
            math.random(-DESYNC_POWER, DESYNC_POWER)
        )
    end

    -- 5. QUAN TRỌNG: Tắt va chạm để không fling
    hrp.CanCollide = false

    getgenv().VELOCITY_DESYNC_UNTIL = os.clock() + 0.05
    hrp.AssemblyLinearVelocity = vel

    render_stepped_wait(render_stepped)

    -- 6. Khôi phục trạng thái ngay lập tức
    hrp.AssemblyLinearVelocity = old_lin
    hrp.AssemblyAngularVelocity = old_ang
    hrp.CanCollide = old_collide

    getgenv().VELOCITY_DESYNC_UNTIL = os.clock() + 0.02
end

-- Bật/tắt anti-aim
local function velocity_desync_enable(value)
    for i = #anti_aim, 1, -1 do
        if anti_aim[i] == do_smart_desync then
            remove(anti_aim, i)
        end
    end
    if value then
        anti_aim[#anti_aim+1] = do_smart_desync
    else
        pcall(function() setfflag("S2PhysicsSenderRate", fake_position_sender_rate_old or "15") end)
    end
end

-- Vòng lặp chính
local heartbeat_conn = run_service.Heartbeat:Connect(function(dt)
    local hrp = local_parts["HumanoidRootPart"]
    for i = 1, #anti_aim do
        local func = anti_aim[i]
        if func then
            task.spawn(func, dt, hrp)
        end
    end
end)

-- Quản lý nhân vật
local function init_character(character)
    if not character then return end
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if hrp then
        local_parts["HumanoidRootPart"] = hrp
    end
end

init_character(local_player.Character)
local char_added_conn = local_player.CharacterAdded:Connect(init_character)

-- =============================================
-- UI CHO MENU
-- =============================================
my_own_section:AddLabel("Credits: @anya_bts (V4 Fix by CAT)")

my_own_section:AddToggle("enabled", function(state)
    velocity_desync_enable(state)
    if state then
        shared.Notify("Anti Aim V4 enabled", 2)
    else
        shared.Notify("Anti Aim V4 disabled", 2)
    end
end)

my_own_section:AddDropdown("mode", {"stealth", "jitter"}, function(selected)
    velocity_desync_type = selected
    shared.Notify("Mode: " .. selected, 2)
end)

my_own_section:AddSlider("Trigger Angle", 10, 45, TRIGGER_ANGLE, function(value)
    TRIGGER_ANGLE = value
    shared.Notify("Trigger Angle: " .. value, 2)
end)

my_own_section:AddSlider("Power", 50, 250, DESYNC_POWER, function(value)
    DESYNC_POWER = value
    shared.Notify("Power: " .. value, 2)
end)

my_own_section:AddSlider("Packet Rate", 1, 10, 2, function(value)
    PACKET_RATE = tostring(value)
    shared.Notify("Packet Rate: " .. value, 2)
end)

my_own_section:AddButton("unload", function()
    velocity_desync_enable(false)
    if heartbeat_conn then
        pcall(function() heartbeat_conn:Disconnect() end)
        heartbeat_conn = nil
    end
    if char_added_conn then
        pcall(function() char_added_conn:Disconnect() end)
        char_added_conn = nil
    end
    shared.Notify("Anti Aim V4 unloaded", 2)
end)
