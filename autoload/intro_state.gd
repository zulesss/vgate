class_name IntroStateNode extends Node

# M12 intro splash holder. Main menu START sets target_scene before switching to
# intro_splash.tscn; splash reads target_scene на завершении и переключает в неё.
# Между смертью и restart loop'ом splash НЕ показывается (RunLoop.reload_current_scene
# обходит splash). Очищается на старте splash'а — single-use per main-menu START.

var target_scene: String = ""
