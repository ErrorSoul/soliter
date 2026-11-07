#!/usr/bin/env python3
"""Lay out the owner's original art with readable, boxed card indices.

Run after tools/build-theme.py --theme vivid. Requires rsvg-convert + Arial Bold.
Original PNGs are embedded unchanged; SVG viewports place their art and frame.
No illustration is generated or repainted. The rendered deck is a sibling asset.
"""
import base64
import importlib.util
from pathlib import Path
import re
import math

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme', ROOT/'tools/build-theme.py')
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
# Eyedropper samples from the original portraits (source pixel coordinates).
# Colors are copied without adjustment; dragon badges use medium-tone colors from their bodies.
COLORS = {'red':'#C33527', 'green':'#417D20', 'blue':'#0065F0', 'flower':'#B65EBB'}
COLOR_SAMPLES = {'red': (118,192), 'green': (226,130), 'blue': (147,152)}
DRAGON_COLORS = {'red': '#BC1E2E', 'green': '#169242', 'blue': '#24669E'}
DRAGON_COLOR_SAMPLES = {'red': (143, 160), 'green': (202, 132), 'blue': (142, 187)}


def asset(path, body):
    t.svg_asset(path,180,300,body)
    # The checked-in original PNG and this layout are the sources.
    (ROOT/path).with_suffix('.svg').unlink()


def source(suit, dragon=False):
    if suit == 'flower': return 'assets/cards/f_flower.png'
    return f'assets/cards/d_{suit}.png' if dragon else f'assets/cards/{suit}_cards/7_{suit}.png'


def base(suit, dragon=False):
    path=source(suit,dragon)
    w,h=(300,480) if suit=='flower' else (320,446)
    data=base64.b64encode((ROOT/path).read_bytes()).decode()
    # Keep the exact outer frame. Cover only the old face/indices, then place
    # its original illustration in a separate viewport beneath the index strip.
    return (f'<defs><image id="original" width="{w}" height="{h}" href="data:image/png;base64,{data}"/><clipPath id="art-only"><path d="M52 0H{w}V{h}H0V50H52Z"/></clipPath></defs>'
            f'<use href="#original" transform="scale({180/w} {300/h})"/>'
            '<rect x="3" y="3" width="174" height="294" rx="6" fill="white"/>')


def portrait(suit):
    view='24 45 252 280' if suit=='flower' else '24 43 272 230'
    # The source crop excludes the old indices and keeps all decorative leaves.
    return f'<svg x="14" y="93" width="152" height="157" viewBox="{view}" preserveAspectRatio="xMidYMid meet"><use href="#original" clip-path="url(#art-only)"/></svg>'


def mark(suit,x,y,scale=1,color=None):
    shapes={'red':'<path d="M0-16L16 0 0 16-16 0Z"/>',
            'green':'<path d="M0-17L17 14H-17Z"/>',
            'blue':'<circle r="15"/>',
            'flower':'<path d="M0-18L5-5 18 0 5 5 0 18-5 5-18 0-5-5Z"/>'}
    return f'<g transform="translate({x} {y}) scale({scale})" fill="{color or COLORS[suit]}">{shapes[suit]}</g>'


def indices(value,suit,compact=False):
    c=(DRAGON_COLORS if value == 'D' else COLORS)[suit]
    size, y, fs, baseline = (34, 1, 26, 28) if compact else (56, 7, 43, 50)
    body=f'<rect x="7" y="{y}" width="{size}" height="{size}" rx="5" fill="{c}" stroke="{c}" stroke-width="2"/>'
    body+=f'<text x="{7+size/2}" y="{baseline}" text-anchor="middle" fill="white" font-family="Arial" font-weight="bold" font-size="{fs}">{value}</text>'
    body+=mark(suit,145,18 if compact else 35,0.75 if compact else 1,c)
    body+=f'<text x="166" y="281" text-anchor="end" fill="{c}" font-family="Arial" font-weight="bold" font-size="27">{value}</text>'
    return body


def dragon_frame(suit, frame):
    # Only the illustration moves. Original frame and rank stay pixel-identical.
    phase=(frame-1)/17
    wave=math.sin(phase*math.pi*2)
    tilt=3.5*wave
    scale=1+0.025*math.sin(phase*math.pi)**2
    head=f'<g transform="translate(90 180) rotate({tilt}) scale({scale}) translate(-90 -180)">'+portrait(suit)+'</g>'
    color={'red':'#FFA449','green':'#7FDB9C','blue':'#8CCEF0'}[suit]
    # A short, restrained exhale from the snout; never reaches the rank strip.
    puff=''
    if .22 < phase < .85:
        q=(phase-.22)/.63
        opacity=.5*math.sin(q*math.pi)
        for j in range(3):
            x=114+q*27+j*5
            y=199+q*17-j*5
            puff+=f'<circle cx="{x}" cy="{y}" r="{3+q*5}" fill="{color}" opacity="{opacity*(1-j*.2)}"/>'
    return base(suit,True)+head+puff+indices('D',suit)


def animal_frame(suit, frame):
    phase=(frame-1)/17
    # Owl looks sideways, fox tilts, orc breathes. Frames begin/end at rest.
    tilt={'red':4.0,'green':1.8,'blue':-5.0}[suit]*math.sin(phase*math.tau)
    stretch=1+{'red':.018,'green':.035,'blue':.012}[suit]*math.sin(phase*math.pi)**2
    data=base(suit).split('</defs>')[0]+'</defs>'
    return data+f'<g transform="translate(90 180) rotate({tilt}) scale(1 {stretch}) translate(-90 -180)">'+portrait(suit)+'</g>'


def main():
    faces = []
    for suit in ['red','green','blue']:
        faces += [(str(v),suit,False) for v in range(2,11)]
        faces.append(('d',suit,True))
    faces.append(('f','flower',False))
    for value,suit,dragon in faces:
        for compact in [False,True]:
            name=f'{value}_{suit}' + ('_compact' if compact else '')
            asset(f'assets/vivid/cards/{name}.png',base(suit,dragon)+portrait(suit)+indices(value.upper(),suit,compact))
    # Shared transparent animal frames avoid duplicating 18 frames for every rank.
    blank_names=[]
    for suit in ['red','green','blue']:
        for value in range(2,11):
            name=f'{value}_{suit}_empty'
            blank_names.append(name)
            asset(f'assets/vivid/cards/{name}.png',base(suit)+indices(str(value),suit))
    motion_names=[]
    for suit in ['red','green','blue']:
        for frame in range(1,19):
            name=f'animal_{suit}_motion_{frame}'
            motion_names.append(name)
            asset(f'assets/vivid/motion/{name}.png',animal_frame(suit,frame))
    for suit in ['red','green','blue']:
        for frame in range(1,19):
            name=f'd_{suit}_motion_{frame}'
            motion_names.append(name)
            asset(f'assets/vivid/motion/{name}.png',dragon_frame(suit,frame))
    # Original three-head tableau symbol and dashed frame, with stronger opacity.
    slot_data=base64.b64encode((ROOT/'assets/cards/slot_tableau.png').read_bytes()).decode()
    t.svg_asset('assets/vivid/slots/slot_tableau.png',180,300,
        '<defs><filter id="readable"><feComponentTransfer><feFuncA type="linear" slope="2.2"/></feComponentTransfer></filter></defs>'
        f'<image width="180" height="300" preserveAspectRatio="none" filter="url(#readable)" href="data:image/png;base64,{slot_data}"/>')
    # Original back, dragon buttons and felt; generated variants remain only
    # as historical assets, not active atlas references.
    p=ROOT/'main/main.atlas'
    s=p.read_text().replace('/assets/vivid/cards/back.png','/assets/cards/back.png')
    s=s.replace('/assets/vivid/buttons/','/assets/buttons/')
    s=s.replace('/assets/ui/slots/slot_tableau.png','/assets/vivid/slots/slot_tableau.png')
    s=s.replace('/assets/cards/slot_tableau.png','/assets/vivid/slots/slot_tableau.png')
    s=re.sub(r'images \{\s*image: "/assets/vivid/motion/[^"\n]+.png"\s*\}\n', '', s)
    s += ''.join(f'images {{\n image: "/assets/vivid/motion/{name}.png"\n}}\n' for name in motion_names)
    s=re.sub(r'images \{\s*image: "/assets/vivid/cards/[^"\n]+_compact.png"\s*\}\n', '', s)
    s += ''.join(f'images {{\n image: "/assets/vivid/cards/{v}_{s}_compact.png"\n}}\n' for v,s,d in faces)
    s=re.sub(r'images \{\s*image: "/assets/vivid/cards/[^"\n]+_empty.png"\s*\}\n', '', s)
    s += ''.join(f'images {{\n image: "/assets/vivid/cards/{name}.png"\n}}\n' for name in blank_names)
    p.write_text(s)
    p=ROOT/'main/Scripts/xf.atlas'
    p.write_text(p.read_text().replace('/assets/vivid/table.png','/assets/background/table.jpg'))
    print('Built 62 faces, 27 empty faces, 108 shared motion frames, original tableau symbol; original back/buttons/felt')


if __name__=='__main__': main()
