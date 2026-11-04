#!/usr/bin/env python3
"""Vivid animal deck. image_gen portraits + deterministic readable SVG indices.

Run after tools/build-theme.py --theme vivid. Requires rsvg-convert.
"""
import base64
import importlib.util
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme', ROOT/'tools/build-theme.py')
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
COLORS = {'red':'#CE3919', 'green':'#087546', 'blue':'#185BC4'}
BRIGHT = {'red':'#FF8935', 'green':'#29E799', 'blue':'#35BBFF'}
ANIMALS = {'red':'tiger','green':'panda','blue':'owl'}

def asset(path,w,h,body):
    t.svg_asset(path,w,h,body)
    if '/cards/' in path or '/buttons/' in path:
        (ROOT/path).with_suffix('.svg').unlink()

def portrait(suit,x,y,size):
    data = base64.b64encode((ROOT/f'assets/vivid/emblems/{ANIMALS[suit]}.png').read_bytes()).decode()
    return f'<image x="{x}" y="{y}" width="{size}" height="{size}" href="data:image/png;base64,{data}"/>'

def mark(suit,x,y,scale=1,color=None):
    shapes = {'red':'<path d="M0-17L17 0 0 17-17 0Z"/>',
              'green':'<path d="M0-17L17 14H-17Z"/>',
              'blue':'<circle r="15"/>'}
    return f'<g transform="translate({x} {y}) scale({scale})" fill="{color or COLORS[suit]}">{shapes[suit]}</g>'

def crown(x,y,scale=1):
    return f'<g transform="translate({x} {y}) scale({scale})"><path d="M-22 12L-28-12L-12-3L0-22L12-3L28-12L22 12Z" fill="#FFD23E" stroke="#5A3511" stroke-width="3"/><path d="M-20 19H20" stroke="#5A3511" stroke-width="4"/></g>'

def frame(suit, special=False):
    return (f'<rect x="2" y="2" width="176" height="296" rx="10" fill="#FFFEF8" stroke="{COLORS[suit]}" stroke-width="3"/>'
        + (f'<rect x="6" y="6" width="168" height="61" rx="6" fill="{COLORS[suit]}"/>' if special else '')
        +f'<path d="M10 70H170" stroke="{BRIGHT[suit]}" stroke-width="2" opacity=".7"/>')

def indices(value,suit,special=False):
    color='#FFFFFF' if special else COLORS[suit]
    return (f'<text x="12" y="54" fill="{color}" font-family="Arial" font-weight="bold" font-size="48">{value}</text>'
            + (crown(142,35,.66) if special else mark(suit,145,34))
            + f'<text x="165" y="281" text-anchor="end" fill="{COLORS[suit]}" font-family="Arial" font-weight="bold" font-size="27">{value}</text>'
            + mark(suit,22,272,.45))

def main():
    for suit in COLORS:
        for value in range(2,11):
            # Upper 35 game pixels hold only the value + suit, never cropped art.
            body=frame(suit)+indices(value,suit)+portrait(suit,13,92,154)
            asset(f'assets/vivid/cards/{value}_{suit}.png',180,300,body)
        body=frame(suit,True)+indices('D',suit,True)
        body+=f'<path d="M18 105Q90 70 162 105V204Q148 241 90 258Q32 241 18 204Z" fill="{BRIGHT[suit]}" opacity=".22"/>'
        body+=portrait(suit,13,100,154)+crown(90,96,.75)
        asset(f'assets/vivid/cards/d_{suit}.png',180,300,body)
        for disabled in [False,True]:
            name=f'button_{suit}'+('_grey' if disabled else '')
            body=f'<circle cx="48" cy="48" r="45" fill="{COLORS[suit] if not disabled else "#23574E"}" stroke="{BRIGHT[suit] if not disabled else "#7F9C91"}" stroke-width="3"/>'
            body+=f'<g opacity="{.3 if disabled else 1}">'+portrait(suit,10,12,76)+crown(48,16,.35)+'</g>'
            asset(f'assets/vivid/buttons/{name}.png',96,96,body)
    asset('assets/vivid/buttons/button_grey.png',96,96,'<circle cx="48" cy="48" r="44" fill="#23574E" stroke="#9BB8A9" stroke-width="3"/>'+crown(48,48,.7))
    flower='<g transform="translate(90 169)">'
    for a in range(0,360,45):
        flower+=f'<ellipse transform="rotate({a})" cx="0" cy="-29" rx="20" ry="34" fill="#FF579D" stroke="#B72970" stroke-width="3"/>'
    flower+='<circle r="23" fill="#FFE15B" stroke="#BF7415" stroke-width="3"/></g>'
    asset('assets/vivid/cards/f_flower.png',180,300,frame('red')+'<text x="12" y="54" fill="#B72970" font-family="Arial" font-weight="bold" font-size="48">F</text><path d="M145 16L150 29 164 34 150 39 145 52 140 39 126 34 140 29Z" fill="#EA4088"/>'+flower)
    asset('assets/vivid/cards/back.png',180,300,'<rect x="2" y="2" width="176" height="296" rx="10" fill="#087C61" stroke="#FFD23E" stroke-width="3"/><rect x="11" y="11" width="158" height="278" rx="5" fill="none" stroke="#39EBB1" stroke-width="2"/>'+crown(90,150,2))
    asset('assets/vivid/table.png',960,540,'<defs><radialGradient id="felt"><stop stop-color="#157856"/><stop offset="1" stop-color="#064839"/></radialGradient></defs><rect width="960" height="540" fill="url(#felt)"/><path d="M854 18V522" stroke="#66E4AE" stroke-opacity=".25"/>')
    p=ROOT/'main/main.atlas'
    s=p.read_text()
    s=re.sub(r'/assets/(?:jade|vivid)/cards/', '/assets/vivid/cards/',s)
    s=re.sub(r'/assets/(?:jade|vivid)/buttons/', '/assets/vivid/buttons/',s)
    p.write_text(s)
    p=ROOT/'main/Scripts/xf.atlas'
    p.write_text(re.sub(r'/assets/(?:jade|vivid)/table.png','/assets/vivid/table.png',p.read_text()))
    print('Built Vivid: 32 cards, 7 buttons, table; 35px index strip')

if __name__=='__main__': main()
