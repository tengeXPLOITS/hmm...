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
local handToActive = false
local handToCoroutine = nil
local searchDelay = 4 -- seconds between search attempts to avoid rapid searching

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
    local ok, _ = pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
            return
        end
        if _G and _G.fireproximityprompt then
            _G.fireproximityprompt(prompt)
            return
        end
        if prompt.InputHoldBegin then
            prompt:InputHoldBegin()
            wait(0.1)
            prompt:InputHoldEnd()
            return
        end
    end)
    return ok
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
        if not botHasEscoba() then
            -- stop following if bot doesn't have Escoba
            break
        end
        pcall(function()
            local frontPos = targetHRP.Position + targetHRP.CFrame.LookVector * 1.5 + Vector3.new(0, 0, 0)
            hrp.CFrame = CFrame.lookAt(frontPos, targetHRP.Position)
        end)
        wait(0.5)
    end
end

local function acquireEscobaAndDeliverTo(targetPlayer)
    botActive = true
    notifyLocal("Assist", "Starting assistance procedure...", 5)

    -- create safety platform and teleport bot up
    local platform = createSafetyPlatform(120)
    wait(0.2)
    local platformPos = platform.Position + Vector3.new(0, 3, 0)
    teleportTo(platformPos)
    wait(0.5)

    -- If the target already has an Escoba, stay on the safety platform until they no longer have it
    if playerHasEscoba(targetPlayer) then
        notifyLocal("Assist", "Target already has Escoba. Waiting on safety platform...", 6)
        while playerHasEscoba(targetPlayer) and botActive do
            if safetyPlatform and safetyPlatform.Parent then
                pcall(function()
                    teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
                end)
            end
            wait(3)
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
        wait(0.2)
        local prompt = getProximityPromptFromModel(model)
        if prompt then
            triggerPrompt(prompt)
            wait(0.3)
            local tool = waitForToolAcquired(4)
            if tool then
                foundTool = tool
                break
            end
        else
            wait(0.2)
            local tool = waitForToolAcquired(3)
            if tool then
                foundTool = tool
                break
            end
        end

        -- go back to safety platform between attempts to avoid being seen and add a delay
        if safetyPlatform and safetyPlatform.Parent then
            pcall(function()
                teleportTo(safetyPlatform.Position + Vector3.new(0, 3, 0))
            end)
            wait(0.4)
        end
        -- avoid rapid searching
        local sd = tonumber(searchDelay) or 4
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
            local frontPos = targetHRP.Position + targetHRP.CFrame.LookVector * 2 + Vector3.new(0, 3, 0)
            teleportTo(frontPos)
            wait(0.2)

            -- equip the tool if possible so the bot is ready to hand it over
            pcall(function()
                equipTool(foundTool)
            end)

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

        -- fire server HandTo event repeatedly every 70s until the player has the tool or assistance stops
        pcall(function()
            if ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("HandTo") then
                handToActive = true
                if handToCoroutine and coroutine.status(handToCoroutine) ~= "dead" then
                    -- already running
                else
                    handToCoroutine = coroutine.create(function()
                        while handToActive and botActive and not playerHasEscoba(targetPlayer) do
                            pcall(function()
                                ReplicatedStorage.Events.HandTo:FireServer()
                            end)
                            -- wait 70 seconds before next attempt
                            local waited = 0
                            while waited < 70 and handToActive and botActive and not playerHasEscoba(targetPlayer) do
                                wait(1)
                                waited = waited + 1
                            end
                        end
                        handToActive = false
                    end)
                    coroutine.resume(handToCoroutine)
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
                wait(0.5)
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
        handToActive = false
        handToCoroutine = nil
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
