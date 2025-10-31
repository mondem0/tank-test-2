# tank-test-2

## Roblox "Stalker" Enemy AI

Use the Lua script in [`docs/StalkerEnemy.lua`](docs/StalkerEnemy.lua) to create an enemy NPC that constantly tries to keep a fixed distance from the closest player. The NPC backs away if the player gets too close and advances if they get too far. The script also leaves a neon breadcrumb trail with beams that show the computed navigation path.

### Step-by-step setup in Roblox Studio

1. **Create the enemy model**
   - Insert an NPC (e.g., a R15 dummy) into the workspace and rename the model `StalkerEnemy`.
   - Make sure the model contains a `Humanoid` object and a `HumanoidRootPart` (default for Roblox characters). Set the model's `PrimaryPart` to `HumanoidRootPart`.

2. **Add configuration attributes (optional)**
   - With the model selected, create Number attributes to tweak behavior:
     - `DesiredDistance` (studs) – default 14. The distance the NPC tries to maintain from the player.
     - `DistanceTolerance` (studs) – default 2. How much wiggle room is allowed before the NPC moves.
     - `PathRefreshSeconds` – default 0.5. How often the path recalculates.
     - `MaxPathTime` – default 1.5. Caps how long the NPC commits to a path before recomputing.
   - If you skip this step the script falls back to its default values.

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
     - Spawn glowing spheres and beams that reveal each waypoint in the computed path.
   - The trail updates every time the NPC recalculates its path, so you can visualize how it reacts to obstacles and player movement.

5. **Cleanup (optional)**
   - You can recolor or resize the visuals by editing the `PATH_VISUAL_COLOR`, beam width, or marker size constants near the top of the script.
   - To disable visuals entirely, remove the body of the `drawPath` function.

### Notes

- The script assumes the NPC has enough room to pathfind. Place a `NavigationMesh` or set your workspace terrain settings if your experience uses custom navigation agents.
- Because the script runs on the server it will guide the NPC consistently for all players.
- For large experiences consider adding throttling or using `PathfindingService:CreatePath` with customized agent parameters to better match your enemy's collision size.
