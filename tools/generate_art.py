#!/usr/bin/env python3
"""Living Pond V0.9.5.1 – procedural, fully offline Zen pond artwork.
Produces a nonphotographic, pre-baked pool bottom and antialiased living
plant sprites. All static detail is precomputed to protect 2017 Intel iMac.
Requires Pillow and NumPy only to regenerate. Assets are included in ZIP.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, math, random
R = random.Random(4922)
G = np.random.default_rng(4922)
ART = Path(__file__).resolve().parents[1]/'Resources'/'Art'
ART.mkdir(parents=True,exist_ok=True)
W,H=1600,900

def noise(w,h,scale):
    nw=max(4,int(w/scale));nh=max(4,int(h/scale))
    raw=G.integers(0,255,(nh,nw),dtype=np.uint8)
    return np.asarray(Image.fromarray(raw,'L').resize((w,h),Image.Resampling.BICUBIC),dtype=np.float32)/255.0-.5

def smooth_closed(vertices, steps=9):
    result=[]
    n=len(vertices)
    for i in range(n):
        p0,p1,p2,p3=(vertices[(i+k)%n] for k in (-1,0,1,2))
        for j in range(steps):
            t=j/steps;t2=t*t;t3=t2*t
            result.append(tuple(.5*((2*p1[a])+(-p0[a]+p2[a])*t+(2*p0[a]-5*p1[a]+4*p2[a]-p3[a])*t2+(-p0[a]+3*p1[a]-3*p2[a]+p3[a])*t3) for a in range(2)))
    return result

# Deep jade water with broad diffuse translucency, restrained caustics and
# long dark breathing areas to leave Finder files visually legible.
y,x=np.mgrid[0:H,0:W].astype(np.float32)
u=x/W;v=y/H
edge=np.minimum.reduce([u,1-u,v,1-v]);rim=np.clip((.15-edge)/.15,0,1)**1.3
large=noise(W,H,310);medium=noise(W,H,83);fine=noise(W,H,14)
sun=np.exp(-(((u-.38)/.45)**2+((v-.39)/.61)**2))
secondary=np.exp(-(((u-.72)/.30)**2+((v-.22)/.43)**2))
wu=u+.016*np.sin(10*v+4*u)+.009*medium
wv=v+.013*np.cos(9*u-5*v)+.008*large
wave1=np.sin(19*wu+15*wv+np.sin(wv*17)*1.12)
wave2=np.cos(13*wu-18*wv+np.cos(wu*13)*.78)
caustic=np.maximum(0,wave1*wave2-.43)**3*(.38*sun+.16*secondary)
light=.86*sun+.13*secondary
rgb=np.stack([12+18*light+6*large+2.2*medium+38*caustic,
              57+40*light+9*large+3.6*medium+46*caustic,
              55+36*light+10*large+3.8*medium+38*caustic],axis=-1)
rgb*=1-rim[...,None]*.27
# Soft underwater glints with a gentle moving-looking geometry, baked into
# the base map to preserve native frame pacing. The live shader still changes
# their tone over time, while the broad pond centre remains uncluttered.
halo=np.exp(-(((u-.32)/.29)**2+((v-.34)/.35)**2))*0.75+np.exp(-(((u-.74)/.25)**2+((v-.67)/.36)**2))*0.48
filament=np.maximum(0,np.sin(36*wu+17*wv+np.sin(12*wv)*1.6)*np.cos(28*wv-16*wu))**3
rgb+=((filament*halo*13)[...,None])*np.array([.83,1.0,.89],dtype=np.float32)
rgb+=fine[...,None]*1.35
bed=Image.fromarray(np.uint8(np.clip(rgb,0,255)),'RGB').convert('RGBA')

# Rocks: smoothed spline contours, underwater gradients, photographic-style
# moss microvariation, soft exterior shadow. No hard polygon silhouette.
rocks=[]
for j in range(23):
    side=j%4
    if side==0: px=R.uniform(-65,90);py=R.uniform(-35,H+35)
    elif side==1: px=R.uniform(W-93,W+65);py=R.uniform(-35,H+35)
    elif side==2: px=R.uniform(-50,W+50);py=R.uniform(-75,45)
    else: px=R.uniform(-50,W+50);py=R.uniform(H-52,H+70)
    radius=R.uniform(22,77)
    rocks.append((px,py,radius,R.uniform(0,math.tau)))
# Render large rocks first for convincing overlapping banks.
for px,py,rad,rotation in sorted(rocks,key=lambda p:p[2],reverse=True):
    side=int(rad*2.6)
    if side<60:continue
    localX=int(px-rad*1.30);localY=int(py-rad*1.30)
    sw=sh=side
    verts=[]
    count=13
    rvalues=[rad*R.uniform(.81,1.13) for _ in range(count)]
    # Unbroken irregular silhouettes, avoiding V0.9 chunky pixel blocks.
    for i in range(count):
        a=rotation+2*math.pi*i/count
        verts.append((sw/2+math.cos(a)*rvalues[i],sh/2+math.sin(a)*rvalues[i]*.79))
    points=smooth_closed(verts,steps=8)
    mask=Image.new('L',(sw*2,sh*2)); pen=ImageDraw.Draw(mask)
    pen.polygon([(int(xx*2),int(yy*2)) for xx,yy in points],fill=244)
    mask=mask.resize((sw,sh),Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(1.4))
    shadow=Image.new('RGBA',(sw,sh))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(rad*.11)))
    shadowRGB=Image.new('RGBA',(sw,sh),(4,24,22,67))
    shadowRGB.putalpha(shadow.getchannel('A').point(lambda value:int(value*.24)))
    bed.alpha_composite(shadowRGB,(localX+5,localY+7)) if 0<=localX+5 and 0<=localY+7 and localX+sw+5<=W and localY+sh+7<=H else None
    # Pillow alpha_composite with clipping to allow half-visible bank stones.
    yy,xx=np.mgrid[0:sh,0:sw].astype(np.float32)
    dist=((xx-sw*.50)/(rad*1.04))**2+((yy-sh*.50)/(rad*.83))**2
    n1=noise(sw,sh,23);n2=noise(sw,sh,5)
    top=np.clip(.55+(sw*.45-yy)/(rad*3),.12,.92)
    moss=np.clip((n1+.25)*2.1,0,1)*np.clip((1-dist)*1.55,0,1)
    rr=27+32*top+18*moss+12*n2
    gg=59+38*top+27*moss+13*n2
    bb=51+32*top+13*moss+12*n2
    texture=Image.fromarray(np.uint8(np.clip(np.stack([rr,gg,bb],-1),0,255)),'RGB').convert('RGBA')
    texture.putalpha(mask)
    # Paste clipped instead of alpha_composite at negative coordinates.
    if localX>=0 and localY>=0 and localX+sw<=W and localY+sh<=H:
        bed.alpha_composite(texture,(localX,localY))
    else:
        temp=Image.new('RGBA',(W,H))
        temp.paste(texture,(localX,localY))
        bed=Image.alpha_composite(bed,temp)

# Sparse submerged microflora in clusters near edges, not evenly scattered noise.
flora=Image.new('RGBA',(W,H)); d=ImageDraw.Draw(flora,'RGBA')
for i in range(66):
    side=R.randrange(4)
    px=R.uniform(0,117) if side==0 else R.uniform(W-117,W) if side==1 else R.uniform(0,W)
    py=R.uniform(0,H) if side<2 else R.uniform(0,76) if side==2 else R.uniform(H-76,H)
    angle=R.uniform(0,math.tau)
    l=R.uniform(7,19)
    tip=(px+math.cos(angle)*l,py+math.sin(angle)*l)
    d.line((px,py,*tip),fill=(88,125,96,26),width=1)
    for t in (.36,.7):
        cx=px+(tip[0]-px)*t;cy=py+(tip[1]-py)*t
        d.ellipse((cx-2.2,cy-1.0,cx+2.2,cy+1.0),fill=(99,140,100,38))
bed=Image.alpha_composite(bed,flora)

# Shore habitat: fine bent waterweed and submerged moss in irregular groups.
# Pre-baked at authoring time: no new nodes, shaders or per-frame CPU cost.
undergrowth=Image.new('RGBA',(W,H))
brush=ImageDraw.Draw(undergrowth,'RGBA')
clusters=[(92,140,43,1),(1483,170,48,-1),(65,695,52,1),
          (1506,710,48,-1),(277,855,28,-1),(1302,45,37,1),
          (38,440,36,1),(1556,438,30,-1)]
for bx,by,spread,direction in clusters:
    for stem in range(R.randrange(8,16)):
        x0=bx+R.uniform(-spread,spread)
        y0=by+R.uniform(-spread,spread)
        length=R.uniform(8,27)
        angle=R.uniform(-1.25,1.25)+(0.0 if direction==1 else math.pi)
        x1=x0+math.cos(angle)*length
        y1=y0+math.sin(angle)*length
        mid=((x0+x1)/2+R.uniform(-3,3),(y0+y1)/2+R.uniform(-3,3))
        brush.line([(x0,y0),mid,(x1,y1)],fill=(83,122,91,R.randrange(17,35)),width=1)
        for t in (.35,.68):
            cx=x0+(x1-x0)*t;cy=y0+(y1-y0)*t
            a=R.uniform(-.7,.7)
            vx=math.cos(angle+a)*R.uniform(2,6)
            vy=math.sin(angle+a)*R.uniform(2,6)
            brush.ellipse((cx-abs(vx),cy-abs(vy),cx+abs(vx),cy+abs(vy)),fill=(73,128,93,R.randrange(16,37)))
# Sparse microscopic suspended particles: clustered at banks, almost absent in
# center where icons and koi should remain clear.
for _ in range(95):
    bx,by,spread,_=R.choice(clusters)
    sx=bx+R.gauss(0,spread*1.25); sy=by+R.gauss(0,spread*1.25)
    rad=R.uniform(.35,1.1)
    brush.ellipse((sx-rad,sy-rad,sx+rad,sy+rad),fill=(148,185,136,R.randrange(10,36)))
undergrowth=undergrowth.filter(ImageFilter.GaussianBlur(.75))
bed=Image.alpha_composite(bed,undergrowth)
bed.convert('RGB').save(ART/'pond-bed.jpg',quality=91,optimize=True,subsampling=0)

# Four hand-shaped leaf silhouettes: baked depth and tiny droplets, rounded
# notches that remain narrow, irregular radii, no thick radial pie-wedge.
S=384
yy,xx=np.mgrid[:S,:S].astype(np.float32)
for ix in range(6):
    cx=cy=S/2
    dx=xx-cx;dy=(yy-cy)/(0.87+ix*0.028)
    th=np.arctan2(dy,dx)
    dist=np.sqrt(dx*dx+dy*dy)
    k=ix*1.47
    # Six individual leaves: three lobing families, subtly imperfect edges.
    lobe=(5,7,8,6,9,5)[ix]
    radius=(140 + (ix%3)*6)*(1+.032*np.sin(lobe*th+k)+.015*np.sin((lobe+4)*th-k)+.025*np.cos(4*th+1.5*k))
    # notch at +x near stem: tapered and narrow.
    notch=np.exp(-(.5*np.arctan2(np.sin(th),np.cos(th))/.033)**2)
    radius*=1-(0.24+0.025*(ix%3))*notch
    interior=dist<radius
    fade=np.clip((radius-dist)/4.4,0,1)
    top=np.clip(.54+.15*(cy-yy)/150+.11*(cx-xx)/150,0,1)
    veins=np.exp(-(np.mod(th+.13,math.pi/11)-math.pi/22)**2/(.022**2))*.0 # secondary finer strokes added below
    major=np.exp(-(np.mod(th+math.pi/20,math.pi/10)-math.pi/20)**2/(.027**2))
    major*=np.clip(dist/145,0,1)*.67
    nf=noise(S,S,16)+.22*noise(S,S,4)
    fold=.09*np.sin(th*5+k)+.06*np.cos(th*3+k)
    # Distinct warm emerald, sage and blue-green leaves share one palette.
    greens=[0,8,-7,4,13,-5]
    hue=greens[ix]
    rr=29+20*top+7*major+7*nf+7*fold+0.34*hue
    gg=79+42*top+18*major+10*nf+15*fold+hue
    bb=52+25*top+10*major+8*nf+9*fold+0.30*hue
    rgba=np.stack([rr,gg,bb,interior*fade*247],-1)
    img=Image.fromarray(np.uint8(np.clip(rgba,0,255)),'RGBA')
    # Contact shadow behind leaf, small and offset (same texture = no extra SK nodes).
    shad=Image.new('RGBA',(S,S),(7,30,29,0))
    malpha=img.getchannel('A').filter(ImageFilter.GaussianBlur(8)).point(lambda a:int(a*.18))
    shad.putalpha(malpha)
    leaf=Image.alpha_composite(shad,img)
    pen=ImageDraw.Draw(leaf,'RGBA')
    for drop in range(1+ix%4):
        for attempt in range(20):
            bx=R.randrange(87,305);by=R.randrange(78,300)
            if leaf.getpixel((bx,by))[3]>220:break
        r=R.uniform(2.3,5.0)
        pen.ellipse((bx-r,by-r*.80,bx+r,by+r*.80),fill=(194,230,221,50),outline=(231,252,239,100),width=1)
        pen.ellipse((bx-r*.45,by-r*.50,bx-.4,by-.9),fill=(249,255,254,113))
    leaf.save(ART/f'leaf-{ix}.png',optimize=True)

# Irregularly arranged top-view water lilies with concave petals. Each petal
# is a softly shaded gradient in one baked image; zero additional SpriteKit nodes.
FS=320
ly,lx=np.mgrid[0:FS,0:FS].astype(np.float32)
for kind in range(3):
    flower=Image.new('RGBA',(FS,FS))
    center=FS/2
    for ring,(petals,ln,width) in enumerate(((11,116,29),(9,88,26),(7,65,22))):
        for i in range(petals):
            degrees=360*i/petals + (ring*17) + (3 if kind else -4) + R.uniform(-8,8)
            length=ln*R.uniform(.89,1.04)
            w=width*R.uniform(.87,1.04)
            # Broad at midsection, pinched gracefully near the blossom core.
            outline=[]
            for j in range(40):
                t=j/39
                # rounded outer point at t=1 and shoulder near t=.67
                wr=w*max(.02,math.sin(math.pi*t)**.61)*(0.82+0.2*t)
                y=center+13-length*t
                shift=3*math.sin(math.pi*t)
                outline.append((center-wr+shift,y))
            for j in range(39,-1,-1):
                t=j/39
                wr=w*max(.02,math.sin(math.pi*t)**.61)*(0.82+0.2*t)
                y=center+13-length*t
                shift=3*math.sin(math.pi*t)
                outline.append((center+wr+shift,y))
            mask=Image.new('L',(FS,FS));pd=ImageDraw.Draw(mask)
            pd.polygon(outline,fill=242)
            mask=mask.filter(ImageFilter.GaussianBlur(.65))
            # Pigment concentrated at petal tip; creamy translucent bases.
            lengthT=np.clip((center+13-ly)/length,0,1)
            xT=np.abs(lx-(center+3*np.sin(np.pi*lengthT)))/max(1,w)
            blush=np.clip((lengthT-.52)/.48,0,1)**1.3
            blush*=.6+.4*(1-np.clip(xT,0,1))
            rootTone=(1-lengthT)*.06
            pink=(0.28,0.72,0.12)[kind]
            rr=255-10*blush-7*rootTone
            gg=245 - (35+29*pink)*blush - 8*rootTone
            bb=231 - (25+30*pink)*blush - 12*rootTone
            # center ridge / gently shadowed edges follow the petal curve
            ridge=np.exp(-(xT/.18)**2)
            rr+=1.8*ridge;gg+=6*ridge;bb+=5*ridge
            rgba=np.stack([rr,gg,bb,np.asarray(mask,dtype=np.float32)],-1)
            pet=Image.fromarray(np.uint8(np.clip(rgba,0,255)),'RGBA')
            pet=pet.rotate(degrees,resample=Image.Resampling.BICUBIC,center=(center,center))
            flower=Image.alpha_composite(flower,pet)
    pd=ImageDraw.Draw(flower,'RGBA')
    pd.ellipse((center-19,center-19,center+19,center+19),fill=(225,192,104,250))
    pd.ellipse((center-11,center-11,center+11,center+11),fill=(252,227,154,250))
    for _ in range(35):
        a=R.random()*math.tau;rad=R.random()*14
        cx=center+math.cos(a)*rad;cy=center+math.sin(a)*rad
        pd.ellipse((cx-.85,cy-.85,cx+.85,cy+.85),fill=(170,128,57,167))
    flower.save(ART/f'lotus-{kind}.png',optimize=True)
print('V0.9.5.1 procedural artwork generated:',*[x.name for x in sorted(ART.iterdir())])
