"""Regenerates every AttackData .tres from one table. Usage: gen_attacks.py <project_dir> <tuning.json>"""
import json, sys, os
proj, tuning = sys.argv[1], json.load(open(sys.argv[2]))
AD_UID = open(os.path.join(proj, "attack_data.gd.uid")).read().strip()
os.makedirs(os.path.join(proj, "attacks", "enemy"), exist_ok=True)
def col(c): return "Color(%s, %s, %s, 1)" % tuple(c)
for rel, a in tuning.items():
    lines = [
        f'[gd_resource type="Resource" script_class="AttackData" format=3 uid="{a["uid"]}"]', "",
        f'[ext_resource type="Script" uid="{AD_UID}" path="res://attack_data.gd" id="1_attack_data"]', "",
        "[resource]", 'script = ExtResource("1_attack_data")',
        f'anim = &"{a["anim"]}"', f'type = {a.get("type", 0)}', f'damage = {a["damage"]}',
        f'hit_frame = {a["hit_frame"]}', f'knockback = {float(a["knockback"])}',
        f'shake = {float(a.get("shake", 0.0))}', f'lunge = {float(a.get("lunge", 0.0))}',
        f'windup_time = {float(a.get("windup_time", 0.0))}', f'active_frames = {a.get("active_frames", 0)}',
        f'poise_damage = {float(a.get("poise_damage", 0.0))}', f'hit_stop = {float(a.get("hit_stop", 0.0))}',
    ]
    for k in ("parryable", "guard_break"):
        if k in a: lines.append(f'{k} = {"true" if a[k] else "false"}')
    for k in ("hitbox_radius", "hitbox_offset", "anim_speed", "projectile_speed"):
        if k in a: lines.append(f'{k} = {float(a[k])}')
    if "color" in a: lines.append(f'telegraph_color = {col(a["color"])}')
    open(os.path.join(proj, rel), "w").write("\n".join(lines) + "\n")
print("wrote", len(tuning), "attack files")
