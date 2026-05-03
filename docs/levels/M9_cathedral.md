# M9 Arena C "Собор" (Cathedral) — design artifact

**Status**: LOCKED — finale arena per user approval 2026-05-03
**Replaces**: abandoned "Шахта" (multi-tier) + abandoned "Дорога" (journey room-and-corridor)
**Identity**: "Sacred space defiled" — sci-fi cathedral aesthetic, 4 altar capture + boss kill finale

## Concept

Player wins by capturing 4 altars + killing boss + alive within drain economy (no timer pressure — drain is the timer).

Sequence:
1. Run start — 4 altars active simultaneously (red emissive), each spawning enemies independently
2. Player approaches altar zone (Area3D 10×2×10 around altar) → dwell timer 4s starts
3. Enemy in zone → contested (red, dwell reset to 0)
4. Player solo dwell 4s → captured (green emissive, locked) + cap restore +10
5. Captured altar stops spawning (immediate tactical relief)
6. 4 captured → 2s silence → boss spawns at center (BossSpawn marker)
7. Kill boss + alive → win
8. Drain to 0 anywhere → loss

No timer (per game-designer locked spec). Drain economy creates urgency.

## Geometry (locked, see `scenes/arenas/arena_c_cathedral.tscn`)

**Footprint**: 44×44, **closed ceiling 12u** (sci-fi cathedral feel + future wall-run friendly)
**Origin** `(0, 0, 0)` = floor center. Player spawn `(0, 1, 18)` (south wall, facing north).

### Walls (12u high)
- WallNorth pos=(0, 6, -22) size=(44, 12, 0.5)
- WallSouth pos=(0, 6, 22) size=(44, 12, 0.5)
- WallEast pos=(22, 6, 0) size=(0.5, 12, 44)
- WallWest pos=(-22, 6, 0) size=(0.5, 12, 44)
- Ceiling pos=(0, 12.05, 0) size=(44, 0.1, 44)
- Floor pos=(0, -0.05, 0) size=(44, 0.1, 44)

### NO central platform (removed per user 2026-05-03)
BossSpawn Marker3D at `(0, 0.5, 0)` — flat floor center spawn position.

### 4 Altar Clusters (corners ±15, 0, ±15)
Each cluster: 3 columns 2×2×4 forming П-shape pocket with opening to center.

NW cluster (mirror NE/SE/SW):
- Col_NW_A pos=(-17, 2, -17) size=(2, 4, 2)
- Col_NW_B pos=(-13, 2, -17) size=(2, 4, 2)
- Col_NW_C pos=(-17, 2, -13) size=(2, 4, 2)

### 4 Altars (visual only — pass-through beam)
**Altar_*_Top** CSGCylinder3D radius **3.0** height 8, position y=4 (centered vertical pillar of light), `use_collision=false`.

Material: StandardMaterial3D semi-transparent (alpha 0.4) + emissive. **State color** controlled by AltarDirector via `material_override`:
- Uncaptured: red `Color(1.0, 0.2, 0.2)` slow pulse
- Capturing (player solo): yellow `Color(1.0, 0.9, 0.0)` fast pulse
- Contested (enemy in zone): red fast pulse (dwell reset)
- Captured: green `Color(0.2, 1.0, 0.3)` static + brief flash burst

**Group**: `navmesh_excluded` (NavBaker detaches from tree during bake — see memory rule `feedback_godot_navmesh_csg_visibility.md`).

### 4 Altar Capture Zones (Area3D)
**AltarArea_*** BoxShape3D size **(10, 2, 10)** at altar position. **collision_mask = 6** (player layer 2 + enemy layer 4 — both detected for capture vs contested logic).

### 8 Spawn-points (between cluster and outer wall)
- SpawnNW_1 (-20, 0, -15), SpawnNW_2 (-15, 0, -20)
- SpawnNE_1 (20, 0, -15), SpawnNE_2 (15, 0, -20)
- SpawnSE_1 (20, 0, 15), SpawnSE_2 (15, 0, 20)
- SpawnSW_1 (-20, 0, 15), SpawnSW_2 (-15, 0, 20)

Each ≥2u from columns + 2u from walls (anti-stuck spawn).

### Optional pews (atmosphere)
4 long boxes between center and W/E walls — décor, no gameplay function.

## Materials (per level-designer lock)

| Geometry | Color | Emissive |
|---|---|---|
| Floor | `Color(0.5, 0.48, 0.5)` | — |
| Outer walls | `Color(0.3, 0.3, 0.35)` | — |
| Ceiling | `Color(0.2, 0.2, 0.25)` | — |
| Altar columns | `Color(0.4, 0.38, 0.4)` | — |
| Altar beam | state-colored | 1.0 energy |
| Pews | `Color(0.35, 0.28, 0.22)` | — |

## NavMesh

NavigationRegion3D + NavBaker (existing pattern):
- `agent_radius = 0.3`
- `agent_height = 1.8`
- `agent_max_climb = 0.6`
- `agent_max_slope = 45°`
- `parsed_geometry_type = MESH_INSTANCES`
- `partition_type = WATERSHED`
- Group `navigation_geometry` on arena root + child meshes

Altar beams excluded via `navmesh_excluded` group → NavBaker detaches from tree during bake.

## Mechanic — Altar Capture Director

**Architecture** (autoload `AltarDirector`):
- Activates on arena root group `objective_cathedral`
- Tracks 4 altar states (uncaptured/capturing/contested/captured) + dwell timers + spawn timers
- Each frame:
  - For uncaptured/contested altars: count player + enemy bodies в Area3D `get_overlapping_bodies()`. If player solo → state=CAPTURING + increment dwell. If enemy joins → state=CONTESTED + dwell=0. Player leaves → state=UNCAPTURED + dwell=0.
  - For captured altars: spawn loop disabled.
  - For all uncaptured: spawn enemy on `_spawn_timer` interval (~3-5s) at one of 2 zone spawn-points (anti-overlap check `_is_spawn_area_clear` r=1.2 mask=4 — mirror SpawnController).
- Dwell ≥ 4s in CAPTURING → state=CAPTURED, emit `Events.altar_captured(index)` + `VelocityGate.apply_altar_reward(10)` (cap +10 mirror sphere reward — no player_hit emit).
- 4 captured → 2s silence timer → spawn boss at BossSpawn → emit `Events.boss_phase_started`.

**Spawn weights per phase**:
- Phase 0 (0 captured): 50% melee, 30% shooter, 20% swarm
- Phase 1+: shifts toward swarm (test post-playtest)

## HUD

- **Capturing progress bar** above cap bar — visible когда player в any altar zone with active dwell. Yellow fill, "CAPTURING" label, hides on captured/leave.
- **Boss HP bar top-center** appears when boss spawns (`Events.boss_phase_started`):
  - 768×24 px width, BOSS label
  - 2 vertical phase markers at 67% and 34% (boundaries)
  - Color shifts discrete green→orange→red per phase
  - Hides on `boss_killed` или `player_died`

## Win/Death screens

- Win: "AREA CLEARED" + score (kills × avg_cap)
- Drain death: "VELOCITY DRAINED"
- (No "objective failed" — no timer, only drain death possible)

## Implementation history

- Cathedral concept brainstorm (level-designer 2026-05-03) — chosen over Maze/Pillared/Quadrants/Funnel/Boss-Duel alternatives
- Geometry impl `f2f9807` (~520 lines tscn)
- Altar mechanic `bd8724b → 86074e2` (4 commits, AltarDirector + spawn integration + HUD)
- Pass-through visual `c73bc68 → 8ecd050` (disc + beam → beam-only)
- Color states `f92a643 → e1c8b5e` (red/yellow/green + progress bar)
- Beam radius enlargement `d6d40b9` (3.0u radius pillar of light)
- Contested mask fix `50d331d` (collision_mask 2→6)
- NavMesh CSG visibility fix `4aea02e` (detach-from-tree pattern)
- Spawn position fixes `ab831ef` (move outside columns) + `1629a8a` (anti-overlap check)
- Detection radius bump `99df2fe` (35→50 для 44×44 arena coverage)
- Shooter REPOSITION liveliness `48ad9ab` (stuck-timer bail)

## Open questions / followups

- Single-source-of-truth for `BOSS_PHASE_*_HP_RATIO` (duplicated в run_hud + boss.gd) — prototype scope OK, refactor если становится maintenance burden.
- AltarDirector spawn weights — TBD post-playtest balance.
- Wall-run skill (M9 step 4 pending) — outer walls 44u long × 12u high are wall-run prime surfaces.
