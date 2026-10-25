#!/bin/sh
# usage: runsweep.sh <project> runs=12 key=value ...  -> compact run-simulation table
G=/home/claude/godot/Godot_v4.7-stable_linux.x86_64
P="$1"; shift
cd "$P" && timeout 1700 $G --headless --fixed-fps 60 --path . -s res://run_sim.gd -- "$@" 2>&1 | grep -E "SCRIPT|Parse|^overrides|^bot|^masher|^turtle|^parry|^dodge"
