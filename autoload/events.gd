class_name EventsBus extends Node

# Signal bus для VelocityGate hook'а. Один canonical источник правды для коммуникации
# между Player, EnemyDummy, VelocityGate, RunManager, DebugHud.

signal player_hit(penalty: int)                          # враг попал по игроку, penalty = списанный cap
signal enemy_killed(restore: int, position: Vector3)     # враг убит, +N к cap
signal dash_started()                                    # игрок стартанул dash
signal drain_started()                                   # speed_ratio < threshold > tolerance → drain активен
signal drain_stopped()                                   # игрок снова движется или убил → drain отменён
signal player_died()                                     # cap дошёл до 0 в drain → death
signal run_restarted()                                   # после restart loop арена reset
