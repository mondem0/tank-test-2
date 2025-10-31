--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local stalkerModel = script.Parent
if not stalkerModel or not stalkerModel:IsA("Model") then
    warn("Stalker enemy script must be parented to a Model")
    return
end

local function resolvePrimaryPart(model: Model): BasePart?
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end

    local humanoidRoot = model:FindFirstChild("HumanoidRootPart")
    if humanoidRoot and humanoidRoot:IsA("BasePart") then
        model.PrimaryPart = humanoidRoot
        return humanoidRoot
    end

    for _, child in model:GetChildren() do
        if child:IsA("BasePart") then
            model.PrimaryPart = child
            return child
        end
    end

    return nil
end

local root = resolvePrimaryPart(stalkerModel)
if not root then
    warn("Stalker enemy requires a PrimaryPart or any BasePart to move")
    return
end

root.Anchored = true

local function anchorModelParts(model: Model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
        end
    end
end

anchorModelParts(stalkerModel)

local _, boundsSize = stalkerModel:GetBoundingBox()
local horizontalFootprint = math.max(boundsSize.X, boundsSize.Z, 2)
local modelHalfHeight = math.max(boundsSize.Y * 0.5, root.Size.Y * 0.5)
local arrivalRadius = math.max(horizontalFootprint * 0.45, 1.5)
local waypointSpacing = math.max(horizontalFootprint * 0.35, 1)

local DEFAULTS = {
    DesiredDistance = 12,
    DistanceTolerance = 1.75,
    MoveSpeed = 12,
    RepathInterval = 0.35,
    RepathDistance = 6,
    GroundOffset = modelHalfHeight,
    AgentHeight = boundsSize.Y + 4,
    AgentRadius = math.max(horizontalFootprint * 0.5, 2),
    AgentCanJump = true,
    AgentMaxSlope = 35,
    ShowPathVisuals = true,
    PathMarkerSize = math.max(horizontalFootprint * 0.25, 0.6),
    PathBeamWidth = 0.18,
    PathColor = Color3.fromRGB(255, 170, 0),
    PathTransparency = 0.2,
}

type Config = typeof(DEFAULTS)
local CONFIG: Config = table.clone(DEFAULTS)

local pathMarkersFolder = Instance.new("Folder")
pathMarkersFolder.Name = "PathMarkers"
pathMarkersFolder.Parent = stalkerModel

local groundRayParams = RaycastParams.new()
groundRayParams.FilterDescendantsInstances = { stalkerModel }
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function readAttribute(attributeName: string, defaultValue: any)
    local value = stalkerModel:GetAttribute(attributeName)
    if value == nil then
        return defaultValue
    end

    return value
end

local function refreshConfig()
    for key, defaultValue in pairs(DEFAULTS) do
        (CONFIG :: any)[key] = readAttribute(key, defaultValue)
    end
end

refreshConfig()
for key in pairs(DEFAULTS) do
    stalkerModel:GetAttributeChangedSignal(key):Connect(refreshConfig)
end

local function clearMarkers()
    for _, child in ipairs(pathMarkersFolder:GetChildren()) do
        child:Destroy()
    end
end

local function renderPath(waypoints: { PathWaypoint })
    if not CONFIG.ShowPathVisuals then
        clearMarkers()
        return
    end

    clearMarkers()

    local previousAttachment: Attachment? = nil
    for _, waypoint in ipairs(waypoints) do
        local markerSize = CONFIG.PathMarkerSize
        local marker = Instance.new("Part")
        marker.Name = "Waypoint"
        marker.Anchored = true
        marker.CanCollide = false
        marker.CastShadow = false
        marker.Color = CONFIG.PathColor
        marker.Material = Enum.Material.Neon
        marker.Shape = Enum.PartType.Ball
        marker.Transparency = CONFIG.PathTransparency
        marker.Size = Vector3.new(markerSize, markerSize, markerSize)
        marker.CFrame = CFrame.new(waypoint.Position)
        marker.Parent = pathMarkersFolder

        local attachment = Instance.new("Attachment")
        attachment.Parent = marker

        if previousAttachment then
            local beam = Instance.new("Beam")
            beam.Attachment0 = previousAttachment
            beam.Attachment1 = attachment
            beam.Color = ColorSequence.new(CONFIG.PathColor)
            beam.Width0 = CONFIG.PathBeamWidth
            beam.Width1 = CONFIG.PathBeamWidth
            beam.Transparency = NumberSequence.new(CONFIG.PathTransparency)
            beam.FaceCamera = true
            beam.LightEmission = 1
            beam.Parent = marker
        end

        previousAttachment = attachment
    end
end

local lastFacing = root.CFrame.LookVector
local activeWaypoints: { PathWaypoint } = {}
local currentWaypointIndex = 1
local lastPathCompute = 0
local lastDestination: Vector3? = nil

local function trimWaypoints(waypoints: { PathWaypoint }, startPosition: Vector3): { PathWaypoint }
    if #waypoints == 0 then
        return {
            {
                Position = startPosition,
                Action = Enum.PathWaypointAction.Walk,
            },
        }
    end

    local trimmed: { PathWaypoint } = {}
    local previous = startPosition

    for index, waypoint in ipairs(waypoints) do
        local distance = (waypoint.Position - previous).Magnitude
        if distance >= waypointSpacing or index == #waypoints then
            table.insert(trimmed, waypoint)
            previous = waypoint.Position
        end
    end

    if #trimmed == 0 then
        table.insert(trimmed, {
            Position = waypoints[#waypoints].Position,
            Action = Enum.PathWaypointAction.Walk,
        })
    end

    return trimmed
end

local function computePath(destination: Vector3)
    local path = PathfindingService:CreatePath({
        AgentRadius = CONFIG.AgentRadius,
        AgentHeight = CONFIG.AgentHeight,
        AgentCanJump = CONFIG.AgentCanJump,
        AgentMaxSlope = CONFIG.AgentMaxSlope,
    })

    local success = false
    local status: Enum.PathStatus? = nil
    local waypoints: { PathWaypoint } = {}

    local ok, err = pcall(function()
        path:ComputeAsync(root.Position, destination)
    end)

    if ok then
        status = path.Status
        if status == Enum.PathStatus.Success then
            success = true
            waypoints = path:GetWaypoints()
        end
    else
        warn("Failed to compute stalker path:", err)
    end

    if not success then
        activeWaypoints = {
            {
                Position = destination,
                Action = Enum.PathWaypointAction.Walk,
            },
        }
        currentWaypointIndex = 1
        renderPath(activeWaypoints)
        lastDestination = destination
        lastPathCompute = os.clock()
        return
    end

    local trimmed = trimWaypoints(waypoints, root.Position)
    if #trimmed > 0 and (trimmed[1].Position - root.Position).Magnitude < waypointSpacing then
        table.remove(trimmed, 1)
    end

    if #trimmed == 0 then
        trimmed = {
            {
                Position = destination,
                Action = Enum.PathWaypointAction.Walk,
            },
        }
    end

    activeWaypoints = trimmed
    currentWaypointIndex = 1
    renderPath(activeWaypoints)
    lastDestination = destination
    lastPathCompute = os.clock()
end

local function ensureGrounded(position: Vector3): Vector3
    local rayOrigin = position + Vector3.new(0, CONFIG.GroundOffset * 2, 0)
    local rayDirection = Vector3.new(0, -CONFIG.GroundOffset * 4, 0)
    local result = Workspace:Raycast(rayOrigin, rayDirection, groundRayParams)
    if result then
        return Vector3.new(position.X, result.Position.Y, position.Z)
    end

    return Vector3.new(position.X, position.Y, position.Z)
end

local function findClosestPlayerRoot(): BasePart?
    local closestRoot: BasePart? = nil
    local closestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and hrp and hrp:IsA("BasePart") then
                local distance = (hrp.Position - root.Position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestRoot = hrp
                end
            end
        end
    end

    return closestRoot
end

local function planarDistance(a: Vector3, b: Vector3): number
    local delta = a - b
    return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function updateFacing(moveDirection: Vector3)
    local planar = Vector3.new(moveDirection.X, 0, moveDirection.Z)
    if planar.Magnitude > 0.1 then
        lastFacing = planar.Unit
    end
end

local function moveAlongPath(dt: number)
    local waypoint = activeWaypoints[currentWaypointIndex]
    if not waypoint then
        return
    end

    local walkwayPosition = ensureGrounded(waypoint.Position)
    local targetPosition = walkwayPosition + Vector3.new(0, CONFIG.GroundOffset, 0)
    local currentPosition = root.Position
    local delta = targetPosition - currentPosition
    local horizontalDistance = planarDistance(targetPosition, currentPosition)
    local verticalDistance = math.abs(delta.Y)

    if horizontalDistance <= arrivalRadius and verticalDistance <= CONFIG.GroundOffset * 1.5 then
        currentWaypointIndex += 1
        return
    end

    local moveSpeed = math.max(CONFIG.MoveSpeed, 0)
    if moveSpeed <= 0 then
        return
    end

    local stepDistance = moveSpeed * dt
    if stepDistance <= 0 then
        return
    end

    local distanceToWaypoint = delta.Magnitude
    if distanceToWaypoint < 1e-4 then
        currentWaypointIndex += 1
        return
    end

    local direction = delta / distanceToWaypoint
    updateFacing(direction)

    local travel = math.min(stepDistance, distanceToWaypoint)
    local newPosition = currentPosition + direction * travel
    local lookVector = lastFacing.Magnitude > 0 and lastFacing or Vector3.new(0, 0, -1)
    local pivotCFrame = CFrame.lookAt(newPosition, newPosition + lookVector, Vector3.new(0, 1, 0))
    stalkerModel:PivotTo(pivotCFrame)
end

local function computeDesiredDestination(playerRoot: BasePart): Vector3
    local rootPosition = root.Position
    local playerPosition = playerRoot.Position

    local offset = Vector3.new(rootPosition.X, 0, rootPosition.Z) - Vector3.new(playerPosition.X, 0, playerPosition.Z)
    if offset.Magnitude < 0.5 then
        offset = -playerRoot.CFrame.LookVector
        offset = Vector3.new(offset.X, 0, offset.Z)
    end

    if offset.Magnitude < 0.5 then
        offset = Vector3.new(0, 0, -1)
    end

    offset = offset.Unit
    local desired = Vector3.new(playerPosition.X, playerPosition.Y, playerPosition.Z) + offset * CONFIG.DesiredDistance
    return ensureGrounded(desired)
end

local function shouldRecomputePath(destination: Vector3): boolean
    if not lastDestination then
        return true
    end

    if (destination - lastDestination).Magnitude >= CONFIG.RepathDistance then
        return true
    end

    if os.clock() - lastPathCompute >= CONFIG.RepathInterval then
        return true
    end

    local finalWaypoint = activeWaypoints[#activeWaypoints]
    if finalWaypoint then
        local finalPosition = ensureGrounded(finalWaypoint.Position)
        if planarDistance(finalPosition, destination) > arrivalRadius then
            return true
        end
    end

    return false
end

local function update(dt: number)
    local targetRoot = findClosestPlayerRoot()
    if not targetRoot then
        clearMarkers()
        activeWaypoints = {}
        currentWaypointIndex = 1
        return
    end

    local destination = computeDesiredDestination(targetRoot)
    local distanceToPlayer = planarDistance(root.Position, targetRoot.Position)
    local distanceError = math.abs(distanceToPlayer - CONFIG.DesiredDistance)

    if distanceError <= CONFIG.DistanceTolerance then
        activeWaypoints = {}
        currentWaypointIndex = 1
        clearMarkers()
        local lookVector = Vector3.new((targetRoot.Position - root.Position).X, 0, (targetRoot.Position - root.Position).Z)
        if lookVector.Magnitude > 0.1 then
            lastFacing = lookVector.Unit
            local pivot = CFrame.lookAt(root.Position, root.Position + lastFacing, Vector3.new(0, 1, 0))
            stalkerModel:PivotTo(pivot)
        end
        return
    end

    if #activeWaypoints == 0 then
        computePath(destination)
    elseif shouldRecomputePath(destination) then
        computePath(destination)
    end

    moveAlongPath(dt)
end

RunService.Heartbeat:Connect(function(dt)
    update(dt)
end)
