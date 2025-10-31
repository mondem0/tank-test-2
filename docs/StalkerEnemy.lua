--!strict

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

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
    ShowPathVisuals = true,
    PathMarkerSize = 0.75,
    PathBeamWidth = 0.15,
    PathVisualTransparency = 0.2,
    PathVisualColor = Color3.fromRGB(255, 170, 0),
    AgentCanJump = true,
}

local CONFIG = table.clone(DEFAULT_CONFIG)

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

local function waitForMove(timeout: number)
    local completed = false
    local connection: RBXScriptConnection? = nil
    connection = humanoid.MoveToFinished:Connect(function()
        completed = true
    end)

    local startTime = os.clock()
    while not completed and os.clock() - startTime < timeout do
        RunService.Heartbeat:Wait()
    end

    if connection then
        connection:Disconnect()
    end

    return completed
end

local function computeTargetPosition(player: Player): Vector3?
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end

    local offsetDirection = hrp.Position - root.Position
    if offsetDirection.Magnitude < 0.5 then
        local lookVector = hrp.CFrame.LookVector
        if lookVector.Magnitude > 0.1 then
            offsetDirection = lookVector
        else
            offsetDirection = Vector3.new(0, 0, -1)
        end
    end

    offsetDirection = offsetDirection.Unit
    return hrp.Position - offsetDirection * CONFIG.DesiredDistance
end

local function onStep()
    if humanoid.Health <= 0 then
        clearMarkers()
        return
    end

    local player = findClosestPlayer()
    if not player then
        humanoid:MoveTo(root.Position)
        clearMarkers()
        return
    end

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not hrp then
        return
    end

    local currentDistance = (hrp.Position - root.Position).Magnitude
    if math.abs(currentDistance - CONFIG.DesiredDistance) <= CONFIG.DistanceTolerance then
        humanoid:MoveTo(root.Position)
        clearMarkers()
        return
    end

    local targetPosition = computeTargetPosition(player)
    if not targetPosition then
        return
    end

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

    if path.Status ~= Enum.PathStatus.Success or #waypoints == 0 then
        clearMarkers()
        humanoid:MoveTo(targetPosition)
        waitForMove(CONFIG.PathRefreshSeconds)
        return
    end

    drawPath(waypoints)

    local pathStart = os.clock()

    for index = 2, #waypoints do
        local waypoint = waypoints[index]
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end

        humanoid:MoveTo(waypoint.Position)
        local reached = waitForMove(CONFIG.PathRefreshSeconds)

        local updatedDistance = (hrp.Position - root.Position).Magnitude
        if math.abs(updatedDistance - CONFIG.DesiredDistance) <= CONFIG.DistanceTolerance then
            break
        end

        if not reached then
            break
        end

        if os.clock() - pathStart > CONFIG.MaxPathTime then
            break
        end
    end
end

while task.wait(CONFIG.PathRefreshSeconds) do
    onStep()
end
