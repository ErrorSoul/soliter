#!/usr/bin/env python3
"""Rebuild the Jade deck from vector layouts and checked-in image_gen emblems.

Requires rsvg-convert and the Arial Bold font. Card numbers are typeset, never
generated. Run from the repository: python3 tools/build-jade.py.
"""
import base64
import importlib.util
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_theme', ROOT / 'tools/build-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)
def asset(path, width, height, body):
    theme.svg_asset(path, width, height, body)
    # Layout source is this script. Avoid storing duplicated base64 emblems in
    # generated SVGs; the original PNG emblems are checked in separately.
    if '/cards/' in path or '/buttons/' in path:
        (ROOT / path).with_suffix('.svg').unlink()
COLORS = {'red': '#9E3329', 'green': '#17634D', 'blue': '#284D82'}


def symbol(suit, x=0, y=0, scale=1, color=None):
    color = color or COLORS[suit]
    if suit == 'red':
        paths = '<circle r="13"/>'
        for n in range(12):
            paths += f'<path transform="rotate({n*30})" d="M-3-18Q-6-23 0-29Q1-23 4-19Z"/>'
    elif suit == 'green':
        paths = '<path d="M0 25C-20 9-29-5-26-23C-5-19 4-3 0 25M4 18C0-8 13-24 31-28C29-5 19 7 4 18"/>'
        paths += '<path d="M-16-11L1 24L20-13" fill="none" stroke="#F5EFDF" stroke-width="2"/>'
    else:
        paths = '<path d="M-30 13Q-36-7-17-11Q-15-33 6-26Q16-25 18-12Q36-10 31 8Q27 18 13 16H-25Z"/>'
        paths += '<path d="M-11 7Q11 14 12-3Q9-14 0-7Q-6 2 4 3M-33 25Q-15 16 0 22T33 21" fill="none" stroke="#F5EFDF" stroke-width="3" stroke-linecap="round"/>'
    return f'<g transform="translate({x} {y}) scale({scale})" fill="{color}">{paths}</g>'


def lotus(x=90, y=150, scale=1):
    return f'''<g transform="translate({x} {y}) scale({scale})">
    <path d="M0 37C-39 42-50 22-49 13C-25 10-10 18 0 37M0 37C39 42 50 22 49 13C25 10 10 18 0 37" fill="#17634D"/>
    <path d="M0 22C-45 21-55-7-48-28C-20-27-8-3 0 22M0 22C45 21 55-7 48-28C20-27 8-3 0 22" fill="#B35D79"/>
    <path d="M0 22C-25-4-26-31 0-59C26-31 25-4 0 22" fill="#CE8097"/>
    <path d="M0 25C-34 24-45 9-39-9C-18-13-5 6 0 25M0 25C34 24 45 9 39-9C18-13 5 6 0 25" fill="#D990A3"/>
    <path d="M-11 21Q0 6 11 21Q0 30-11 21" fill="#C5A269"/>
    </g>'''


def emblem(suit, x, y, w, h):
    data = base64.b64encode((ROOT / f'assets/jade/emblems/dragon_{suit}.png').read_bytes()).decode()
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:image/png;base64,{data}"/>'


def frame():
    return '''<defs><linearGradient id="paper" x2=".25" y2="1"><stop stop-color="#FBF6E9"/><stop offset="1" stop-color="#EFE5CD"/></linearGradient></defs>
    <rect x="1.5" y="1.5" width="177" height="297" rx="9" fill="url(#paper)" stroke="#B9AA87" stroke-width="2"/>
    <path d="M8 17V9H19M161 291H172V280" fill="none" stroke="#BA9854" stroke-width="2"/>'''


def index(value, suit):
    color = COLORS.get(suit, '#A34A6C')
    return (f'<g fill="{color}" font-family="Arial" font-weight="bold">'
            f'<text x="12" y="56" font-size="48">{value}</text>'
            f'<text x="165" y="279" font-size="27" text-anchor="end">{value}</text></g>')


def main():
    for suit in COLORS:
        for value in range(2, 11):
            body = frame() + index(value, suit) + symbol(suit, 139, 37, .58) + symbol(suit, 90, 156, 1.9)
            asset(f'assets/jade/cards/{value}_{suit}.png', 180, 300, body)
        body = frame() + index('D', suit) + symbol(suit,139,37,.58) + emblem(suit,5,77,170,166)
        asset(f'assets/jade/cards/d_{suit}.png', 180, 300, body)
    asset('assets/jade/cards/f_flower.png',180,300,frame()+index('F','flower')+lotus(141,38,.27)+lotus(90,166,1.35))
    asset('assets/jade/cards/back.png',180,300,
          '<rect x="1.5" y="1.5" width="177" height="297" rx="9" fill="#164B46" stroke="#D6B774" stroke-width="3"/>'
          '<rect x="12" y="12" width="156" height="276" rx="5" fill="none" stroke="#C5A269" stroke-width="1.5"/>'
          +symbol('green',90,150,2,'#C5A269'))

    for suit in COLORS:
        for disabled in [False,True]:
            name = f'button_{suit}' + ('_grey' if disabled else '')
            body = '<circle cx="48" cy="48" r="45" fill="#123631" stroke="#B99C5F" stroke-width="2"/>'
            body += f'<g opacity="{.35 if disabled else 1}">' + emblem(suit,5,5,86,86)+'</g>'
            if not disabled:
                body += '<circle cx="48" cy="48" r="43" fill="none" stroke="#F0D290" stroke-width="2"/>'
            asset(f'assets/jade/buttons/{name}.png',96,96,body)
    asset('assets/jade/buttons/button_grey.png',96,96,'<circle cx="48" cy="48" r="43" fill="#203C36" stroke="#738979" stroke-width="2"/>'+symbol('green',48,48,.7,'#738979'))
    # Match the printed suits on the three foundation targets.
    for suit in COLORS:
        c={'red':'#D3977C','green':'#8FC6A0','blue':'#96BAD6'}[suit]
        asset(f'assets/ui/slots/slot_foundation_{suit}.png',180,300,
              f'<rect x="2" y="2" width="176" height="296" rx="11" fill="#103D3B" fill-opacity=".35" stroke="{c}" stroke-width="3"/>'
              +symbol(suit,90,150,.65,c))
    asset('assets/jade/table.png',960,540,
          '<defs><radialGradient id="felt"><stop stop-color="#1A514A"/><stop offset="1" stop-color="#103D3B"/></radialGradient></defs>'
          '<rect width="960" height="540" fill="url(#felt)"/>'
          '<path d="M857 16V524" stroke="#C5A269" stroke-opacity=".18"/>'
          '<path d="M24 524Q350 480 834 524" fill="none" stroke="#C5A269" stroke-opacity=".08"/>')
    atlas = ROOT / 'main/main.atlas'
    text = atlas.read_text()
    text = re.sub(r'/assets/cards/(?:red_cards/|green_cards/|blue_cards/)?((?:[2-9]|10|d)_(?:red|green|blue)|f_flower|back)\.png',r'/assets/jade/cards/\1.png',text)
    text = text.replace('/assets/buttons/', '/assets/jade/buttons/')
    atlas.write_text(text)
    p = ROOT / 'main/Scripts/xf.atlas'
    p.write_text(p.read_text().replace('/assets/background/table.jpg','/assets/jade/table.png'))
    print('Built 32 Jade card faces/backs, 7 buttons, foundations and table')


if __name__ == '__main__':
    main()
