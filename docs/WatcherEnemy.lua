--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local watcherModel = script.Parent
if not watcherModel then
    warn("Watcher script must be parented under the NPC model")
    return
end

local humanoid: Humanoid = watcherModel:WaitForChild("Humanoid")
local root: BasePart = watcherModel:WaitForChild("HumanoidRootPart")

local DEFAULT_CONFIG = {
    StopDistance = 4,
    PathRefreshSeconds = 0.5,
    MaxPathTime = 2,
    WalkSpeed = humanoid.WalkSpeed,
    AgentCanJump = true,
    ViewConeAngle = 55,
    RequireLineOfSight = true,
    ShowPathVisuals = true,
    PathMarkerSize = 0.75,
    PathBeamWidth = 0.12,
    PathVisualTransparency = 0.3,
    PathVisualColor = Color3.fromRGB(160, 60, 255),
}

local CONFIG = table.clone(DEFAULT_CONFIG)

local function getAttributeOrDefault(attributeName: string, defaultValue)
    local attributeValue = watcherModel:GetAttribute(attributeName)
    if attributeValue == nil then
        return defaultValue
    end

    return attributeValue
end

local function refreshConfig()
    for key, defaultValue in pairs(DEFAULT_CONFIG) do
        CONFIG[key] = getAttributeOrDefault(key, defaultValue)
    end

    humanoid.WalkSpeed = CONFIG.WalkSpeed
end

refreshConfig()

for attributeName in pairs(DEFAULT_CONFIG) do
    watcherModel:GetAttributeChangedSignal(attributeName):Connect(refreshConfig)
end

local markerFolder = Instance.new("Folder")
markerFolder.Name = "PathMarkers"
markerFolder.Parent = watcherModel

local function clearMarkers()
    for _, child in ipairs(markerFolder:GetChildren()) do
        child:Destroy()
    end
end

local function drawPath(waypoints: { PathWaypoint })
    if not CONFIG.ShowPathVisuals then
        clearMarkers()
        return
    end

    clearMarkers()

    local previousAttachment: Attachment? = nil

    for _, waypoint in ipairs(waypoints) do
        local marker = Instance.new("Part")
        marker.Anchored = true
        marker.CanCollide = false
        marker.CastShadow = false
        marker.Color = CONFIG.PathVisualColor
        marker.Material = Enum.Material.Neon
        marker.Shape = Enum.PartType.Ball
        local markerSize = CONFIG.PathMarkerSize
        marker.Size = Vector3.new(markerSize, markerSize, markerSize)
        marker.CFrame = CFrame.new(waypoint.Position)
        marker.Name = "Waypoint"
        marker.Parent = markerFolder

        local attachment = Instance.new("Attachment")
        attachment.Parent = marker

        if previousAttachment then
            local beam = Instance.new("Beam")
            beam.Attachment0 = previousAttachment
            beam.Attachment1 = attachment
            beam.Color = ColorSequence.new(CONFIG.PathVisualColor)
            beam.Width0 = CONFIG.PathBeamWidth
            beam.Width1 = CONFIG.PathBeamWidth
            beam.Transparency = NumberSequence.new(CONFIG.PathVisualTransparency)
            beam.FaceCamera = true
            beam.LightEmission = 1
            beam.Parent = marker
        end

        previousAttachment = attachment
    end
end

local function findClosestPlayer(): Player?
    local closestPlayer: Player? = nil
    local shortestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if character and hrp and humanoid and humanoid.Health > 0 then
            local distance = (hrp.Position - root.Position).Magnitude
            if distance < shortestDistance then
                shortestDistance = distance
                closestPlayer = player
            end
        end
    end

    return closestPlayer
end

local visionRayParams = RaycastParams.new()
visionRayParams.FilterType = Enum.RaycastFilterType.Exclude
visionRayParams.IgnoreWater = true

local function playerCanSeeWatcher(player: Player): boolean
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not character or not hrp or not humanoid or humanoid.Health <= 0 then
        return false
    end

    local toWatcher = root.Position - hrp.Position
    local distance = toWatcher.Magnitude
    if distance < 0.001 then
        return true
    end

    local direction = toWatcher.Unit
    local lookVector = hrp.CFrame.LookVector
    local cosineThreshold = math.cos(math.rad(CONFIG.ViewConeAngle))

    if lookVector:Dot(direction) < cosineThreshold then
        return false
    end

    if not CONFIG.RequireLineOfSight then
        return true
    end

    visionRayParams.FilterDescendantsInstances = { watcherModel, character }
    local result = Workspace:Raycast(hrp.Position, direction * distance, visionRayParams)

    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(watcherModel)
end

local function anyPlayerIsWatching(): boolean
    for _, player in ipairs(Players:GetPlayers()) do
        if playerCanSeeWatcher(player) then
            return true
        end
    end

    return false
end

local activeWaypoints: { PathWaypoint }? = nil
local activeWaypointIndex = 0
local pathExpiresAt = 0
local isComputingPath = false
local pendingJumpRequest = false

local groundedStates = {
    [Enum.HumanoidStateType.Running] = true,
    [Enum.HumanoidStateType.RunningNoPhysics] = true,
    [Enum.HumanoidStateType.Landed] = true,
}

local function tryPerformPendingJump()
    if not pendingJumpRequest then
        return
    end

    if humanoid.FloorMaterial == Enum.Material.Air then
        return
    end

    humanoid.Jump = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    pendingJumpRequest = false
end

humanoid.StateChanged:Connect(function(_, newState)
    if groundedStates[newState] then
        tryPerformPendingJump()
    end
end)

local function followNextWaypoint()
    if not activeWaypoints then
        return
    end

    local nextIndex = activeWaypointIndex + 1
    if nextIndex > #activeWaypoints then
        activeWaypoints = nil
        pendingJumpRequest = false
        clearMarkers()
        return
    end

    activeWaypointIndex = nextIndex
    local waypoint = activeWaypoints[nextIndex]

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        pendingJumpRequest = true
        tryPerformPendingJump()
    end

    humanoid:MoveTo(waypoint.Position)
end

humanoid.MoveToFinished:Connect(function(reached)
    if not activeWaypoints then
        pendingJumpRequest = false
        return
    end

    if not reached then
        activeWaypoints = nil
        pendingJumpRequest = false
        pathExpiresAt = 0
        clearMarkers()
        return
    end

    followNextWaypoint()
end)

local function computePath(targetPosition: Vector3)
    if isComputingPath then
        return
    end

    isComputingPath = true

    local path = PathfindingService:CreatePath({
        AgentCanJump = CONFIG.AgentCanJump,
    })

    path:ComputeAsync(root.Position, targetPosition)

    isComputingPath = false

    if path.Status ~= Enum.PathStatus.Success then
        activeWaypoints = nil
        pendingJumpRequest = false
        clearMarkers()
        humanoid:MoveTo(targetPosition)
        pathExpiresAt = tick() + CONFIG.PathRefreshSeconds
        return
    end

    activeWaypoints = path:GetWaypoints()
    activeWaypointIndex = 0
    pendingJumpRequest = false
    pathExpiresAt = tick() + CONFIG.MaxPathTime

    drawPath(activeWaypoints)
    followNextWaypoint()
end

RunService.Heartbeat:Connect(function()
    if humanoid.Health <= 0 then
        activeWaypoints = nil
        clearMarkers()
        return
    end

    local targetPlayer = findClosestPlayer()
    if not targetPlayer then
        activeWaypoints = nil
        clearMarkers()
        return
    end

    local character = targetPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if not character or not hrp then
        activeWaypoints = nil
        clearMarkers()
        return
    end

    if anyPlayerIsWatching() then
        if activeWaypoints then
            activeWaypoints = nil
            pendingJumpRequest = false
            clearMarkers()
        end

        humanoid:MoveTo(root.Position)
        return
    end

    local distance = (hrp.Position - root.Position).Magnitude
    if distance <= CONFIG.StopDistance then
        if activeWaypoints then
            activeWaypoints = nil
            pendingJumpRequest = false
            clearMarkers()
        end

        humanoid:MoveTo(root.Position)
        return
    end

    local now = tick()
    if now >= pathExpiresAt then
        activeWaypoints = nil
    end

    if not activeWaypoints then
        computePath(hrp.Position)
        return
    end
end)
