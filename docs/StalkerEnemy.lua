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

local root = findRootPart(stalkerModel)
if not root then
    warn("Stalker script requires the model to contain a BasePart to move")
    return
end

local modelExtents = stalkerModel:GetExtentsSize()
local horizontalFootprint = math.max(modelExtents.X, modelExtents.Z, root.Size.X, root.Size.Z, 1)
local rootHalfHeight = math.max(modelExtents.Y * 0.5, root.Size.Y * 0.5)
local WAYPOINT_SPACING = math.clamp(horizontalFootprint * 0.2, 1, 3)
local ARRIVAL_EPSILON = math.clamp(horizontalFootprint * 0.15, 0.75, 4)

local DEFAULT_CONFIG = {
    DesiredDistance = 14,
    DistanceTolerance = 2,
    PathRefreshSeconds = 0.5,
    MaxPathTime = 1.5,
    MoveSpeed = 12,
    ShowPathVisuals = true,
    PathMarkerSize = 0.75,
    PathBeamWidth = 0.15,
    PathVisualTransparency = 0.2,
    PathVisualColor = Color3.fromRGB(255, 170, 0),
    AgentCanJump = true,
    GroundOffset = rootHalfHeight,
}

local CONFIG = table.clone(DEFAULT_CONFIG)

local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
groundRayParams.FilterDescendantsInstances = { stalkerModel }

type ConfigKey = typeof(DEFAULT_CONFIG)

local function getAttributeOrDefault(attributeName: string, defaultValue)
    local attributeValue = stalkerModel:GetAttribute(attributeName)
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

local function projectToGround(position: Vector3, extraExclude: Instance?): Vector3
    if extraExclude then
        groundRayParams.FilterDescendantsInstances = { stalkerModel, extraExclude }
    else
        groundRayParams.FilterDescendantsInstances = { stalkerModel }
    end

    local rayOrigin = position + Vector3.new(0, CONFIG.GroundOffset * 2, 0)
    local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -CONFIG.GroundOffset * 4, 0), groundRayParams)
    if result then
        return Vector3.new(position.X, result.Position.Y + CONFIG.GroundOffset, position.Z)
    end

    return position
end

local function computeTargetPosition(player: Player): (Vector3?, Vector3?)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil, nil
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
    desiredPosition = projectToGround(desiredPosition, character)

    if math.abs(hrp.Position.Y - desiredPosition.Y) > 6 then
        desiredPosition = Vector3.new(desiredPosition.X, hrp.Position.Y, desiredPosition.Z)
    end

    local fallbackPosition = projectToGround(hrp.Position, character)
    return desiredPosition, fallbackPosition
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

local function computePathAsync(targetPosition: Vector3, fallbackPosition: Vector3?)
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

            local function tryFollow(goalPosition: Vector3)
                path:ComputeAsync(root.Position, goalPosition)
                local waypoints = sanitizeWaypoints(path:GetWaypoints())

                if path.Status == Enum.PathStatus.Success then
                    if #waypoints >= 1 then
                        beginFollowingPath(waypoints, goalPosition)
                        return true
                    end

                    activeWaypoints = nil
                    desiredTargetPosition = goalPosition
                    clearMarkers()
                    return true
                end

                return false
            end

            local followed = tryFollow(targetPosition)

            if not followed and fallbackPosition then
                followed = tryFollow(fallbackPosition)
            end

            if not followed then
                activeWaypoints = nil
                desiredTargetPosition = fallbackPosition or targetPosition
                clearMarkers()
            end
        end)

        if not ok then
            warn(string.format("Stalker path computation failed: %s", tostring(err)))
            activeWaypoints = nil
            desiredTargetPosition = fallbackPosition or targetPosition
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
    local player = findClosestPlayer()
    if not player then
        activeWaypoints = nil
        desiredTargetPosition = nil
        immediateRepathRequested = false
        clearMarkers()
        return
    end

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not hrp then
        return
    end

    local targetPosition, fallbackPosition = computeTargetPosition(player)
    if not targetPosition then
        return
    end

    local currentDistance = (hrp.Position - root.Position).Magnitude
    if math.abs(currentDistance - CONFIG.DesiredDistance) <= CONFIG.DistanceTolerance then
        activeWaypoints = nil
        desiredTargetPosition = nil
        clearMarkers()
        return
    end

    local needsRepath = false

    if not activeWaypoints and not desiredTargetPosition then
        needsRepath = true
    elseif desiredTargetPosition and (targetPosition - desiredTargetPosition).Magnitude > CONFIG.DistanceTolerance then
        needsRepath = true
    elseif activeWaypoints and os.clock() >= pathExpiresAt then
        needsRepath = true
    end

    if immediateRepathRequested then
        needsRepath = true
        immediateRepathRequested = false
    end

    if needsRepath then
        computePathAsync(targetPosition, fallbackPosition)
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
