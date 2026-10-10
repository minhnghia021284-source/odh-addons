local shared = odh_shared_plugins

local my_own_tab = shared.CreateTab("Anti Aim", "/popora4ka/Disablerendering/refs/heads/main/Antiaim")
local my_own_section = my_own_tab:AddSection("Anti Aim", "STEALTH - KHÔNG BAY, KHÔNG GIẬT")

local run_service = game:GetService("RunService")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer

local anti_aim = {}
local local_parts = {}
local stomping = false
local purchasing = nil

local render_stepped = run_service.RenderStepped
local render_stepped_wait = render_stepped.Wait

local velocity_desync_type = "stealth"
local SAFE_RADIUS = 8

local function round(num, decimals)
    local mult = 10^(decimals or 0)
    return math.floor(num * mult + 0.5 - (num < 0 and 1 or 0)) / mult
end

local fake_position_sender_rate_old
pcall(function()
    fake_position_sender_rate_old = getfflag("S2PhysicsSenderRate")
end)

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

-- =============================================
-- KỸ THUẬT 1: Network Sleep Desync
-- Làm server tưởng mày "ngủ" → không replicate vị trí
-- =============================================
local function apply_network_sleep(hrp)
    pcall(function()
        sethiddenproperty(hrp, "NetworkIsSleeping", true)
    end)
    pcall(function()
        hrp:SetNetworkOwner(nil)
    end)
end

-- =============================================
-- KỸ THUẬT 2: Position Noise Siêu Nhỏ
-- ±2-4 studs — đủ phá prediction, không thấy bay
-- =============================================
local function apply_position_noise(hrp, intensity)
    local old_vel = hrp.AssemblyLinearVelocity
    
    -- Chỉ thay đổi X/Z, giữ Y = 0 (không bay lên trời)
    hrp.AssemblyLinearVelocity = Vector3.new(
        math.random(-intensity, intensity),
        0,  -- QUAN TRỌNG: Y = 0, không bay
        math.random(-intensity, intensity)
    )
    
    render_stepped_wait(render_stepped)
    hrp.AssemblyLinearVelocity = old_vel
end

-- =============================================
-- KỸ THUẬT 3: Rotation Desync (không dịch chuyển)
-- Xoay nhẹ character — phá aim của đối thủ mà không bay
-- =============================================
local function apply_rotation_desync(hrp)
    local old_ang = hrp.AssemblyAngularVelocity
    hrp.AssemblyAngularVelocity = Vector3.new(
        math.random(-15, 15),
        math.random(-15, 15),
        math.random(-15, 15)
    )
    render_stepped_wait(render_stepped)
    hrp.AssemblyAngularVelocity = old_ang
end

-- =============================================
-- CORE: STEALTH DESYNC
-- =============================================
local do_stealth_desync = function(dt, hrp)
    if not hrp or stomping or purchasing then return end
    if (getgenv().FLING_ACTIVE or 0) ~= 0 then return end

    -- Không desync nếu player gần (tránh fling + tránh bị thấy)
    if has_nearby_player(hrp, SAFE_RADIUS) then return end

    -- Set packet rate thấp (fake lag)
    pcall(function() setfflag("S2PhysicsSenderRate", "2") end)

    -- Áp dụng các kỹ thuật tùy mode
    if velocity_desync_type == "stealth" then
        -- Chỉ noise nhỏ + rotation
        apply_position_noise(hrp, 3)
        apply_rotation_desync(hrp)

    elseif velocity_desync_type == "ghost" then
        -- Network sleep — server không thấy mày
        apply_network_sleep(hrp)

    elseif velocity_desync_type == "rotate" then
        -- Chỉ xoay, không dịch chuyển
        apply_rotation_desync(hrp)

    elseif velocity_desync_type == "micro" then
        -- Noise siêu nhỏ (±2)
        apply_position_noise(hrp, 2)

    elseif velocity_desync_type == "balanced" then
        -- Kết hợp: noise + rotation + packet rate
        apply_position_noise(hrp, 5)
        apply_rotation_desync(hrp)
    end
end

local function velocity_desync_enable(value)
    for i = #anti_aim, 1, -1 do
        if anti_aim[i] == do_stealth_desync then
            remove(anti_aim, i)
        end
    end
    if value then
        anti_aim[#anti_aim+1] = do_stealth_desync
    else
        pcall(function() setfflag("S2PhysicsSenderRate", fake_position_sender_rate_old or "15") end)
    end
end

local heartbeat_conn = run_service.Heartbeat:Connect(function(dt)
    local hrp = local_parts["HumanoidRootPart"]
    for i = 1, #anti_aim do
        local func = anti_aim[i]
        if func then
            task.spawn(func, dt, hrp)
        end
    end
end)

local function init_character(character)
    if not character then return end
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if hrp then
        local_parts["HumanoidRootPart"] = hrp
    end
end

init_character(local_player.Character)
local char_added_conn = local_player.CharacterAdded:Connect(init_character)

my_own_section:AddLabel("Credits: @anya_bts (Stealth Fix by CAT)")

my_own_section:AddToggle("enabled", function(state)
    velocity_desync_enable(state)
    if state then
        shared.Notify("Anti Aim enabled", 2)
    else
        shared.Notify("Anti Aim disabled", 2)
    end
end)

my_own_section:AddDropdown("mode", {"stealth", "ghost", "rotate", "micro", "balanced"}, function(selected)
    velocity_desync_type = selected
    shared.Notify("Mode: " .. selected, 2)
end)

my_own_section:AddSlider("Safe Radius", 5, 20, SAFE_RADIUS, function(value)
    SAFE_RADIUS = value
    shared.Notify("Safe Radius: " .. value, 2)
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
    shared.Notify("Anti Aim unloaded", 2)
end)
