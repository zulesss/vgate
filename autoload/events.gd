class_name EventsBus extends Node

# Signal bus для VelocityGate hook'а. Один canonical источник правды для коммуникации
# между Player, EnemyBase подклассами, VelocityGate, RunLoop, DeathScreen, DebugHud,
# ScoreState, SpawnController.

signal player_hit(penalty: int)                                              # враг попал по игроку, penalty = списанный cap
signal enemy_killed(restore: int, position: Vector3, type: String)           # враг убит — restore к cap, тип ("melee"/"shooter") для score/spawn counter'ов
signal dash_started()                                                         # игрок стартанул dash
signal drain_started()                                                        # speed_ratio < threshold > tolerance → drain активен
signal drain_stopped()                                                        # игрок снова движется или убил → drain отменён
signal player_died()                                                          # cap дошёл до 0 в drain → death

# M4 lifecycle bus
signal run_started()                                                          # VelocityGate.reset_for_run() закончил → spawn/score self-reset listeners
signal run_restart_requested()                                                # Death-screen Restart pressed → run_loop в main reset'ит state
signal enemy_spawned(enemy: Node)                                             # spawn_controller инстанцировал нового врага (для analytics/HUD)
signal score_changed(new_score: int)                                          # current_score обновился (kill applied)
signal high_score_loaded(score: int)                                          # ConfigFile прочитан, best_score готов к показу

# M7 Kill Chain (docs/feel/M7_polish_spec.md §Эффект 3). Tier 1=3 kills, 2=5 в окне 3с.
# Emit'ится KillChain autoload'ом каждый kill в chain — listeners (player camera/FOV, sfx pitch,
# KillChainFlash overlay) применяют additive feel поверх kill burst'а.
# Tier 7+ (3) больше НЕ emit'ит kill_chain_triggered — заменён на sustained streak semantics
# ниже (kill_chain_streak_entered / kill_chain_streak_exited) после плейтеста: per-kill jolts
# на 7+ были «дёрганые», sustained state читается чище.
signal kill_chain_triggered(tier: int, hit_pos: Vector3)

# M7 Kill Chain Streak (Tier 7+ sustained). Entered эмитится один раз когда counter впервые
# ≥7; пока стрик активен (каждый kill в окне 3с подтверждает) — sustained higher FOV +
# cap ceiling boost. Exited эмитится при window timeout / death / run_started.
signal kill_chain_streak_entered(hit_pos: Vector3)
signal kill_chain_streak_exited()
