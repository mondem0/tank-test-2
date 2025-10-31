--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local watcherModel = script.Parent
if not watcherModel or not watcherModel:IsA("Model") then
    warn("Watcher enemy script must be parented to a Model")
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

local root = resolvePrimaryPart(watcherModel)
if not root then
    warn("Watcher enemy requires a PrimaryPart or any BasePart to move")
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

anchorModelParts(watcherModel)

local _, boundsSize = watcherModel:GetBoundingBox()
local horizontalFootprint = math.max(boundsSize.X, boundsSize.Z, 2)
local modelHalfHeight = math.max(boundsSize.Y * 0.5, root.Size.Y * 0.5)
local arrivalRadius = math.max(horizontalFootprint * 0.45, 1.5)
local waypointSpacing = math.max(horizontalFootprint * 0.35, 1)

local DEFAULTS = {
    MoveSpeed = 10,
    StopDistance = math.max(horizontalFootprint * 0.6, 4),
    RepathInterval = 0.3,
    RepathDistance = 5,
    GroundOffset = modelHalfHeight,
    AgentHeight = boundsSize.Y + 4,
    AgentRadius = math.max(horizontalFootprint * 0.5, 2),
    AgentCanJump = true,
    AgentMaxSlope = 35,
    ViewConeAngle = 55,
    RequireLineOfSight = true,
    ShowPathVisuals = true,
    PathMarkerSize = math.max(horizontalFootprint * 0.25, 0.6),
    PathBeamWidth = 0.18,
    PathColor = Color3.fromRGB(160, 80, 255),
    PathTransparency = 0.25,
}

type Config = typeof(DEFAULTS)
local CONFIG: Config = table.clone(DEFAULTS)
local visionDotThreshold = math.cos(math.rad(CONFIG.ViewConeAngle * 0.5))

local pathMarkersFolder = Instance.new("Folder")
pathMarkersFolder.Name = "PathMarkers"
pathMarkersFolder.Parent = watcherModel

local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
groundRayParams.FilterDescendantsInstances = { watcherModel }

type AnyValue = any
local function readAttribute(attributeName: string, defaultValue: AnyValue)
    local value = watcherModel:GetAttribute(attributeName)
    if value == nil then
        return defaultValue
    end
    return value
end

local function refreshConfig()
    for key, defaultValue in pairs(DEFAULTS) do
        (CONFIG :: any)[key] = readAttribute(key, defaultValue)
    end

    local cone = math.clamp(CONFIG.ViewConeAngle, 1, 179)
    visionDotThreshold = math.cos(math.rad(cone * 0.5))
end

refreshConfig()
for key in pairs(DEFAULTS) do
    watcherModel:GetAttributeChangedSignal(key):Connect(refreshConfig)
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
local lastDestination: Vector3? = nil
local lastPathCompute = 0

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

local function ensureGrounded(position: Vector3): Vector3
    local rayOrigin = position + Vector3.new(0, CONFIG.GroundOffset * 2, 0)
    local rayDirection = Vector3.new(0, -CONFIG.GroundOffset * 4, 0)
    local result = Workspace:Raycast(rayOrigin, rayDirection, groundRayParams)
    if result then
        return Vector3.new(position.X, result.Position.Y, position.Z)
    end

    return Vector3.new(position.X, position.Y, position.Z)
end

local function computePath(destination: Vector3)
    local path = PathfindingService:CreatePath({
        AgentRadius = CONFIG.AgentRadius,
        AgentHeight = CONFIG.AgentHeight,
        AgentCanJump = CONFIG.AgentCanJump,
        AgentMaxSlope = CONFIG.AgentMaxSlope,
    })

    local ok, err = pcall(function()
        path:ComputeAsync(root.Position, destination)
    end)

    local success = ok and path.Status == Enum.PathStatus.Success
    local waypoints = success and path:GetWaypoints() or nil

    if not success or not waypoints then
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
    watcherModel:PivotTo(pivotCFrame)
end

local function findClosestPlayerRoot(): BasePart?
    local closest: BasePart? = nil
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
                    closest = hrp
                end
            end
        end
    end

    return closest
end

local function hasLineOfSight(character: Model, targetPosition: Vector3): boolean
    if not CONFIG.RequireLineOfSight then
        return true
    end

    local head = character:FindFirstChild("Head")
    local originPart = (head and head:IsA("BasePart")) and head or character:FindFirstChild("HumanoidRootPart")
    if not originPart or not originPart:IsA("BasePart") then
        return false
    end

    local origin = originPart.Position
    local direction = targetPosition - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { watcherModel, character }

    local result = Workspace:Raycast(origin, direction, params)
    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(watcherModel)
end

local function isObserved(targetPosition: Vector3): boolean
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and hrp and hrp:IsA("BasePart") then
                local lookVector = hrp.CFrame.LookVector
                if lookVector.Magnitude > 0 then
                    local toEnemy = targetPosition - hrp.Position
                    if toEnemy.Magnitude > 0 then
                        local dot = toEnemy.Unit:Dot(lookVector.Unit)
                        if dot >= visionDotThreshold then
                            if hasLineOfSight(character, targetPosition) then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

local function computeDestination(playerRoot: BasePart): Vector3?
    local rootPosition = root.Position
    local playerPosition = playerRoot.Position

    local planarToPlayer = Vector3.new(playerPosition.X - rootPosition.X, 0, playerPosition.Z - rootPosition.Z)
    local distance = planarToPlayer.Magnitude
    if distance <= CONFIG.StopDistance then
        return nil
    end

    local direction = planarToPlayer.Unit
    local destination = playerPosition - direction * CONFIG.StopDistance
    destination = ensureGrounded(destination)
    return destination
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

    local enemyPosition = root.Position
    local observed = isObserved(enemyPosition)

    if observed then
        clearMarkers()
        activeWaypoints = {}
        currentWaypointIndex = 1
        local lookVector = Vector3.new((targetRoot.Position - enemyPosition).X, 0, (targetRoot.Position - enemyPosition).Z)
        if lookVector.Magnitude > 0.1 then
            lastFacing = lookVector.Unit
            watcherModel:PivotTo(CFrame.lookAt(enemyPosition, enemyPosition + lastFacing, Vector3.new(0, 1, 0)))
        end
        return
    end

    local destination = computeDestination(targetRoot)
    if not destination then
        clearMarkers()
        activeWaypoints = {}
        currentWaypointIndex = 1
        local lookVector = Vector3.new((targetRoot.Position - enemyPosition).X, 0, (targetRoot.Position - enemyPosition).Z)
        if lookVector.Magnitude > 0.1 then
            lastFacing = lookVector.Unit
            watcherModel:PivotTo(CFrame.lookAt(enemyPosition, enemyPosition + lastFacing, Vector3.new(0, 1, 0)))
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
