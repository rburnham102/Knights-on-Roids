Knights on Roids - healer companion
Built on commit 5d17069 ("healer animations").

INSTALL
1. Close Godot.
2. Unzip into your project folder, overwriting when asked.
3. Open the project. Godot imports the new files and registers Healer and
   HolyBurst. Nothing else to set up.

NEW FILES
  healer.gd                    her state machine (follow / heal / burst / hurt / dead)
  upgrades/healer.tres         the "Hire a Healer" upgrade card
  effects/holy_burst.gd/.tscn  her defensive burst (Area2D + fire animation)
  effects/heal_effect.tscn     green crosses played on the knight
  effects/one_shot_effect.gd   plays an animation once, then frees itself
  dev_tools/healer_tests.gd    32 tests

CHANGED FILES
  healer.tscn          script attached, root renamed "Healer", collision layer
                       0, "attack" animation no longer loops, HealthBar added
  run_manager.gd       hires her, carries her between rooms, peels enemies
                       onto her, drops the perk when she dies
  enemy.gd             joins "enemies"; swings hurt the "allies" group
  knight.gd            joins "allies"
  dev_tools/run_sim.gd healer=1 option

RUN THE TOOLS
  godot --headless --fixed-fps 60 --path . -s res://dev_tools/healer_tests.gd
  godot --headless --fixed-fps 60 --path . -s res://dev_tools/run_sim.gd -- runs=12 healer=1
