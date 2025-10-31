# Roblox Enemy AI Scripts

This repository ships two standalone Roblox server scripts that drive enemy behaviors without relying on `Humanoid:MoveTo`. Both scripts only need a model with a `PrimaryPart`; they keep that part anchored and pivot the entire model along the computed navigation path so custom creatures of any size stay in control.

- [`docs/StalkerEnemy.lua`](docs/StalkerEnemy.lua) keeps its distance from the closest player by constantly backing up or advancing until it matches a configurable standoff radius.
- [`docs/WatcherEnemy.lua`](docs/WatcherEnemy.lua) stalks the nearest player but freezes the moment anyone is looking at it, resuming the chase as soon as every observer looks away.

## Using the scripts in Roblox Studio

### 1. Prepare the model

1. Insert or build the mesh/rig you want to control.
2. Set the model's **PrimaryPart** to the piece you want the script to move. A `Humanoid` is optional; any `BasePart` works.
3. Drop a normal **Script** under the model and paste the contents of the desired file from the `docs/` folder.

Both scripts will anchor the `PrimaryPart`, create a `PathMarkers` folder for debug visuals, and size their pathfinding agents from the full model bounds so oversized monsters behave reliably.

### 2. Optional configuration attributes

Add attributes to the model to override any of the defaults listed below. You can tweak them live during a Play Test; the scripts pick up changes immediately.

#### Stalker enemy attributes

| Attribute | Type | Default | Description |
| --- | --- | --- | --- |
| `DesiredDistance` | Number | 12 | Ideal distance (studs) the stalker tries to maintain from the closest player. |
| `DistanceTolerance` | Number | 1.75 | Allowed error before the stalker stops moving and simply faces the player. |
| `MoveSpeed` | Number | 12 | Glide speed when approaching the next waypoint. |
| `RepathInterval` | Number | 0.35 | Minimum time (seconds) between path recomputations. |
| `RepathDistance` | Number | 6 | How far the destination must shift before forcing a new path immediately. |
| `GroundOffset` | Number | Half the model height | Vertical offset that keeps the PrimaryPart hovering just above the floor. |
| `AgentHeight` | Number | Model height + 4 | Pathfinding agent height passed to `CreatePath`. |
| `AgentRadius` | Number | Half the footprint (min 2) | Pathfinding agent radius. |
| `AgentCanJump` | Boolean | `true` | Allows the path to include jump links when necessary. |
| `AgentMaxSlope` | Number | 35 | Maximum slope angle the pathfinder will consider walkable. |
| `ShowPathVisuals` | Boolean | `true` | Toggles neon waypoint spheres and beams. |
| `PathMarkerSize` | Number | Scaled to model | Diameter of the waypoint markers. |
| `PathBeamWidth` | Number | 0.18 | Width of the connecting beams. |
| `PathColor` | Color3 | Orange | Color used for both markers and beams. |
| `PathTransparency` | Number | 0.2 | Transparency applied to the path visuals. |

#### Watcher enemy attributes

| Attribute | Type | Default | Description |
| --- | --- | --- | --- |
| `MoveSpeed` | Number | 10 | Glide speed while the watcher is unobserved. |
| `StopDistance` | Number | `max(footprint * 0.6, 4)` | Distance from the target player where the watcher stops advancing. |
| `RepathInterval` | Number | 0.3 | Minimum seconds between path recomputations. |
| `RepathDistance` | Number | 5 | How far the goal must shift before forcing a new path. |
| `GroundOffset` | Number | Half the model height | Vertical offset that keeps the PrimaryPart hovering above the floor. |
| `AgentHeight` | Number | Model height + 4 | Pathfinding agent height passed to `CreatePath`. |
| `AgentRadius` | Number | Half the footprint (min 2) | Pathfinding agent radius. |
| `AgentCanJump` | Boolean | `true` | Allows jump links in the computed path. |
| `AgentMaxSlope` | Number | 35 | Maximum slope angle considered walkable. |
| `ViewConeAngle` | Number | 55 | Field-of-view cone in degrees. Players inside this cone freeze the watcher. |
| `RequireLineOfSight` | Boolean | `true` | If enabled, the watcher only freezes when no solid geometry blocks the view. |
| `ShowPathVisuals` | Boolean | `true` | Toggles neon waypoint spheres and beams. |
| `PathMarkerSize` | Number | Scaled to model | Diameter of the waypoint markers. |
| `PathBeamWidth` | Number | 0.18 | Width of the connecting beams. |
| `PathColor` | Color3 | Purple | Color used for markers and beams. |
| `PathTransparency` | Number | 0.25 | Transparency for the path visuals. |

Remove an attribute to fall back to the default listed above.

### 3. Testing tips

- Both enemies recalculate their desired destination every heartbeat and trim away zero-length waypoints so the first marker never spawns inside the model.
- The scripts raycast beneath each goal to stay glued to the ground even when the player stands on ledges.
- The watcher checks every player each heartbeat. If any player is inside the configured view cone (and, if required, has direct line of sight) the watcher clears its path, faces the player, and waits.
- Because the movement loop pivots the model instead of using physics, the enemies glide smoothly even while new paths are being computed.
- For best results make sure your place has a navigation mesh that matches your level geometry so Roblox pathfinding can find routes onto platforms.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Enemy spins or won't leave the first waypoint | Confirm the model's `PrimaryPart` is centered and that the navigation mesh covers the area between the enemy and the player. The scripts already ignore zero-length waypoints; spinning usually indicates a missing or obstructed navmesh. |
| Enemy floats too high/low | Adjust the `GroundOffset` attribute so the PrimaryPart sits exactly where you want. |
| Watcher never moves | Lower `ViewConeAngle`, disable `RequireLineOfSight`, or verify no player is constantly staring at the enemy during tests. |

Playtest your experience in Roblox Studio to validate movement—these scripts run entirely on the server and depend on Studio's pathfinding simulation for final behavior.
