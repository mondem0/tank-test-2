--[=[
Stalker enemy script
====================

This version keeps the enemy at a configurable standoff radius from the nearest
player without relying on Humanoids. The model is pivoted directly along the
computed path so any creature built from anchored parts can glide across the
world. The navigation stack is intentionally written from scratch so oversized
rigs stop spinning on their initial waypoint and immediately seek meaningful
markers.
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local model = script.Parent
if not model or not model:IsA("Model") then
    error("StalkerEnemy.lua must be placed inside a Model")
end

if not model.PrimaryPart then
    error("Assign a PrimaryPart to the stalker model before running this script")
end

local primary = model.PrimaryPart

local baseParts = {}
local originalAnchored = {}
local originalMassless = {}

for _, descendant in ipairs(model:GetDescendants()) do
    if descendant:IsA("BasePart") then
        table.insert(baseParts, descendant)
        originalAnchored[descendant] = descendant.Anchored
        originalMassless[descendant] = descendant.Massless
    end
end

local currentAnchoringState

local function applyAnchoring(shouldAnchor)
    if currentAnchoringState == shouldAnchor then
        return
    end

    currentAnchoringState = shouldAnchor

    for _, part in ipairs(baseParts) do
        if shouldAnchor then
            part.Anchored = true
            part.Massless = true
        else
            local anchored = originalAnchored[part]
            if anchored ~= nil then
                part.Anchored = anchored
            else
                part.Anchored = false
            end

            local massless = originalMassless[part]
            if massless ~= nil then
                part.Massless = massless
            else
                part.Massless = false
            end
        end
    end
end

local _, boundsSize = model:GetBoundingBox()
local footprint = Vector2.new(math.max(boundsSize.X, 1), math.max(boundsSize.Z, 1))
local tallestAxis = math.max(boundsSize.Y, 1)

local baseDefaults = {
    DesiredDistance = 12,
    DistanceTolerance = 1.75,
    MoveSpeed = 12,
    RepathInterval = 0.35,
    RepathDistance = 6,
    AgentCanJump = true,
    AgentMaxSlope = 35,
    ShowPathVisuals = true,
    PathBeamWidth = 0.18,
    PathTransparency = 0.2,
    AutoAnchorParts = false,
}

local dynamicDefaults = {
    GroundOffset = function()
        return tallestAxis * 0.5
    end,
    AgentHeight = function()
        return tallestAxis + 4
    end,
    AgentRadius = function()
        return math.max(math.min(footprint.X, footprint.Y) * 0.5, 2)
    end,
    PathMarkerSize = function()
        return math.clamp(math.max(footprint.X, footprint.Y) * 0.35, 1.5, 10)
    end,
    PathColor = function()
        return Color3.fromRGB(255, 170, 0)
    end,
}

local config = {}

local function readAttribute(name)
    local value = model:GetAttribute(name)
    if value ~= nil then
        return value
    end

    local dynamic = dynamicDefaults[name]
    if dynamic then
        return dynamic()
    end

    return baseDefaults[name]
end

local function applyConfig()
    local previousAnchoring = config.AutoAnchorParts

    config.DesiredDistance = math.max(0, readAttribute("DesiredDistance"))
    config.DistanceTolerance = math.max(0.25, readAttribute("DistanceTolerance"))
    config.MoveSpeed = math.max(0, readAttribute("MoveSpeed"))
    config.RepathInterval = math.max(0.05, readAttribute("RepathInterval"))
    config.RepathDistance = math.max(0, readAttribute("RepathDistance"))
    config.GroundOffset = readAttribute("GroundOffset")
    config.AgentHeight = math.max(2, readAttribute("AgentHeight"))
    config.AgentRadius = math.max(1, readAttribute("AgentRadius"))
    config.AgentCanJump = readAttribute("AgentCanJump") and true or false
    config.AgentMaxSlope = math.clamp(readAttribute("AgentMaxSlope"), 0, 89)
    config.ShowPathVisuals = readAttribute("ShowPathVisuals") and true or false
    config.PathMarkerSize = math.max(0.5, readAttribute("PathMarkerSize"))
    config.PathBeamWidth = math.max(0.01, readAttribute("PathBeamWidth"))
    config.PathColor = readAttribute("PathColor")
    config.PathTransparency = math.clamp(readAttribute("PathTransparency"), 0, 1)
    config.AutoAnchorParts = readAttribute("AutoAnchorParts") and true or false

    if previousAnchoring == nil or previousAnchoring ~= config.AutoAnchorParts then
        applyAnchoring(config.AutoAnchorParts)
    end
end

applyConfig()
model.AttributeChanged:Connect(applyConfig)

local pathFolder = Instance.new("Folder")
pathFolder.Name = "PathMarkers"
pathFolder.Parent = model

local pathVisuals = {
    markers = {},
    beams = {},
}

local function clearVisuals()
    for _, inst in ipairs(pathVisuals.markers) do
        inst:Destroy()
    end

    for _, inst in ipairs(pathVisuals.beams) do
        inst:Destroy()
    end

    pathVisuals.markers = {}
    pathVisuals.beams = {}
end

local function buildVisuals(points)
    clearVisuals()

    if not config.ShowPathVisuals then
        return
    end

    local previousAttachment
    for index, point in ipairs(points) do
        local marker = Instance.new("Part")
        marker.Shape = Enum.PartType.Ball
        marker.Material = Enum.Material.Neon
        marker.Color = config.PathColor
        marker.Transparency = config.PathTransparency
        marker.CanCollide = false
        marker.Anchored = true
        marker.Size = Vector3.new(config.PathMarkerSize, config.PathMarkerSize, config.PathMarkerSize)
        marker.CFrame = CFrame.new(point.position)
        marker.Name = string.format("Waypoint_%d", index)
        marker.Parent = pathFolder

        local attachment = Instance.new("Attachment")
        attachment.Name = "MarkerAttachment"
        attachment.Parent = marker

        if previousAttachment then
            local beam = Instance.new("Beam")
            beam.Attachment0 = previousAttachment
            beam.Attachment1 = attachment
            beam.Width0 = config.PathBeamWidth
            beam.Width1 = config.PathBeamWidth
            beam.Color = ColorSequence.new(config.PathColor)
            beam.Transparency = NumberSequence.new(config.PathTransparency)
            beam.Parent = marker
            table.insert(pathVisuals.beams, beam)
        end

        previousAttachment = attachment
        table.insert(pathVisuals.markers, marker)
    end
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function projectToGround(position)
    raycastParams.FilterDescendantsInstances = { model }

    local rayOrigin = position + Vector3.new(0, config.AgentHeight, 0)
    local rayDirection = Vector3.new(0, -config.AgentHeight * 2, 0)
    local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if result then
        return result.Position + Vector3.new(0, config.GroundOffset, 0)
    end

    return position
end

local trackedDirection
local lastGoalPosition
local lastPathTime = 0

local activePath = {}
local waypointIndex = 1

local function measureFootprintTolerance()
    return math.max(config.DistanceTolerance, math.max(footprint.X, footprint.Y) * 0.35)
end

local function choosePlayer()
    local rootPosition = primary.CFrame.Position
    local bestPlayer
    local bestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character and character.PrimaryPart then
            local distance = (character.PrimaryPart.Position - rootPosition).Magnitude
            if distance < bestDistance then
                bestDistance = distance
                bestPlayer = character
            end
        end
    end

    return bestPlayer
end

local function computeOrbitDirection(targetCharacter)
    local playerRoot = targetCharacter.PrimaryPart
    local toEnemy = primary.CFrame.Position - playerRoot.Position
    local planar = Vector3.new(toEnemy.X, 0, toEnemy.Z)

    if planar.Magnitude > 1e-3 then
        trackedDirection = planar.Unit
        return
    end

    if trackedDirection then
        local planarDirection = Vector3.new(trackedDirection.X, 0, trackedDirection.Z)
        if planarDirection.Magnitude > 1e-3 then
            trackedDirection = planarDirection.Unit
            return
        end
    end

    local lookVector = playerRoot.CFrame.LookVector
    planar = Vector3.new(-lookVector.X, 0, -lookVector.Z)
    if planar.Magnitude > 1e-3 then
        trackedDirection = planar.Unit
    else
        trackedDirection = Vector3.new(0, 0, -1)
    end
end

local function computeGoal(targetCharacter)
    computeOrbitDirection(targetCharacter)
    local playerRoot = targetCharacter.PrimaryPart
    local desiredOffset = trackedDirection * config.DesiredDistance
    local desired = playerRoot.Position + Vector3.new(desiredOffset.X, 0, desiredOffset.Z)

    return projectToGround(desired)
end

local function filterWaypoints(rawWaypoints, goal)
    local trimmed = {}
    local minSpacing = math.max(config.AgentRadius * 0.6, 2)
    local lastPosition

    for _, waypoint in ipairs(rawWaypoints) do
        local pos = waypoint.Position
        if not lastPosition then
            if (pos - primary.CFrame.Position).Magnitude >= minSpacing then
                lastPosition = pos
                table.insert(trimmed, { position = pos, action = waypoint.Action })
            end
        else
            if (pos - lastPosition).Magnitude >= minSpacing then
                lastPosition = pos
                table.insert(trimmed, { position = pos, action = waypoint.Action })
            end
        end
    end

    if goal and (#trimmed == 0 or (goal - trimmed[#trimmed].position).Magnitude >= minSpacing) then
        table.insert(trimmed, { position = goal, action = Enum.PathWaypointAction.Walk })
    end

    return trimmed
end

local function requestPath(goalPosition)
    local path = PathfindingService:CreatePath({
        AgentRadius = config.AgentRadius,
        AgentHeight = config.AgentHeight,
        AgentCanJump = config.AgentCanJump,
        AgentMaxSlope = config.AgentMaxSlope,
    })

    local success = pcall(function()
        path:ComputeAsync(primary.CFrame.Position, goalPosition)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local trimmed = filterWaypoints(path:GetWaypoints(), goalPosition)
        activePath = trimmed
        waypointIndex = 1
        buildVisuals(trimmed)
    else
        activePath = {}
        waypointIndex = 1
        clearVisuals()
    end

    lastPathTime = os.clock()
    lastGoalPosition = goalPosition
end

local function shouldRepath(goalPosition)
    if not lastGoalPosition then
        return true
    end

    if (goalPosition - lastGoalPosition).Magnitude >= config.RepathDistance then
        return true
    end

    if os.clock() - lastPathTime >= config.RepathInterval then
        return true
    end

    return false
end

local function withinTolerance(goalPosition)
    local position = primary.CFrame.Position
    local delta = goalPosition - position
    local planar = Vector3.new(delta.X, 0, delta.Z)

    return planar.Magnitude <= measureFootprintTolerance()
end

local function advanceWaypoint()
    waypointIndex += 1
    if waypointIndex > #activePath then
        activePath = {}
        waypointIndex = 1
    end
end

local function stepAlong(goalPosition, targetCharacter, dt)
    if #activePath == 0 then
        if withinTolerance(goalPosition) then
            return
        end

        local start = primary.CFrame.Position
        local delta = goalPosition - start
        local planar = Vector3.new(delta.X, 0, delta.Z)
        local planarDistance = planar.Magnitude
        if planarDistance < 1e-4 then
            return
        end

        local maxStep = config.MoveSpeed * dt
        local stepAmount = math.min(planarDistance, maxStep)
        local stepVector = planar.Unit * stepAmount

        local newPlanar = Vector3.new(start.X + stepVector.X, start.Y, start.Z + stepVector.Z)
        local vertical = math.clamp(goalPosition.Y - newPlanar.Y, -config.MoveSpeed * dt, config.MoveSpeed * dt)
        local targetPosition = Vector3.new(newPlanar.X, newPlanar.Y + vertical, newPlanar.Z)

        local lookTarget
        if targetCharacter and targetCharacter.PrimaryPart then
            lookTarget = targetCharacter.PrimaryPart.Position
        else
            lookTarget = targetPosition + primary.CFrame.LookVector
        end

        local orientation = CFrame.new(targetPosition, Vector3.new(lookTarget.X, targetPosition.Y, lookTarget.Z))
        model:PivotTo(orientation)
        return
    end

    local waypoint = activePath[waypointIndex]
    local waypointPos = waypoint.position
    local currentPosition = primary.CFrame.Position
    local offset = waypointPos - currentPosition
    local planarOffset = Vector3.new(offset.X, 0, offset.Z)

    local tolerance = measureFootprintTolerance()
    if planarOffset.Magnitude <= tolerance and math.abs(offset.Y) <= config.AgentHeight then
        advanceWaypoint()
        return
    end

    local maxStep = config.MoveSpeed * dt
    if maxStep <= 0 then
        return
    end

    local planarStep
    local planarDistance = planarOffset.Magnitude
    if planarDistance < 1e-4 then
        planarStep = Vector3.zero
    else
        planarStep = planarOffset.Unit * math.min(planarDistance, maxStep)
    end

    local newX = currentPosition.X + planarStep.X
    local newZ = currentPosition.Z + planarStep.Z
    local verticalStep = math.clamp(offset.Y, -config.MoveSpeed * dt, config.MoveSpeed * dt)
    local newY = currentPosition.Y + verticalStep
    local newPosition = Vector3.new(newX, newY, newZ)

    local lookTarget
    if targetCharacter and targetCharacter.PrimaryPart then
        local focus = targetCharacter.PrimaryPart.Position
        lookTarget = Vector3.new(focus.X, newY, focus.Z)
    else
        lookTarget = newPosition + primary.CFrame.LookVector
    end

    local newFrame = CFrame.new(newPosition, lookTarget)
    model:PivotTo(newFrame)

    if planarOffset.Magnitude <= tolerance and math.abs(offset.Y) <= config.AgentHeight then
        advanceWaypoint()
    end
end

local function facePlayer(character)
    if not character or not character.PrimaryPart then
        return
    end

    local currentPosition = primary.CFrame.Position
    local focus = character.PrimaryPart.Position
    local lookFrame = CFrame.new(currentPosition, Vector3.new(focus.X, currentPosition.Y, focus.Z))
    model:PivotTo(lookFrame)
end

RunService.Heartbeat:Connect(function(dt)
    local character = choosePlayer()
    if not character then
        trackedDirection = nil
        activePath = {}
        waypointIndex = 1
        clearVisuals()
        return
    end

    local goal = computeGoal(character)
    if shouldRepath(goal) then
        requestPath(goal)
    elseif #activePath == 0 then
        lastGoalPosition = goal
    end

    if withinTolerance(goal) then
        facePlayer(character)
    else
        stepAlong(goal, character, dt)
    end
end)
