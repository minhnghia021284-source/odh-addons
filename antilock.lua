local shared = odh_shared_plugins

local my_own_tab = shared.CreateTab("Anti Aim", "/popora4ka/Disablerendering/refs/heads/main/Antiaim")
local my_own_section = my_own_tab:AddSection("Anti Aim", "PROTECTS YOU FROM AIMBOTS (STEALTH - NO VISUAL)")

local run_service = game:GetService("RunService")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer

local anti_aim = {}
local local_parts = {}
local local_fps = 200
local stomping = false
local purchasing = nil

local render_stepped = run_service.RenderStepped
local render_stepped_wait = render_stepped.Wait

local velocity_desync_type = "stealth"
local velocity_desync_rotate = false

local SAFE_RADIUS = 15
local STEALTH_INTENSITY = 8   -- Càng nhỏ càng kín (5-15 là an toàn)

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
-- STEALTH DESYNC - Không di chuyển thấy rõ
-- =============================================
local do_velocity_desync = function(dt, hrp)
    if hrp and not stomping and not purchasing and (getgenv().FLING_ACTIVE or 0) == 0 then

        -- Không desync nếu có player gần
        if has_nearby_player(hrp, SAFE_RADIUS) then
            return
        end

        pcall(function() setfflag("S2PhysicsSenderRate", tostring(round(local_fps, 1))) end)
        pcall(function() sethiddenproperty(hrp, "NetworkIsSleeping", false) end)

        local old_lin = hrp.AssemblyLinearVelocity
        local old_ang = hrp.AssemblyAngularVelocity
        local old_collide = hrp.CanCollide

        -- =============================================
        -- STEALTH: Chỉ di chuyển siêu nhỏ (±5-15)
        -- Đủ phá aimbot nhưng mắt thường không thấy
        -- =============================================
        local intensity = STEALTH_INTENSITY
        local vel

        if velocity_desync_type == "stealth" then
            -- Di chuyển siêu nhỏ theo pattern ngẫu nhiên
            vel = Vector3.new(
                math.random(-intensity, intensity),
                math.random(-2, 2),
                math.random(-intensity, intensity)
            )
        elseif velocity_desync_type == "micro" then
            -- Còn nhỏ hơn nữa, cực kỳ kín
            vel = Vector3.new(
                math.random(-4, 4),
                0,
                math.random(-4, 4)
            )
        elseif velocity_desync_type == "slide" then
            -- Trượt nhẹ theo 1 hướng ngẫu nhiên
            local angle = math.random() * math.pi * 2
            vel = Vector3.new(math.cos(angle) * intensity, 0, math.sin(angle) * intensity)
        elseif velocity_desync_type == "spin" then
            -- Xoay nhẹ, không dịch chuyển vị trí
            vel = old_lin
            hrp.AssemblyAngularVelocity = Vector3.new(
                math.random(-3, 3),
                math.random(-3, 3),
                math.random(-3, 3)
            )
        elseif velocity_desync_type == "jitter" then
            vel = Vector3.new(
                math.random(1,2) == 1 and -intensity or intensity,
                0,
                math.random(1,2) == 1 and -intensity or intensity
            )
        else
            vel = Vector3.new(
                math.random(-intensity, intensity),
                0,
                math.random(-intensity, intensity)
            )
        end

        -- Tắt collision để không đụng ai
        hrp.CanCollide = false

        getgenv().VELOCITY_DESYNC_UNTIL = os.clock() + 0.03
        hrp.AssemblyLinearVelocity = vel

        render_stepped_wait(render_stepped)

        -- Khôi phục ngay (chỉ 1 frame)
        hrp.AssemblyLinearVelocity = old_lin
        hrp.AssemblyAngularVelocity = old_ang
        hrp.CanCollide = old_collide

        getgenv().VELOCITY_DESYNC_UNTIL = os.clock() + 0.01
    end
end

-- =============================================
-- SAFE MODE - Không đổi velocity, chỉ desync network packet
-- 100% không thấy gì trên màn hình người khác
-- =============================================
local safe_mode = true

local function do_safe_desync(dt, hrp)
    if hrp and safe_mode then
        -- Chỉ thay đổi tốc độ gửi packet, không đổi vị trí
        pcall(function() setfflag("S2PhysicsSenderRate", tostring(math.random(8, 20))) end)
        pcall(function() sethiddenproperty(hrp, "NetworkIsSleeping", false) end)
    end
end

local function velocity_desync_enable(value)
    for i = #anti_aim, 1, -1 do
        if anti_aim[i] == do_velocity_desync or anti_aim[i] == do_safe_desync then
            remove(anti_aim, i)
        end
    end
    if value then
        if safe_mode then
            anti_aim[#anti_aim+1] = do_safe_desync
        else
            anti_aim[#anti_aim+1] = do_velocity_desync
        end
    else
        pcall(function() setfflag("S2PhysicsSenderRate", fake_position_sender_rate_old or "15") end)
    end
end

local heartbeat_conn = run_service.Heartbeat:Connect(function(dt)
    local_fps = 1 / (os.clock() - (os.clock() - dt))
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

my_own_section:AddLabel("Credits: @anya_bts (Fixed by CAT - Stealth Mode)")

-- =============================================
-- TOGGLE SAFE MODE
-- =============================================
my_own_section:AddToggle("🛡️ Safe Mode (Không thấy gì)", function(state)
    safe_mode = state
    if state then
        shared.Notify("🛡️ Safe Mode - Không ai thấy mày hack", 3)
    else
        shared.Notify("⚡ Stealth Mode - Vẫn kín nhưng mạnh hơn", 3)
    end
end)

my_own_section:AddToggle("enabled", function(state)
    velocity_desync_enable(state)
    if state then
        shared.Notify("Anti Aim enabled", 2)
    else
        shared.Notify("Anti Aim disabled", 2)
    end
end)

-- =============================================
-- DROPDOWN MODE - Đổi sang các mode kín
-- =============================================
my_own_section:AddDropdown("mode", {"stealth", "micro", "slide", "spin", "jitter"}, function(selected)
    velocity_desync_type = selected
    shared.Notify("Anti Aim mode: " .. selected, 2)
end)

-- =============================================
-- SLIDER - Điều chỉnh độ mạnh (càng nhỏ càng kín)
-- =============================================
my_own_section:AddSlider("Stealth Intensity", 3, 20, STEALTH_INTENSITY, function(value)
    STEALTH_INTENSITY = value
    shared.Notify("Intensity: " .. value .. " (nhỏ = kín)", 2)
end)

my_own_section:AddToggle("rotate", function(state)
    velocity_desync_rotate = state
    if state then
        shared.Notify("Rotation enabled", 2)
    else
        shared.Notify("Rotation disabled", 2)
    end
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
