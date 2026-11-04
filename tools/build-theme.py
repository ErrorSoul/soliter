#!/usr/bin/env python3
"""Build deterministic vector UI assets. Requires rsvg-convert; no image downloads.

Usage: python3 tools/build-theme.py --theme classic|jade|vivid
The generated GUI keeps the board geometry and action node IDs unchanged.
"""
import argparse
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def svg_asset(path, width, height, body):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    source = path.with_suffix('.svg')
    source.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n')
    subprocess.run(['rsvg-convert', str(source), '-o', str(path)], check=True)


def rgb(hex_value):
    return [int(hex_value[i:i+2], 16) / 255 for i in (1, 3, 5)]


def field(name, values):
    return name + ' {\n' + ''.join(f'  {k}: {v}\n' for k, v in values.items()) + '}\n'


def node(name, x=0, y=0, w=0, h=0, color='#FFFFFF', parent=None,
         texture=None, text=None, scale=1, layer='buttons', enabled=True,
         alpha=1, inherit=True, rotation=0, rounded=False):
    s = 'nodes {\n' + field('position', dict(x=float(x), y=float(y)))
    s += field('size', dict(x=float(w), y=float(h)))
    s += field('color', dict(zip('xyzw', rgb(color) + [alpha])))
    if scale != 1:
        s += field('scale', dict(x=scale, y=scale, z=1.0))
    if rotation:
        s += field('rotation', dict(z=float(rotation)))
    if rounded:
        s += field('slice9', dict(x=16.0, y=16.0, z=16.0, w=16.0))
    s += f'type: TYPE_{"TEXT" if text is not None else "BOX"}\nid: "{name}"\nlayer: "{layer}"\n'
    if parent:
        s += f'parent: "{parent}"\n'
    if texture:
        s += f'texture: "{texture}"\n'
    if text is not None:
        s += f'text: "{text}"\nfont: "main_font"\n'
    s += f'alpha: {alpha}\ninherit_alpha: {str(inherit).lower()}\nenabled: {str(enabled).lower()}\n'
    return s + '}\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--theme', choices=['classic', 'jade', 'vivid'], default='classic')
    args = ap.parse_args()
    jade = args.theme == 'jade'
    bg = '#103D3B' if jade else '#063D35'
    panel = '#164B46' if jade else '#087D59'
    gold = '#D6B774' if jade else '#FFE56A'
    cream = '#F5EFDF'
    primary = '#CBB077' if jade else '#FFD23E'
    secondary = '#285950' if jade else '#07865F'

    svg_asset('assets/ui/rounded.png', 64, 64,
        '<rect x="1" y="1" width="62" height="62" rx="13" fill="white"/>')
    svg_asset('assets/ui/outlined.png', 64, 64,
        '<rect x="1" y="1" width="62" height="62" rx="13" fill="white"/>'
        f'<rect x="2" y="2" width="60" height="60" rx="12" fill="none" stroke="{gold if jade else "#FFFFFF"}" stroke-width="2"/>')
    svg_asset('assets/ui/card_outline.png', 180, 300,
        '<rect x="1.5" y="1.5" width="177" height="297" rx="8" fill="none" stroke="#4E5649" stroke-width="3"/>')
    svg_asset('assets/ui/screen_art.png', 960, 540,
        f'<defs><radialGradient id="g"><stop stop-color="{panel}"/><stop offset="1" stop-color="{bg}"/></radialGradient></defs>'
        '<rect width="960" height="540" fill="url(#g)"/>'
        f'<g fill="none" stroke="{gold}" stroke-opacity="{.22 if jade else .5}" stroke-width="1.5">'
        '<path d="M-50 440Q140 210 280 155T350 -30M-20 460Q120 240 265 180T330 -30"/>'
        '<path d="M1010 440Q820 210 680 155T610 -30M980 460Q840 240 695 180T630 -30"/></g>'
        f'<g fill="{gold}" opacity="{.12 if jade else .24}"><path d="M95 325Q30 220 22 290Q20 335 95 325M115 296Q110 195 156 213Q180 239 115 296"/>'
        '<path d="M865 325Q930 220 938 290Q940 335 865 325M845 296Q850 195 804 213Q780 239 845 296"/></g>')
    if not jade:
        source = ROOT / 'assets/ui/screen_art.svg'
        rays = ''
        for x, y, c in [(110,260,'#28F2B0'), (850,260,'#35CBFF')]:
            for angle in range(0,360,30):
                rays += f'<path transform="translate({x} {y}) rotate({angle})" d="M0-36L9-80L0-110L-9-80Z" fill="{c}" opacity=".16"/>'
        for x,y in [(80,70),(170,440),(810,80),(895,420),(230,290),(745,300)]:
            rays += f'<path d="M{x} {y-6}L{x+2} {y-2}L{x+6} {y}L{x+2} {y+2}L{x} {y+6}L{x-2} {y+2}L{x-6} {y}L{x-2} {y-2}Z" fill="{gold}" opacity=".65"/>'
        source.write_text(source.read_text().replace('</svg>', rays+'</svg>'))
        subprocess.run(['rsvg-convert',str(source),'-o',str(source.with_suffix('.png'))],check=True)
    # Strong empty-slot boundaries, rendered at 2x to keep rounded edges clean.
    for name in ['tableau', 'free', 'flower', 'foundation', 'foundation_red', 'foundation_green', 'foundation_blue']:
        color = {'foundation_red': '#D3977C', 'foundation_green': '#8FC6A0', 'foundation_blue': '#96BAD6', 'flower': '#D5A4C0'}.get(name, '#A7B89E')
        symbol = '<path d="M78 143h24v24H78z"/>' if name == 'free' else '<path d="M90 138l14 25H76z"/>'
        if name == 'tableau':
            symbol = '<path d="M90 140l12 15-12 15-12-15z"/>'
        if name == 'flower':
            symbol = '<path d="M90 140C60 110 60 160 90 170C120 160 120 110 90 140z"/>'
        svg_asset(f'assets/ui/slots/slot_{name}.png', 180, 300,
            f'<rect x="2" y="2" width="176" height="296" rx="11" fill="{bg}" fill-opacity=".35" stroke="{color}" stroke-width="3"/>'
            f'<g fill="none" stroke="{color}" stroke-width="2.5" opacity=".8">{symbol}</g>')

    ui_assets = ['rounded', 'outlined', 'card_outline', 'screen_art']
    atlas = ''.join(f'images {{\n  image: "/assets/ui/{n}.png"\n  sprite_trim_mode: SPRITE_TRIM_MODE_OFF\n}}\n' for n in ui_assets)
    (ROOT / 'gui/theme.atlas').write_text(atlas + 'extrude_borders: 2\n')

    out = 'script: "/gui/ui.gui_script"\nfonts {\n name: "main_font"\n font: "/assets/fonts/main_font.font"\n}\n'
    out += 'textures {\n name: "main"\n texture: "/main/main.atlas"\n}\ntextures {\n name: "ui"\n texture: "/gui/theme.atlas"\n}\n'
    def add(*a, **kw):
        nonlocal out
        out += node(*a, **kw)
    def button(id, textid, x, y, w, h, parent=None, primary_button=False, layer='buttons', label='', textscale=.52):
        add(id, x, y, w, h, primary if primary_button else secondary, parent, 'ui/outlined', layer=layer, rounded=True)
        add(textid, w=w, h=h, parent=id, color=bg if primary_button else cream, text=label, scale=textscale, layer=layer)

    add('hud_rail',907,90,78,152,bg,texture='ui/outlined',rounded=True,layer='background')
    button('restart_button','restart_text',907,56,70,56,label='RESTART',textscale=.30)
    button('tutorial_button','restart_text1',907,124,70,56,label='TUTORIAL',textscale=.30)

    # Oversized solid roots cover letterboxing without distorting child art/text.
    add('victory_overlay',480,270,4000,4000,bg,enabled=False)
    add('victory_art',w=960,h=540,parent='victory_overlay',texture='ui/screen_art')
    if not jade:
        add('victory_left_card',-177,143,64,107,parent='victory_overlay',texture='main/d_red',rotation=15)
        add('victory_right_card',177,143,64,107,parent='victory_overlay',texture='main/d_blue',rotation=-15)
    add('victory_medallion',0,163,106,106,parent='victory_overlay',texture='main/button_green')
    add('victory_title_plate',0,60,570,86,panel,'victory_overlay','ui/outlined',rounded=True)
    add('text1',w=550,h=74,color=cream,parent='victory_title_plate',text='Victory!',scale=1.25)
    add('victory_caption',0,-5,650,30,gold,'victory_overlay',text='',scale=.46)
    button('victory_restart','text',0,-40,280,58,'victory_overlay',True,label='PLAY AGAIN',textscale=.60)
    button('victory_menu_button','victory_menu_text',0,-120,230,52,'victory_overlay',label='MENU',textscale=.50)
    add('victory_footer',0,-220,600,28,gold,'victory_overlay',text='',scale=.34)

    add('start_screen',480,270,4000,4000,bg,layer='layer')
    add('start_art',w=960,h=540,parent='start_screen',texture='ui/screen_art',layer='layer')
    add('start_eyebrow',0,220,600,25,gold,'start_screen',text='',scale=.32,layer='layer')
    add('title_text',0,175,850,65,cream,'start_screen',text='Shenzhen Solitaire',scale=1.05,layer='layer')
    # Actual deck art: the menu remains a truthful preview of the active theme.
    add('start_card_red',-100,75,74,123,parent='start_screen',texture='main/d_red',layer='layer',rotation=12)
    add('start_card_blue',100,75,74,123,parent='start_screen',texture='main/d_blue',layer='layer',rotation=-12)
    add('start_card_green',0,82,82,137,parent='start_screen',texture='main/d_green',layer='layer')
    button('play_button','play_text',0,-40,280,58,'start_screen',True,'layer','PLAY',.64)
    button('start_tutorial_button','start_tutorial_text',0,-115,230,52,'start_screen',False,'layer','TUTORIAL',.48)
    add('start_caption',0,-185,800,30,gold,'start_screen',text='',scale=.38,layer='layer')
    add('start_footer',0,-220,800,28,'#A7B9AE','start_screen',text='',scale=.32,layer='layer')

    add('tutorial_overlay',480,270,960,540,parent=None,alpha=0,enabled=False)
    add('tutorial_highlight',w=920,h=400,parent='tutorial_overlay',alpha=0)
    # All tutorial text lives in one bottom panel; skip and count have their own space.
    add('tutorial_text_bg',0,-220,860,80,panel,'tutorial_overlay','ui/outlined',inherit=False,rounded=True)
    add('tutorial_text',65,10,660,40,cream,'tutorial_text_bg',text='',scale=.48)
    add('tutorial_step_text',65,-19,600,25,gold,'tutorial_text_bg',text='',scale=.34)
    button('tutorial_skip_btn','tutorial_skip_text',-370,-220,112,48,'tutorial_overlay',label='SKIP',textscale=.40)
    # The transparent overlay must not make its controls invisible.
    out = out.replace('id: "tutorial_skip_btn"\nlayer: "buttons"\nparent: "tutorial_overlay"\ntexture: "ui/outlined"\nalpha: 1\ninherit_alpha: true',
                      'id: "tutorial_skip_btn"\nlayer: "buttons"\nparent: "tutorial_overlay"\ntexture: "ui/outlined"\nalpha: 1\ninherit_alpha: false')
    button('music_button','music_text',907,235,78,44,layer='layer',label='MUSIC ON',textscale=.26)
    for layer in ['background','cards','buttons','layer']:
        out += f'layers {{\n name: "{layer}"\n}}\n'
    out += 'material: "/builtins/materials/gui.material"\nadjust_reference: ADJUST_REFERENCE_PARENT\n'
    (ROOT / 'gui/ui.gui').write_text(out)
    (ROOT / 'main/Scripts/theme.lua').write_text(
        '-- Generated palette: tools/build-theme.py --theme ' + args.theme + '\nreturn {\n    wildlife = false,\n' +
        ''.join(f'    {k} = {{{", ".join(str(round(v,6)) for v in rgb(c))}}},\n' for k,c in
                [('background',bg),('panel',panel),('primary',primary),('secondary',secondary)]) + '}\n')
    print('Built', args.theme, 'UI and slot assets')


if __name__ == '__main__':
    main()
