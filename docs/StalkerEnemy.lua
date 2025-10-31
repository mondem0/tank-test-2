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

local DESIRED_DISTANCE = stalkerModel:GetAttribute("DesiredDistance") or 14
local DISTANCE_TOLERANCE = stalkerModel:GetAttribute("DistanceTolerance") or 2
local PATH_REFRESH = stalkerModel:GetAttribute("PathRefreshSeconds") or 0.5
local MAX_PATH_TIME = stalkerModel:GetAttribute("MaxPathTime") or 1.5
local PATH_VISUAL_COLOR = Color3.fromRGB(255, 170, 0)

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
    clearMarkers()

    local previousAttachment: Attachment? = nil

    for _, waypoint in ipairs(waypoints) do
        local marker = Instance.new("Part")
        marker.Anchored = true
        marker.CanCollide = false
        marker.CastShadow = false
        marker.Color = PATH_VISUAL_COLOR
        marker.Material = Enum.Material.Neon
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(0.75, 0.75, 0.75)
        marker.CFrame = CFrame.new(waypoint.Position)
        marker.Name = "Waypoint"
        marker.Parent = markerFolder

        local attachment = Instance.new("Attachment")
        attachment.Parent = marker

        if previousAttachment then
            local beam = Instance.new("Beam")
            beam.Attachment0 = previousAttachment
            beam.Attachment1 = attachment
            beam.Color = ColorSequence.new(PATH_VISUAL_COLOR)
            beam.Width0 = 0.15
            beam.Width1 = 0.15
            beam.Transparency = NumberSequence.new(0.2)
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
    return hrp.Position - offsetDirection * DESIRED_DISTANCE
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
    if math.abs(currentDistance - DESIRED_DISTANCE) <= DISTANCE_TOLERANCE then
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
        AgentCanJump = true,
    })

    path:ComputeAsync(root.Position, targetPosition)
    local waypoints = path:GetWaypoints()

    if path.Status ~= Enum.PathStatus.Success or #waypoints == 0 then
        clearMarkers()
        humanoid:MoveTo(targetPosition)
        waitForMove(PATH_REFRESH)
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
        local reached = waitForMove(PATH_REFRESH)

        local updatedDistance = (hrp.Position - root.Position).Magnitude
        if math.abs(updatedDistance - DESIRED_DISTANCE) <= DISTANCE_TOLERANCE then
            break
        end

        if not reached then
            break
        end

        if os.clock() - pathStart > MAX_PATH_TIME then
            break
        end
    end
end

while task.wait(PATH_REFRESH) do
    onStep()
end
