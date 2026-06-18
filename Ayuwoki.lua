-- Fluent Ayuwoki Field Assistance Mode
-- Run in an executor (supports loadstring and exploit helpers like fireproximityprompt)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Load Fluent UI
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Ayuwoki Assist",
    SubTitle = "Assistance Mode",
    TabWidth = 160,
    Size = UDim2.fromOffset(520, 380),
    Acrylic = true,
    Theme = "Dark"
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "user" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- Internal state
local whitelistedPlayer = nil
local botActive = false
local safetyPlatform = nil
local followCoroutine = nil
local handToFired = false
local toolEquipped = false
local searchDelay = 2 -- seconds between search attempts to avoid rapid searching
local standPosition = "front" -- front/back/left/right

local _baseSearchDelay = 2
local function scaleFactor()
    local sd = tonumber(searchDelay) or _baseSearchDelay
    local s = sd / _baseSearchDelay
    if s < 0.01 then s = 0.01 end
    return s
end

-- Helpers
local function findPlayerByText(text)
    if not text or text == "" then return nil end
    text = text:lower()
    for _,pl in pairs(Players:GetPlayers()) do
        if pl == LocalPlayer then continue end
        if pl.Name:lower():find(text) or (pl.DisplayName and pl.DisplayName:lower():find(text)) then
            return pl
        end
    end
    return nil
end

local function notifyLocal(title, content, duration)
    pcall(function()
        Fluent:Notify({ Title = title, Content = content, Duration = duration or 6 })
    end)
end

local function sendChatMessage(msg)
    pcall(function()
        local chat = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        if chat and chat:FindFirstChild("SayMessageRequest") then
            chat.SayMessageRequest:FireServer(msg, "All")
        end
    end)
end

local function createSafetyPlatform(heightOffset)
    heightOffset = heightOffset or 120
    if safetyPlatform and safetyPlatform.Parent then return safetyPlatform end
    local rootPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position or Vector3.new(0,0,0)
    local part = Instance.new("Part")
    part.Size = Vector3.new(20, 1, 20)
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 1
    part.Name = "_AssistPlatform"
    part.Position = rootPos + Vector3.new(0, heightOffset, 0)
    part.Parent = workspace
    safetyPlatform = part
    return part
end

local function teleportTo(pos)
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    pcall(function() hrp.CFrame = CFrame.new(pos) end)
    return true
end

local function teleportToCFrame(cframe)
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    pcall(function() hrp.CFrame = cframe end)
    return true
end

local function isDescendantOfAnyPlayerCharacter(instance)
    for _,pl in pairs(Players:GetPlayers()) do
        if pl.Character and instance:IsDescendantOf(pl.Character) then
            return true
        end
    end
    return false
end

local function equipTool(tool)
    if not tool then return false end
    local ok = pcall(function()
        local char = LocalPlayer.Character
        if not char then return false end
        local humanoid = char:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid:EquipTool(tool)
        end
    end)
    return ok
end

local function playerHasEscoba(pl)
    if not pl then return false end
    if pl.Character then
        for _,o in pairs(pl.Character:GetChildren()) do
            if o:IsA("Tool") and o.Name:lower():find("escoba") then
                return true
            end
        end
    end
    for _,o in pairs(pl.Backpack:GetChildren()) do
        if o:IsA("Tool") and o.Name:lower():find("escoba") then
            return true
        end
    end
    return false
end

local function botHasEscoba()
    local char = LocalPlayer.Character
    if char then
        for _,o in pairs(char:GetChildren()) do
            if o:IsA("Tool") and o.Name:lower():find("escoba") then
                return true
            end
        end
    end
    for _,o in pairs(LocalPlayer.Backpack:GetChildren()) do
        if o:IsA("Tool") and o.Name:lower():find("escoba") then
            return true
        end
    end
    return false
end

local function findEscobaCandidates()
    local candidates = {}
    for _,inst in pairs(workspace:GetDescendants()) do
        if inst:IsA("Model") then
            local name = inst.Name or ""
            local parentName = inst.Parent and inst.Parent.Name and tostring(inst.Parent.Name):lower() or ""
            if name:lower():find("escoba") or parentName == "escoba" then
                if not isDescendantOfAnyPlayerCharacter(inst) then
                    table.insert(candidates, inst)
                end
            end
        end
    end
    return candidates
end

local function getProximityPromptFromModel(model)
    for _,d in pairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") and (d.Name == "TakePrompt" or d.Name:lower():find("take")) then
            return d
        end
    end
    return nil
end

local function triggerPrompt(prompt)
    if not prompt then return false end
    local success = false
    pcall(function()
        -- try known global helper first
        if fireproximityprompt then
            pcall(function() fireproximityprompt(prompt) end)
            success = true
            return
        end
        if _G and _G.fireproximityprompt then
            pcall(function() _G.fireproximityprompt(prompt) end)
            success = true
            return
        end
        -- teleport closer to the prompt's base part if available to improve reliability
        local basePart = prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent or (prompt.Parent and prompt.Parent.PrimaryPart)
        if basePart and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = LocalPlayer.Character.HumanoidRootPart
            local targetPos = basePart.Position + basePart.CFrame.LookVector * 0.5 + Vector3.new(0, 1.2, 0)
            pcall(function() hrp.CFrame = CFrame.new(targetPos, basePart.Position) end)
            wait(0.15) -- small stabilization after teleport
        end

        -- mobile/executor-specific attempts: try touch-based triggering first on touch devices
        local UserInputService = game:GetService("UserInputService")
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if UserInputService and UserInputService.TouchEnabled and basePart and hrp then
            -- try common exploit touch emulator: firetouchinterest
            if firetouchinterest or (_G and _G.firetouchinterest) then
                for i = 1, 3 do
                    pcall(function()
                        if firetouchinterest then
                            firetouchinterest(basePart, hrp, 0)
                        else
                            _G.firetouchinterest(basePart, hrp, 0)
                        end
                    end)
                    wait(0.06)
                    pcall(function()
                        if firetouchinterest then
                            firetouchinterest(basePart, hrp, 1)
                        else
                            _G.firetouchinterest(basePart, hrp, 1)
                        end
                    end)
                    wait(0.09)
                end
                success = true
                return
            end
        end

        -- attempt several trigger methods with short, non-scaled pauses for reliability
        for i = 1, 4 do
            if prompt.InputHoldBegin and prompt.InputHoldEnd then
                pcall(function()
                    prompt:InputHoldBegin()
                end)
                wait(math.max(0.07, (prompt.HoldDuration or 0.1)))
                pcall(function()
                    prompt:InputHoldEnd()
                end)
            end
            pcall(function() if prompt.Trigger then prompt:Trigger() end end)
            pcall(function() if prompt.Fire then prompt:Fire() end end)
            wait(0.08)
            -- check if tool acquired in outer code; we return true as we attempted
            success = true
        end
    end)
    return success
end

local function waitForToolAcquired(timeout)
    timeout = timeout or 6
    local t0 = tick()
    while tick() - t0 < timeout do
        local char = LocalPlayer.Character
        if char then
            for _,obj in pairs(char:GetChildren()) do
                if obj:IsA("Tool") and obj.Name:lower():find("escoba") then
                    return obj
                end
            end
        end
        for _,obj in pairs(LocalPlayer.Backpack:GetChildren()) do
            if obj:IsA("Tool") and obj.Name:lower():find("escoba") then
                return obj
            end
        end
        wait(0.2)
    end
    return nil
end

local function followPlayerContinuously(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local targetHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end
    while botActive and targetPlayer and targetPlayer.Character and targetHRP.Parent do
        if not botHasEscoba() then break end
        pcall(function()
            local offset = Vector3.new(0,0,0)
            local right = targetHRP.CFrame.RightVector
            local look = targetHRP.CFrame.LookVector
            if standPosition == "front" then
                offset = look * 2
            elseif standPosition == "behind" or standPosition == "back" then
                offset = -look * 2
            elseif standPosition == "left" then
                offset = -right * 2
            elseif standPosition == "right" then
                offset = right * 2
            else
                offset = look * 2
            end
            local basePos = targetHRP.Position + offset + Vector3.new(0, 1.5, 0)
            local lookAt = targetHRP.Position + Vector3.new(0, 1.5, 0)
            -- gentle floating animation (up/down) while standing
            local floatAmp = 0.22
            local floatFreq = 1.1
            local yOffset = math.sin(tick() * floatFreq) * floatAmp
            hrp.CFrame = CFrame.lookAt(basePos + Vector3.new(0, yOffset, 0), lookAt)
        end)
        wait(0.12 * scaleFactor())
    end
end

local function acquireEscobaAndDeliverTo(targetPlayer)
    botActive = true
    handToFired = false
    toolEquipped = false
    notifyLocal("Assist", "Starting assistance procedure...", 5)

    -- create safety platform and teleport bot up
    local platform = createSafetyPlatform(120)
    wait(0.2 * scaleFactor())
    local platformPos = platform.Position + Vector3.new(0, 3, 0)
    teleportTo(platformPos)
    wait(0.5 * scaleFactor())

    -- If the target already has an Escoba, stay on the safety platform until they no longer have it
    if playerHasEscoba(targetPlayer) then
        notifyLocal("Assist", "Target already has Escoba. Waiting on safety platform...", 6)
        while playerHasEscoba(targetPlayer) and botActive do
            if safetyPlatform and safetyPlatform.Parent then
                pcall(function()
                    teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                end)
            end
            wait(math.max(0.05, 3 * scaleFactor()))
        end
        if not botActive then
            return
        end
        notifyLocal("Assist", "Target lost Escoba. Resuming assistance.", 4)
    end

    -- find candidates
    local candidates = findEscobaCandidates()
    if #candidates == 0 then
        notifyLocal("Assist", "No valid Escoba found.", 6)
        botActive = false
        return
    end

    local foundTool = nil
    for _,model in pairs(candidates) do
        if not botActive then break end
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if not primary then continue end

        -- teleport to the candidate, attempt pickup, then return to safety platform
        teleportTo(primary.Position + Vector3.new(0, 3, 0))
        wait(0.2 * scaleFactor())
        local prompt = getProximityPromptFromModel(model)
        if prompt then
            triggerPrompt(prompt)
            wait(0.3 * scaleFactor())
            local tool = waitForToolAcquired(4)
            if tool then
                foundTool = tool
                break
            end
        else
            wait(0.2 * scaleFactor())
            local tool = waitForToolAcquired(3)
            if tool then
                foundTool = tool
                break
            end
        end

        -- avoid rapid searching; continue searching in-place until delivery complete
        local sd = (type(searchDelay) == "number" and searchDelay) or tonumber(searchDelay) or 2
        wait(sd)
    end

    if not foundTool then
        notifyLocal("Assist", "Failed to acquire Escoba.", 6)
        botActive = false
        return
    end

    -- teleport back to target and follow
    if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local targetHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetHRP then
                local right = targetHRP.CFrame.RightVector
                local look = targetHRP.CFrame.LookVector
                local offset = Vector3.new(0,0,0)
                if standPosition == "front" then
                    offset = look * 2
                elseif standPosition == "behind" or standPosition == "back" then
                    offset = -look * 2
                elseif standPosition == "left" then
                    offset = -right * 2
                elseif standPosition == "right" then
                    offset = right * 2
                else
                    offset = look * 2
                end
                local frontPos = targetHRP.Position + offset
                local lookAt = targetHRP.Position + Vector3.new(0, 1.5, 0)
                local cframe = CFrame.new(frontPos + Vector3.new(0, 1.5, 0), lookAt)
                teleportToCFrame(cframe)
                wait(0.2 * scaleFactor())

                -- equip the tool once so the bot is ready to hand it over
                if not toolEquipped then
                    pcall(function()
                        equipTool(foundTool)
                    end)
                    if botHasEscoba() then
                        toolEquipped = true
                    end
                end

                -- ensure bot actually has Escoba before following
                if not botHasEscoba() then
                    notifyLocal("Assist", "Couldn't equip Escoba. Returning to safety platform.", 5)
                    if safetyPlatform and safetyPlatform.Parent then
                        pcall(function()
                            teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                        end)
                    end
                    botActive = false
                    return
                end

                followCoroutine = coroutine.create(function() followPlayerContinuously(targetPlayer) end)
                coroutine.resume(followCoroutine)
        end

        -- Try to notify target via chat
        pcall(function()
            sendChatMessage("[Assist] " .. targetPlayer.Name .. ": assistance mode enabled. A BOT will help you.")
        end)

        -- fire server HandTo event once when bot is ready and player doesn't already have Escoba
        pcall(function()
            if not handToFired and ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("HandTo") then
                if botHasEscoba() and not playerHasEscoba(targetPlayer) then
                    ReplicatedStorage.Events.HandTo:FireServer()
                    handToFired = true
                end
            end
        end)

        notifyLocal("Assist", "Escoba acquired and delivering to " .. targetPlayer.Name, 6)

        -- wait until the target player actually has the tool, then return to safety platform
        spawn(function()
            local t0 = tick()
            local timeout = 10
                while tick() - t0 < timeout do
                if playerHasEscoba(targetPlayer) then
                    -- teleport back to safety platform and stop following
                    if safetyPlatform and safetyPlatform.Parent then
                        pcall(function()
                            teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                        end)
                    end
                    botActive = false
                    return
                end
                wait(0.5 * scaleFactor())
            end
            -- if timeout, still return to platform
            if safetyPlatform and safetyPlatform.Parent then
                pcall(function()
                    teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                end)
            end
            botActive = false
        end)
    end

    -- leave botActive as-is until post-delivery checks complete
end

-- UI elements
local WhitelistInput = Tabs.Main:AddInput("WhitelistInput", {
    Title = "Whitelist Player (name/display name)",
    Placeholder = "Type a name or partial display name",
    Default = "",
    Callback = function(Value) end
})

Tabs.Main:AddButton({
    Title = "Add Whitelist",
    Description = "Whitelists the first matching player",
    Callback = function()
        local text = WhitelistInput.Value
        local pl = findPlayerByText(text)
        if not pl then
            notifyLocal("Whitelist", "Player not found: " .. tostring(text), 5)
            return
        end
        whitelistedPlayer = pl
        notifyLocal("Whitelist", "Whitelisted: " .. pl.Name, 5)
        pcall(function()
            sendChatMessage("[Assist] " .. pl.Name .. ": Assistance mode enabled. A BOT will attempt to help you.")
        end)
    end
})

Tabs.Main:AddToggle("AutoAssist", { Title = "Auto-Assist When Whitelisted", Default = true }):OnChanged(function()
    Options.AutoAssist.Value = not not Options.AutoAssist.Value
end)

-- Search speed slider
local SearchSlider = Tabs.Main:AddSlider("SearchSpeed", {
    Title = "Search Delay",
    Description = "Seconds between search attempts (lower = faster)",
    Default = searchDelay,
    Min = 0.5,
    Max = 6,
    Rounding = 0.5,
    Callback = function(Value)
        searchDelay = tonumber(Value) or searchDelay
    end
})

SearchSlider:OnChanged(function(Value)
    searchDelay = tonumber(Value) or searchDelay
end)

SearchSlider:SetValue(searchDelay)

-- Auto-Respawn indicator (always enabled) and monitor
Tabs.Main:AddToggle("AutoRespawn", { Title = "Auto-Respawn", Description = "Automatically press respawn when DeadFrame appears", Default = true, Disabled = true }):OnChanged(function() end)

-- Stand position input (front/behind/left/right)
local StandInput = Tabs.Main:AddInput("StandPositionInput", {
    Title = "Stand Position",
    Placeholder = "front / behind / left / right",
    Default = standPosition,
    Callback = function(Value) end
})

StandInput:OnChanged(function(Value)
    local v = (Value or ""):lower()
    if v == "front" or v == "behind" or v == "back" or v == "left" or v == "right" then
        if v == "back" then v = "behind" end
        standPosition = v
        notifyLocal("Assist", "Stand position set to: " .. standPosition, 3)
    else
        notifyLocal("Assist", "Invalid stand position. Use front/behind/left/right.", 4)
    end
end)

local function pressDeadFrameButton(deadFrame)
    if not deadFrame then return end
    -- First, try the exact StarterGui path the user provided
    pcall(function()
        local starter = game:GetService("StarterGui")
        if starter then
            local main = starter:FindFirstChild("Main")
            if main then
                local df = main:FindFirstChild("DeadFrame")
                if df then
                    local resp = df:FindFirstChild("Respawn")
                    if resp and resp:IsA("TextButton") then
                        pcall(function() if resp.Activate then resp:Activate() end end)
                        pcall(function() if resp.MouseButton1Click and resp.MouseButton1Click.Fire then resp.MouseButton1Click:Fire() end end)
                        notifyLocal("Auto-Respawn", "Respawn (StarterGui) pressed.", 4)
                        return
                    end
                end
            end
        end
    end)

    -- Fallback: try to find any TextButton descendant under the provided deadFrame
    local btn = nil
    for _,v in pairs(deadFrame:GetDescendants()) do
        if v:IsA("TextButton") and (v.Name == "Respawn" or v.Name:lower():find("respawn")) then
            btn = v
            break
        end
    end
    if not btn then return end
    pcall(function() if btn.Activate then btn:Activate() end end)
    pcall(function()
        if btn.MouseButton1Click and btn.MouseButton1Click.Fire then
            btn.MouseButton1Click:Fire()
        end
    end)
    notifyLocal("Auto-Respawn", "Respawn button pressed.", 4)
end

local function monitorDeadFrameAndPress()
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    -- check existing DeadFrame(s)
    for _,d in pairs(pg:GetDescendants()) do
        if d.Name == "DeadFrame" and d:IsA("Frame") then
            -- if player already dead, press immediately
            local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health <= 0 then
                pcall(function() pressDeadFrameButton(d) end)
            end
        end
    end

    -- Listen for DeadFrame added anywhere under PlayerGui
    pg.DescendantAdded:Connect(function(desc)
        if not desc then return end
        local df = nil
        if desc.Name == "DeadFrame" and desc:IsA("Frame") then
            df = desc
        elseif desc.Parent and desc.Parent.Name == "DeadFrame" then
            df = desc.Parent
        end
        if not df then return end
        -- If we're already dead, press now; otherwise press when humanoid dies
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            pcall(function() pressDeadFrameButton(df) end)
        elseif humanoid then
            humanoid.Died:Connect(function()
                wait(0.05)
                pcall(function() pressDeadFrameButton(df) end)
            end)
        else
            -- wait for character/humanoid then press on death
            LocalPlayer.CharacterAdded:Connect(function(char)
                local hd = char:WaitForChild("Humanoid", 5)
                if hd then
                    hd.Died:Connect(function()
                        wait(0.05)
                        pcall(function() pressDeadFrameButton(df) end)
                    end)
                end
            end)
        end
    end)
end

spawn(monitorDeadFrameAndPress)

-- Monitor workspace for any Model named "Ayuwoki" and move bot to safety platform if too close
spawn(function()
    while true do
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _,m in pairs(workspace:GetDescendants()) do
                if m:IsA("Model") and m.Name == "Ayuwoki" and m.Parent == workspace then
                    local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if part and (hrp.Position - part.Position).Magnitude < 15 then
                        if not safetyPlatform or not safetyPlatform.Parent then
                            createSafetyPlatform(120)
                        end
                        pcall(function()
                            teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                        end)
                        botActive = false
                        notifyLocal("Assist", "Ayuwoki nearby — returning to safety platform.", 4)
                        break
                    end
                end
            end
        end
        wait(0.25)
    end
end)

Tabs.Main:AddButton({
    Title = "Start Assistance Now",
    Description = "Immediately run the assistance routine for the whitelisted player",
    Callback = function()
        if not whitelistedPlayer then
            notifyLocal("Assist", "No whitelisted player set.", 5)
            return
        end
        if not whitelistedPlayer.Character or not whitelistedPlayer.Character:FindFirstChild("HumanoidRootPart") then
            notifyLocal("Assist", "Whitelisted player not in-game or missing character.", 5)
            return
        end
        if botActive then
            notifyLocal("Assist", "Bot is already active.", 4)
            return
        end
        spawn(function()
            acquireEscobaAndDeliverTo(whitelistedPlayer)
        end)
    end
})

Tabs.Main:AddButton({
    Title = "Stop Assistance",
    Description = "Stop any active assistance routine",
    Callback = function()
        botActive = false
        handToFired = false
        toolEquipped = false
        if followCoroutine and coroutine.status(followCoroutine) ~= "dead" then
            -- coroutine will stop due to botActive = false
        end
        if safetyPlatform and safetyPlatform.Parent then
            pcall(function() safetyPlatform:Destroy() end)
            safetyPlatform = nil
        end
        notifyLocal("Assist", "Assistance stopped.", 4)
    end
})

-- Auto-run when whitelisted player appears (if enabled)
spawn(function()
    while true do
        if whitelistedPlayer and Options.AutoAssist and Options.AutoAssist.Value and not botActive then
            if whitelistedPlayer.Character and whitelistedPlayer.Character:FindFirstChild("HumanoidRootPart") then
                spawn(function()
                    acquireEscobaAndDeliverTo(whitelistedPlayer)
                end)
            end
        end
        wait(3)
    end
end)

Window:SelectTab(1)
notifyLocal("Ayuwoki Assist", "UI loaded. Add a player to whitelist to begin.", 6)
