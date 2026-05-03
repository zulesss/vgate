# M9 Boss Redesign — design artifact

**Status**: LOCKED — boss for Cathedral finale per user approval 2026-05-03
**Identity**: 3-phase escalating threat — territorial → aggressive → desperate
**Class**: `EnemyBoss extends EnemyMelee` (`objects/boss.gd`)

## Stats (after redesign)

- **HP**: 800 (was 200 → 400 → 800, scaled per playtest feedback for finale-worthy fight, ~32s sustained @ 25 DPS)
- **move_speed**: 4.0 (Phase 1-2), boost 5.0 in Phase 3
- **attack_range**: 2.5 (default melee swing reach)
- **attack_penalty**: 25 (default), 30 (charge hit), 25 (AOE hit)
- **attack_cooldown**: 2.5 (default), separate cooldowns for charge (4s) + AOE (6s)
- **attack_windup**: 0.5
- **detection_radius**: 40 (raised from 35 to handle Cathedral 44×44 distances)

Visual: scale 1.6, golden HDR emissive `Color(2.0, 0.8, 0.3)` energy 1.5.

## Phase Machine (HP-based)

| Phase | HP Range | Color/Behavior |
|---|---|---|
| **Phase 1** | 100-67% (HP > 536) | Default swing + charge (50% prob, 0.6s telegraph) — territorial w/ commit |
| **Phase 2** | 67-34% (HP > 272) | + charge prob bump (70%, 0.5s telegraph) — aggressive |
| **Phase 3** | 34-0% (HP ≤ 272) | + AOE swing (20%) + charge faster (55%, 0.4s telegraph) + speed boost 6.6→7.8 — desperate |

**Phase transitions** (no swarmling summon — cut round 5):
- Phase 1→2: emissive flash (golden→cream HDR pulse 300ms) + audio cue
- Phase 2→3: emissive flash + audio cue + speed boost (move_speed 6.6→7.8)

**Transitions**:
- Phase 1→2: emissive flash + audio cue + spawn 1 swarmling at boss position (single, not on every transition — guarded by `_summon_used: bool`)
- Phase 2→3: emissive flash + audio cue + speed boost (move_speed 4→5)

**Skip-phase scenario** (P1→P3 directly): NOT possible at current numbers (HP 800 / max repeater dmg 5 → max 1 phase per hit). YAGNI per karpathy. Single transition step per damage event, not while-loop.

## Attack Patterns

### Default Melee Swing (Phase 1+)
- Existing pattern from EnemyMelee
- Range 2.5, penalty 25, cooldown 2.5s, windup 0.5s
- Lunge during swing closes gap on player walk-back

### Charge Attack (Phase 2+)
- **Trigger**: cooldown ready + Phase 2 active + player в mid-range (6-12u)
- **Telegraph 2s**: stand still, white emissive flash on body (`Color(2.0, 2.0, 2.0)` via Tween)
- **Dash-time vector**: capture `_charge_dir = (player.global_position - global_position).normalized()` AT DASH START moment (per user lock — реактивный, not telegraph-time)
- **Dash 0.6s** at 12 u/s → 7.2u distance в captured direction
- **Hit**: collision with player during dash → `apply_hit(30)` (higher penalty than swing)
- **Recovery**: 0.5s vulnerable phase (no attacks)
- **Cooldown**: 4s after attack completes

**Why dash-time (not telegraph-time)**: per user lock for harder skill ceiling. Player can't dodge by reading 2s telegraph and stepping away — must commit to dash off frame at right moment.

### AOE Swing (Phase 3+)
- **Trigger**: cooldown ready + Phase 3 active + player close (≤5u)
- **Telegraph 1.5s**: red emissive ground decal (CSGCylinder3D radius 5, height 0.05, position y=0.05) under boss, pulsing emission_energy 0.5↔2.0 sine via Tween
- **Resolve**: instant radial damage check distance ≤ 5u → `apply_hit(25)`
- Decal hidden after resolve
- **Cooldown**: 6s

## Attack Pattern Selection

In `_update_state` decision (`_special_reroll_timer = 1s` to prevent 60Hz starvation):

- **Phase 1**: only default swing
- **Phase 2**: 60% default swing, 40% charge (when charge_cooldown ≤ 0)
- **Phase 3**: 50% default swing, 30% charge, 20% AOE (when AOE cooldown ≤ 0)
- Fallback to default if special unavailable

## Telegraphs

All visual on existing material:
- **Default swing windup**: existing emission flash from EnemyMelee
- **Charge telegraph**: white emissive flash for 2s + stand still
- **AOE telegraph**: ground red decal pulse for 1.5s

No custom shaders. Existing audio `enemy_attack.ogg` reused (or skipped if no fit).

## Kill Polish

On boss death (`die()` override):
- **Visual**: emission flash to bright white (Tween) for 0.5s before `super.die()`
- **Cap restore**: `BOSS_KILL_RESTORE = 50` (2× regular `KILL_RESTORE = 25`) via `apply_kill_restore` dispatched by `_kill_type() == "boss"` check in VelocityGate
- **Cleanup**: kill active tweens (charge telegraph, AOE pulse), hide AOE decal
- **Signal**: `Events.boss_killed` (existing, used by run_loop for cathedral win path)

Boss kill = unique reward fingerprint vs regular enemies.

## Implementation files

- `objects/boss.gd` — phase machine, charge state, AOE state, pattern selection, kill polish
- `objects/boss.tscn` — AOEDecal CSGCylinder3D child + scene setup
- `autoload/velocity_gate.gd` — `BOSS_KILL_RESTORE = 50` const + dispatch in `apply_kill_restore`
- `autoload/events.gd` — `boss_killed`, `boss_phase_started`, `boss_hp_changed(current, max)` signals
- `scripts/run_hud.gd` + `scenes/run_hud.tscn` — boss HP bar UI subscribed to `boss_hp_changed`

## Implementation history

- Phase A — phase machine `4c58489` + cleanups `69caf1a`
- Phase B — charge attack `2722bb6` + cleanup `ade6545`
- Phase C — AOE swing `ff52cb0`
- Phase D — pattern selection + kill polish `922e1b5`
- HP bar + HP×2 + cap tick removal `0c53635 / f73a7d6 / ecc0635`

## Anti-patterns avoided

Per game-designer locked spec:
- ❌ Ranged projectile attack (boss stays melee archetype)
- ❌ Summons in Phase 3 (Phase 2 single-summon only)
- ❌ Reactive AI anticipating player dash (out of scope для current AI complexity)
