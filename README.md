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
     - Buffer jump requests until the humanoid is grounded so it only leaps once per obstacle instead of chaining mid-air jumps.
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

## Roblox "Watcher" Enemy AI

[`docs/WatcherEnemy.lua`](docs/WatcherEnemy.lua) powers a second type of enemy that stalks players only when nobody is watching it. The NPC freezes in place whenever any player keeps it inside their view cone and only resumes the chase once every observer looks away or loses line of sight.

### Step-by-step setup in Roblox Studio

1. **Create the enemy model**
   - Insert an NPC into the workspace and rename the model `WatcherEnemy` (any name works, but using a unique label helps keep things organized).
   - Confirm the model contains a `Humanoid` and `HumanoidRootPart`, and set the model's `PrimaryPart` to the root.

2. **Add configuration attributes (optional)**
   - Select the watcher model and add attributes to customize the behavior. All attributes default to the script values if omitted.
     - `StopDistance` *(NumberValue, studs, default 4)* – Distance from the target player where the watcher stops advancing.
     - `PathRefreshSeconds` *(NumberValue, default 0.5)* – Minimum time before recomputing the chase path.
     - `MaxPathTime` *(NumberValue, default 2)* – How long the watcher follows the current waypoint list before forcing a refresh.
     - `WalkSpeed` *(NumberValue, default matches the Humanoid)* – Movement speed while it creeps forward unseen.
     - `AgentCanJump` *(BoolValue, default true)* – Allows the pathfinder to request jumps when clearing obstacles.
     - `ViewConeAngle` *(NumberValue, degrees, default 55)* – Size of the cone that counts as “looking” at the watcher.
     - `RequireLineOfSight` *(BoolValue, default true)* – If true, the watcher only freezes when players can see it directly with no obstacles in the way.
     - `ShowPathVisuals` *(BoolValue, default true)* – Toggles the neon waypoint markers and beams used to visualize the active path.
     - `PathMarkerSize` *(NumberValue, default 0.75)* – Diameter of each waypoint sphere.
     - `PathBeamWidth` *(NumberValue, default 0.12)* – Thickness of the neon beams between waypoints.
     - `PathVisualTransparency` *(NumberValue 0-1, default 0.3)* – Transparency of the waypoint visuals.
     - `PathVisualColor` *(Color3Value, default RGB 160,60,255)* – Tint used for the watcher’s path effects.
   - Attribute changes apply immediately while testing, so you can tweak the watcher without editing the Script.

3. **Insert the script**
   - Create a **Script** under the watcher model.
   - Copy the contents of [`docs/WatcherEnemy.lua`](docs/WatcherEnemy.lua) into the Script.
   - The script sets up a `PathMarkers` folder under the model to hold any debug visuals.

4. **Test the behavior**
   - Start a Roblox Studio playtest.
   - The watcher enemy will:
     - Identify the closest living player on every heartbeat.
     - Freeze instantly if any player is looking at it inside the configured view cone (and, if enabled, with a clear line of sight).
     - Resume creeping toward the target as soon as everyone looks away.
     - Pathfind around obstacles while unseen, jumping only when grounded to clear ledges.
     - Halt once it reaches the configured stopping distance or becomes observed again.
     - Spawn purple neon spheres and beams to show the route it is currently following when visuals are enabled.

5. **Fine-tuning later**
   - Adjust or remove attributes at any time to experiment with different levels of aggression or stealth.
   - Removing custom attributes reverts that setting to the script default automatically.

### Notes

- Because observation checks run every heartbeat on the server, the watcher reacts immediately to players looking at it even in multiplayer sessions.
- If `RequireLineOfSight` is disabled, the watcher will also freeze when players stare at it through walls, which can be useful for simple horror setups.
- Pairing the watcher with the stalker enemy lets you create varied pressure—one hovers at a distance, while the other advances only when nobody keeps an eye on it.
