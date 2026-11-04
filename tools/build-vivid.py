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

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme', ROOT/'tools/build-theme.py')
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
COLORS = {'red':'#CC3000', 'green':'#247C1A', 'blue':'#204FC8', 'flower':'#B65EBB'}


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


def mark(suit,x,y,scale=1):
    shapes={'red':'<path d="M0-16L16 0 0 16-16 0Z"/>',
            'green':'<path d="M0-17L17 14H-17Z"/>',
            'blue':'<circle r="15"/>',
            'flower':'<path d="M0-18L5-5 18 0 5 5 0 18-5 5-18 0-5-5Z"/>'}
    return f'<g transform="translate({x} {y}) scale({scale})" fill="{COLORS[suit]}">{shapes[suit]}</g>'


def indices(value,suit,dragon=False):
    c=COLORS[suit]
    body=f'<rect x="7" y="7" width="56" height="56" rx="5" fill="{c if dragon else "white"}" stroke="{c}" stroke-width="2"/>'
    body+=f'<text x="35" y="50" text-anchor="middle" fill="{"white" if dragon else c}" font-family="Arial" font-weight="bold" font-size="43">{value}</text>'
    body+=mark(suit,145,35)
    body+=f'<text x="166" y="281" text-anchor="end" fill="{c}" font-family="Arial" font-weight="bold" font-size="27">{value}</text>'
    return body


def main():
    for suit in ['red','green','blue']:
        for value in range(2,11):
            asset(f'assets/vivid/cards/{value}_{suit}.png',base(suit)+portrait(suit)+indices(value,suit))
        asset(f'assets/vivid/cards/d_{suit}.png',base(suit,True)+portrait(suit)+indices('D',suit,True))
    asset('assets/vivid/cards/f_flower.png',base('flower')+portrait('flower')+indices('F','flower'))
    # Original back, dragon buttons and felt; generated variants remain only
    # as historical assets, not active atlas references.
    p=ROOT/'main/main.atlas'
    s=p.read_text().replace('/assets/vivid/cards/back.png','/assets/cards/back.png')
    s=s.replace('/assets/vivid/buttons/','/assets/buttons/')
    p.write_text(s)
    p=ROOT/'main/Scripts/xf.atlas'
    p.write_text(p.read_text().replace('/assets/vivid/table.png','/assets/background/table.jpg'))
    print('Built 31 readable faces from original artwork; restored original back, buttons, felt')


if __name__=='__main__': main()
