Knights on Roids - hurtbox + inherited enemy scenes
Drop the contents of "Knights on Roids/" on top of your project folder (close Godot first, or let it reload).

DELETE these four files (replaced by enemy.gd):
  orc.gd, orc.gd.uid, armored_orc.gd, armored_orc.gd.uid

NOT included (you do this in the editor, 10 seconds):
  game.tscn -> select the "Game" root node -> Attach Script -> pick your existing res://game.gd

Changed:  project.godot (2 layer names), entity.tscn (now the shared enemy base), orc.tscn + armored_orc.tscn
          (now inherited scenes), enemy.gd (was orc.gd), knight.gd, Knight.tscn, aarow.gd, aarow.tscn
