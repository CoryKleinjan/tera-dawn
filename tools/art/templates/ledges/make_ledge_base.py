"""Draw the guide for a zone's ledge sheet: one heavy floating shelf (2400x1600, 3:2) in a
flat fill with a dark outline, on #FF00FF. Its underside repeats every 680 px from x 520, so
the cuts at 520, 1200 and 1880 give a left cap, two middles and a right cap that join.

    python3 tools/art/templates/ledges/make_ledge_base.py <name> <r> <g> <b> [out_dir] [depth]

Writes <out_dir>/<name>_ledge_base.png (the fill is the zone's ground colour, measured).
`depth` is the middle's depth below the flat top (default 400); the ends and swells scale with it."""
import math, sys
from PIL import Image, ImageDraw
name=sys.argv[1]; FILL=tuple(int(v) for v in sys.argv[2:5]); OUT=sys.argv[5] if len(sys.argv)>5 else '.'
W,H=2400,1600; MAG=(255,0,255); LINE=(40,28,30)
MID=float(sys.argv[6]) if len(sys.argv)>6 else 400.0
K=MID/400.0; TOP=420; TIP=150*K; R=int(min(48, TIP // 3))
def depth(x):
    u=x-520
    return MID+K*(34*math.sin(2*math.pi*u/680)+20*math.sin(2*math.pi*u/340+1.0)+10*math.sin(2*math.pi*u/(680/3)+2.3))
def smooth(t): t=max(0,min(1,t)); return t*t*(3-2*t)
def end_arc(cx, sign, down):
    pts=[(cx - sign*R*math.cos(math.pi/2*i/20), TOP+16+(TIP-16)*math.sin(math.pi/2*i/20)) for i in range(21)]
    return pts if down else pts[::-1]
x0,x1=60,2340
pts=[(x0+16,TOP),(x1-16,TOP),(x1-4,TOP+4),(x1,TOP+16)]
pts+=end_arc(x1-R,-1,True)
for x in range(x1-R, x0+R-1, -4):
    dd=depth(x)
    if x<520: dd=TIP+(dd-TIP)*smooth((x-x0-R)/(520-x0-R))
    if x>1880: dd=TIP+(dd-TIP)*smooth((x1-R-x)/(x1-R-1880))
    pts.append((x, TOP+dd))
pts+=end_arc(x0+R,1,False)+[(x0+4,TOP+4)]
im=Image.new('RGB',(W,H),MAG); d=ImageDraw.Draw(im)
d.polygon(pts, fill=FILL)
d.line(pts+[pts[0]], fill=LINE, width=10, joint='curve')
# fill pinholes: magenta pixels not reachable from the sheet's corner become outline
probe=im.copy(); ImageDraw.floodfill(probe,(0,0),(0,255,0))
import numpy as np
a=np.array(im); holes=(np.array(probe)==np.array(MAG)).all(-1); a[holes]=LINE; im=Image.fromarray(a)
im.save(f'{OUT}/{name}_ledge_base.png')
