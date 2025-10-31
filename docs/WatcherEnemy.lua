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

local function findRootPart(model: Model): BasePart?
    if model.PrimaryPart then
        return model.PrimaryPart
    end

    local candidate = model:FindFirstChild("HumanoidRootPart")
    if candidate and candidate:IsA("BasePart") then
        model.PrimaryPart = candidate
        return candidate
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            model.PrimaryPart = child
            return child
        end
    end

    return nil
end

local root = findRootPart(watcherModel)
if not root then
    warn("Watcher script requires the model to contain a BasePart to move")
    return
end

local modelExtents = watcherModel:GetExtentsSize()
local horizontalFootprint = math.max(modelExtents.X, modelExtents.Z, root.Size.X, root.Size.Z, 1)
local rootHalfHeight = math.max(modelExtents.Y * 0.5, root.Size.Y * 0.5)
local WAYPOINT_SPACING = math.clamp(horizontalFootprint * 0.2, 1, 3)
local ARRIVAL_EPSILON = math.clamp(horizontalFootprint * 0.15, 0.75, 4)

local DEFAULT_CONFIG = {
    StopDistance = 4,
    PathRefreshSeconds = 0.5,
    MaxPathTime = 2,
    MoveSpeed = 12,
    AgentCanJump = true,
    ViewConeAngle = 55,
    RequireLineOfSight = true,
    ShowPathVisuals = true,
    PathMarkerSize = 0.75,
    PathBeamWidth = 0.12,
    PathVisualTransparency = 0.3,
    PathVisualColor = Color3.fromRGB(160, 60, 255),
    GroundOffset = rootHalfHeight,
}

local CONFIG = table.clone(DEFAULT_CONFIG)

type ConfigKey = typeof(DEFAULT_CONFIG)

local function getAttributeOrDefault(attributeName: string, defaultValue)
    local attributeValue = watcherModel:GetAttribute(attributeName)
    if attributeValue == nil then
        return defaultValue
    end

    return attributeValue
end

local function refreshConfig()
    for key, defaultValue in pairs(DEFAULT_CONFIG :: ConfigKey) do
        CONFIG[key] = getAttributeOrDefault(key, defaultValue)
    end
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
    local previousPosition = root.Position

    for _, waypoint in ipairs(waypoints) do
        if (waypoint.Position - previousPosition).Magnitude > WAYPOINT_SPACING then
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
            previousPosition = waypoint.Position
        end
    end
end

local function sanitizeWaypoints(waypoints: { PathWaypoint }): { PathWaypoint }
    if #waypoints == 0 then
        return waypoints
    end

    local sanitized = {}
    local lastPosition = root.Position

    for _, waypoint in ipairs(waypoints) do
        if (waypoint.Position - lastPosition).Magnitude > WAYPOINT_SPACING then
            table.insert(sanitized, waypoint)
            lastPosition = waypoint.Position
        end
    end

    if #sanitized == 0 then
        table.insert(sanitized, waypoints[#waypoints])
    end

    return sanitized
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

local function projectToGround(position: Vector3, extraExclude: Instance?): Vector3
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    if extraExclude then
        params.FilterDescendantsInstances = { watcherModel, extraExclude }
    else
        params.FilterDescendantsInstances = { watcherModel }
    end

    local rayOrigin = position + Vector3.new(0, CONFIG.GroundOffset * 2, 0)
    local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -CONFIG.GroundOffset * 4, 0), params)
    if result then
        return Vector3.new(position.X, result.Position.Y + CONFIG.GroundOffset, position.Z)
    end

    return position
end

local activeWaypoints: { PathWaypoint }? = nil
local activeWaypointIndex = 1
local desiredTargetPosition: Vector3? = nil
local pathExpiresAt = 0
local isComputingPath = false
local lastStepTime = 0
local immediateRepathRequested = false
local lastLookDirection = root.CFrame.LookVector

local function moveTowardsPosition(targetPosition: Vector3, dt: number): boolean
    local currentPosition = root.Position
    local delta = targetPosition - currentPosition
    if delta.Magnitude <= ARRIVAL_EPSILON then
        local horizontal = Vector3.new(lastLookDirection.X, 0, lastLookDirection.Z)
        if horizontal.Magnitude < 0.001 then
            horizontal = Vector3.new(0, 0, -1)
        end
        local lookAt = CFrame.lookAt(targetPosition, targetPosition + horizontal.Unit)
        root:PivotTo(lookAt)
        return true
    end

    local moveDistance = math.min(CONFIG.MoveSpeed * dt, delta.Magnitude)
    if moveDistance <= 0 then
        return false
    end

    local direction = delta.Unit
    local horizontal = Vector3.new(direction.X, 0, direction.Z)
    if horizontal.Magnitude < 0.001 then
        horizontal = Vector3.new(lastLookDirection.X, 0, lastLookDirection.Z)
        if horizontal.Magnitude < 0.001 then
            horizontal = Vector3.new(0, 0, -1)
        end
    else
        lastLookDirection = horizontal.Unit
    end

    local newPosition = currentPosition + direction * moveDistance
    local lookAt = CFrame.lookAt(newPosition, newPosition + horizontal.Unit)
    root:PivotTo(lookAt)

    return false
end

local function beginFollowingPath(waypoints: { PathWaypoint }, targetPosition: Vector3)
    activeWaypoints = waypoints
    activeWaypointIndex = 1
    desiredTargetPosition = targetPosition
    pathExpiresAt = os.clock() + CONFIG.MaxPathTime

    drawPath(waypoints)
end

local function computePathAsync(targetPosition: Vector3)
    if isComputingPath then
        return
    end

    isComputingPath = true

    task.spawn(function()
        local ok, err = pcall(function()
            local agentHeight = math.max(modelExtents.Y, root.Size.Y, CONFIG.GroundOffset * 2)
            local maxWidth = math.max(modelExtents.X, modelExtents.Z, root.Size.X, root.Size.Z)
            local agentRadius = math.max(maxWidth * 0.5, 2)

            local path = PathfindingService:CreatePath({
                AgentHeight = agentHeight,
                AgentRadius = agentRadius,
                AgentCanJump = CONFIG.AgentCanJump,
            })

            path:ComputeAsync(root.Position, targetPosition)
            local waypoints = sanitizeWaypoints(path:GetWaypoints())

            if path.Status == Enum.PathStatus.Success then
                if #waypoints >= 1 then
                    beginFollowingPath(waypoints, targetPosition)
                else
                    activeWaypoints = nil
                    desiredTargetPosition = targetPosition
                    clearMarkers()
                end
            else
                activeWaypoints = nil
                desiredTargetPosition = targetPosition
                clearMarkers()
            end
        end)

        if not ok then
            warn(string.format("Watcher path computation failed: %s", tostring(err)))
            activeWaypoints = nil
            desiredTargetPosition = targetPosition
            clearMarkers()
        end

        isComputingPath = false
    end)
end

local function updateMovement(dt: number)
    if activeWaypoints then
        if os.clock() >= pathExpiresAt then
            activeWaypoints = nil
            immediateRepathRequested = true
            clearMarkers()
            return
        end

        local waypoint = activeWaypoints[activeWaypointIndex]
        if not waypoint then
            activeWaypoints = nil
            desiredTargetPosition = nil
            clearMarkers()
            return
        end

        if moveTowardsPosition(waypoint.Position, dt) then
            activeWaypointIndex += 1
            if activeWaypointIndex > #activeWaypoints then
                activeWaypoints = nil
                desiredTargetPosition = nil
                clearMarkers()
            end
        end

        return
    end

    if desiredTargetPosition then
        if moveTowardsPosition(desiredTargetPosition, dt) then
            desiredTargetPosition = nil
        end
    end
end

local function onStep()
    local targetPlayer = findClosestPlayer()
    if not targetPlayer then
        activeWaypoints = nil
        desiredTargetPosition = nil
        immediateRepathRequested = false
        clearMarkers()
        return
    end

    local character = targetPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not hrp then
        return
    end

    if anyPlayerIsWatching() then
        activeWaypoints = nil
        desiredTargetPosition = nil
        immediateRepathRequested = false
        clearMarkers()
        return
    end

    local distance = (hrp.Position - root.Position).Magnitude
    if distance <= CONFIG.StopDistance then
        activeWaypoints = nil
        desiredTargetPosition = nil
        clearMarkers()
        lastLookDirection = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        return
    end

    local targetPosition = projectToGround(hrp.Position, character)

    local needsRepath = false

    if not activeWaypoints and not desiredTargetPosition then
        needsRepath = true
    elseif desiredTargetPosition and (targetPosition - desiredTargetPosition).Magnitude > WAYPOINT_SPACING then
        needsRepath = true
    elseif activeWaypoints and os.clock() >= pathExpiresAt then
        needsRepath = true
    end

    if immediateRepathRequested then
        needsRepath = true
        immediateRepathRequested = false
    end

    if needsRepath then
        computePathAsync(targetPosition)
    elseif not activeWaypoints and desiredTargetPosition then
        desiredTargetPosition = targetPosition
    end

    if not activeWaypoints and not desiredTargetPosition then
        desiredTargetPosition = targetPosition
    end
end

RunService.Heartbeat:Connect(function(dt)
    if dt <= 0 then
        return
    end

    local now = os.clock()
    if now - lastStepTime >= CONFIG.PathRefreshSeconds then
        lastStepTime = now
        onStep()
    end

    updateMovement(dt)
end)
