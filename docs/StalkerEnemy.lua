--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local stalkerModel = script.Parent
if not stalkerModel then
    warn("Stalker script must be parented under the NPC model")
    return
end

local humanoid: Humanoid = stalkerModel:WaitForChild("Humanoid")
local root: BasePart = stalkerModel:WaitForChild("HumanoidRootPart")

local DEFAULT_CONFIG = {
    DesiredDistance = 14,
    DistanceTolerance = 2,
    PathRefreshSeconds = 0.5,
    MaxPathTime = 1.5,
    WalkSpeed = humanoid.WalkSpeed,
    ShowPathVisuals = true,
    PathMarkerSize = 0.75,
    PathBeamWidth = 0.15,
    PathVisualTransparency = 0.2,
    PathVisualColor = Color3.fromRGB(255, 170, 0),
    AgentCanJump = true,
}

local CONFIG = table.clone(DEFAULT_CONFIG)

local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
groundRayParams.FilterDescendantsInstances = { stalkerModel }

local function getAttributeOrDefault(attributeName: string, defaultValue)
    local attributeValue = stalkerModel:GetAttribute(attributeName)
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
    stalkerModel:GetAttributeChangedSignal(attributeName):Connect(refreshConfig)
end

local markerFolder = Instance.new("Folder")
markerFolder.Name = "PathMarkers"
markerFolder.Parent = stalkerModel

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

local function computeTargetPosition(player: Player): Vector3?
    local character = player.Character
    if character then
        groundRayParams.FilterDescendantsInstances = { stalkerModel, character }
    else
        groundRayParams.FilterDescendantsInstances = { stalkerModel }
    end
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end

    local rootPosition = root.Position
    local horizontalOffset = Vector3.new(hrp.Position.X - rootPosition.X, 0, hrp.Position.Z - rootPosition.Z)

    if horizontalOffset.Magnitude < 0.5 then
        local lookVector = hrp.CFrame.LookVector
        horizontalOffset = Vector3.new(lookVector.X, 0, lookVector.Z)
        if horizontalOffset.Magnitude < 0.1 then
            horizontalOffset = Vector3.new(0, 0, -1)
        end
    end

    local direction = horizontalOffset.Unit
    local desiredPosition = Vector3.new(hrp.Position.X, rootPosition.Y, hrp.Position.Z) - direction * CONFIG.DesiredDistance

    local rayOrigin = desiredPosition + Vector3.new(0, CONFIG.DesiredDistance, 0)
    local raycastResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -CONFIG.DesiredDistance * 4, 0), groundRayParams)
    if raycastResult then
        desiredPosition = Vector3.new(desiredPosition.X, raycastResult.Position.Y + humanoid.HipHeight, desiredPosition.Z)
    else
        desiredPosition = Vector3.new(desiredPosition.X, rootPosition.Y, desiredPosition.Z)
    end

    if math.abs(hrp.Position.Y - desiredPosition.Y) > 6 then
        desiredPosition = Vector3.new(desiredPosition.X, hrp.Position.Y, desiredPosition.Z)
    end

    return desiredPosition
end

local activeWaypoints: { PathWaypoint }? = nil
local activeWaypointIndex = 0
local desiredTargetPosition: Vector3? = nil
local pathExpiresAt = 0
local isComputingPath = false
local lastStepTime = 0
local immediateRepathRequested = false

local function followNextWaypoint()
    if not activeWaypoints then
        return
    end

    local nextIndex = activeWaypointIndex + 1
    if nextIndex > #activeWaypoints then
        activeWaypoints = nil
        clearMarkers()
        return
    end

    activeWaypointIndex = nextIndex
    local waypoint = activeWaypoints[nextIndex]

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        humanoid.Jump = true
    end

    humanoid:MoveTo(waypoint.Position)
end

humanoid.MoveToFinished:Connect(function(reached)
    if not activeWaypoints then
        return
    end

    if reached then
        followNextWaypoint()
    else
        activeWaypoints = nil
        immediateRepathRequested = true
    end
end)

local function beginFollowingPath(waypoints: { PathWaypoint }, targetPosition: Vector3)
    activeWaypoints = waypoints
    activeWaypointIndex = 1
    desiredTargetPosition = targetPosition
    pathExpiresAt = os.clock() + CONFIG.MaxPathTime

    drawPath(waypoints)
    followNextWaypoint()
end

local function computePathAsync(targetPosition: Vector3)
    if isComputingPath then
        return
    end

    isComputingPath = true

    task.spawn(function()
        local ok, err = pcall(function()
            local agentHeight = math.max(root.Size.Y, humanoid.HipHeight * 2)
            local agentRadius = math.max(root.Size.X * 0.5, 2)

            local success, description = pcall(function()
                return humanoid:GetAppliedDescription()
            end)
            if success and description then
                agentHeight = math.max(agentHeight, 5 * description.HeightScale)
            end

            local path = PathfindingService:CreatePath({
                AgentHeight = agentHeight,
                AgentRadius = agentRadius,
                AgentCanJump = CONFIG.AgentCanJump,
            })

            path:ComputeAsync(root.Position, targetPosition)
            local waypoints = path:GetWaypoints()

            if path.Status == Enum.PathStatus.Success and #waypoints >= 2 then
                beginFollowingPath(waypoints, targetPosition)
            else
                activeWaypoints = nil
                clearMarkers()
                humanoid:MoveTo(targetPosition)
            end
        end)

        if not ok then
            warn(string.format("Stalker path computation failed: %s", tostring(err)))
            activeWaypoints = nil
            clearMarkers()
            humanoid:MoveTo(targetPosition)
        end

        isComputingPath = false
    end)
end

local function onStep()
    if humanoid.Health <= 0 then
        activeWaypoints = nil
        clearMarkers()
        return
    end

    local player = findClosestPlayer()
    if not player then
        activeWaypoints = nil
        desiredTargetPosition = nil
        clearMarkers()
        humanoid:MoveTo(root.Position)
        return
    end

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not hrp then
        return
    end

    local targetPosition = computeTargetPosition(player)
    if not targetPosition then
        return
    end

    local currentDistance = (hrp.Position - root.Position).Magnitude
    if math.abs(currentDistance - CONFIG.DesiredDistance) <= CONFIG.DistanceTolerance then
        activeWaypoints = nil
        desiredTargetPosition = nil
        clearMarkers()
        humanoid:MoveTo(root.Position)
        return
    end

    local needsRepath = false

    if not activeWaypoints then
        needsRepath = true
    elseif os.clock() >= pathExpiresAt then
        needsRepath = true
    elseif desiredTargetPosition and (targetPosition - desiredTargetPosition).Magnitude > CONFIG.DistanceTolerance then
        needsRepath = true
    end

    if immediateRepathRequested then
        needsRepath = true
        immediateRepathRequested = false
    end

    if needsRepath then
        computePathAsync(targetPosition)
    end

    if not activeWaypoints then
        humanoid:MoveTo(targetPosition)
        desiredTargetPosition = targetPosition
    end
end

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastStepTime >= CONFIG.PathRefreshSeconds then
        lastStepTime = now
        onStep()
    end
end)
