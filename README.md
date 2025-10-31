# tank-test-2

## Roblox "Stalker" Enemy AI

Use the Lua script in [`docs/StalkerEnemy.lua`](docs/StalkerEnemy.lua) to create an enemy NPC that constantly tries to keep a fixed distance from the closest player. The NPC backs away if the player gets too close and advances if they get too far. The script also leaves a neon breadcrumb trail with beams that show the computed navigation path.

### Step-by-step setup in Roblox Studio

1. **Create the enemy model**
   - Insert an NPC (e.g., a R15 dummy) into the workspace and rename the model `StalkerEnemy`.
   - Make sure the model contains a `Humanoid` object and a `HumanoidRootPart` (default for Roblox characters). Set the model's `PrimaryPart` to `HumanoidRootPart`.

2. **Add configuration attributes (optional)**
   - With the model selected, create attributes to tweak behavior. All attributes are optional—any you omit will use the defaults baked into the script.
     - `DesiredDistance` *(NumberValue, studs, default 14)* – How far the NPC wants to stay from the tracked player.
     - `DistanceTolerance` *(NumberValue, studs, default 2)* – How close to the target distance the NPC must be before it stops.
     - `PathRefreshSeconds` *(NumberValue, default 0.5)* – How often to recompute the path and distance targeting.
     - `MaxPathTime` *(NumberValue, default 1.5)* – How long the NPC follows the same path before forcing a refresh.
     - `WalkSpeed` *(NumberValue, default matches Humanoid WalkSpeed)* – How fast the stalker moves while chasing.
     - `ShowPathVisuals` *(BoolValue, default true)* – Turns the neon waypoint spheres and beams on or off.
     - `PathMarkerSize` *(NumberValue, default 0.75)* – Diameter of the waypoint spheres.
     - `PathBeamWidth` *(NumberValue, default 0.15)* – Thickness of the connecting beams.
     - `PathVisualTransparency` *(NumberValue 0-1, default 0.2)* – Transparency of the beams.
     - `PathVisualColor` *(Color3Value, default RGB 255,170,0)* – Color used for both waypoint markers and beams.
     - `AgentCanJump` *(BoolValue, default true)* – Whether the computed path is allowed to include jumps.
   - The script listens for attribute changes at runtime, so you can tweak values live during a Studio playtest.

3. **Insert the script**
   - Create a **Script** inside the `StalkerEnemy` model (not a LocalScript).
   - Copy the entire contents of [`docs/StalkerEnemy.lua`](docs/StalkerEnemy.lua) and paste it into the new Script.
   - The script automatically creates a `PathMarkers` folder inside the model to hold the marker parts and beams.

4. **Test the behavior**
   - Playtest in Roblox Studio with at least one player character.
   - The NPC will:
     - Pick the closest living player each refresh cycle.
     - Compute a path that positions the NPC at the desired distance from the player.
     - Move along the path using `Humanoid:MoveTo`, backing away if the player approaches and following if the player retreats.
     - Keep gliding while recalculating paths so it doesn't pause each time it searches for a new route.
     - Snap its goal down to the walkable floor, force jumps when the pathfinder calls for it, and immediately request a new path if it slips off a ledge, so it is far less likely to get stuck on edges or when the player is above it.
     - Fall back to the player's current footing when the preferred standoff spot is unreachable, letting the stalker climb up simple parkour platforms before backing off to the desired distance again.
     - Spawn glowing spheres and beams that reveal each waypoint in the computed path.
   - The trail updates every time the NPC recalculates its path, so you can visualize how it reacts to obstacles and player movement.

5. **Fine-tuning later**
   - Update the attributes at any time to adjust the stalker's feel without editing the Script directly.
   - To revert all settings, clear the attributes you added—the defaults defined in the script will take over automatically.

### Notes

- The script assumes the NPC has enough room to pathfind. Place a `NavigationMesh` or set your workspace terrain settings if your experience uses custom navigation agents.
- Because the script runs on the server it will guide the NPC consistently for all players.
- For large experiences consider adding throttling or using `PathfindingService:CreatePath` with customized agent parameters to better match your enemy's collision size.
