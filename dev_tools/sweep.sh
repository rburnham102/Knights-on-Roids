#!/bin/sh
# usage: sweep.sh <project> trials=10 key=value ...   -> compact matrix: wins/hp per scenario
G=/home/claude/godot/Godot_v4.7-stable_linux.x86_64
P="$1"; shift
cd "$P" && timeout 1500 $G --headless --fixed-fps 60 --path . -s res://sim.gd -- "$@" 2>&1 | python3 -c "
import sys,re
rows={}
order=[]
for line in sys.stdin:
    m=re.match(r'^(masher|turtle|parry \d+ms|dodge \d+ms|parry|dodge)\s+(1 orc|2 orcs|armored|orc\+armored|archer|orc\+archer|armored\+archer)\s+(\d+)/(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)',line)
    if not m: continue
    b,sc,w,n,hp,sec,par=m.groups()
    if b not in rows: rows[b]={}; order.append(b)
    rows[b][sc]=(int(w),int(n),int(hp),float(sec),float(par))
SC=['1 orc','2 orcs','armored','orc+armored','archer','orc+archer','armored+archer']
print('%-12s | '%'bot (wins:hp)'+' | '.join('%-13s'%x for x in SC))
for b in order:
    cells=[]
    for sc in SC:
        w,n,hp,sec,par=rows[b].get(sc,(0,1,0,0,0))
        cells.append('%2d/%-2d hp%3d %4.0fs'%(w,n,hp,sec))
    print('%-12s | %s'%(b,' | '.join(cells)))
"
