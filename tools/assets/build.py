#!/usr/bin/env python3
"""Generates every animated SVG used by README.md into ./assets.

    pip install pillow
    python tools/assets/build.py

Everything is self-contained (no web fonts, no scripts, no external requests) so
GitHub renders it through <img>. The logo and dev card are embedded as data URIs;
CI re-runs this after the daily dev-card refresh so the framed card never goes stale.
"""
import base64
import io
import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets"
OUT.mkdir(exist_ok=True)

FONT = "'Fira Code','JetBrains Mono','SF Mono',Menlo,Consolas,'DejaVu Sans Mono',monospace"
PURPLE, LILAC, CYAN, MAGENTA = "#907AD6", "#c9b8ff", "#2de2ff", "#e04bff"

# --------------------------------------------------------------------------- shared

BASE_CSS = """
.tw{animation:tw 4s ease-in-out infinite}
@keyframes tw{0%,100%{opacity:.12}50%{opacity:1}}
@keyframes in{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
@keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-4px)}}
@keyframes sweep{0%{transform:translateX(-120%)}100%{transform:translateX(120%)}}
@keyframes blink{50%{opacity:0}}
@keyframes pulse{0%,100%{opacity:.5}50%{opacity:1}}
@keyframes drift{from{transform:translateX(-60px)}to{transform:translateX(60px)}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes grow{from{transform:scaleX(0)}to{transform:scaleX(1)}}
@keyframes shoot{0%{transform:translate(0,0);opacity:0}4%{opacity:1}14%{transform:translate(260px,110px);opacity:0}100%{opacity:0}}
.shoot{opacity:0;animation-name:shoot;animation-iteration-count:infinite;animation-timing-function:ease-in}
@media (prefers-reduced-motion:reduce){*{animation:none!important}.rv{transform:none!important}.sh{opacity:0!important}}
"""

DEFS = f"""
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#05040c"/><stop offset=".6" stop-color="#150f30"/><stop offset="1" stop-color="#2a1d5a"/></linearGradient>
<linearGradient id="edge" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{PURPLE}" stop-opacity="0"/><stop offset=".5" stop-color="{LILAC}"/><stop offset="1" stop-color="{PURPLE}" stop-opacity="0"/></linearGradient>
<linearGradient id="sw" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="txt" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#cdbfff"/></linearGradient>
<linearGradient id="neon" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{CYAN}"/><stop offset="1" stop-color="{MAGENTA}"/></linearGradient>
<radialGradient id="glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="{PURPLE}" stop-opacity=".5"/><stop offset="1" stop-color="{PURPLE}" stop-opacity="0"/></radialGradient>
<filter id="blur" x="-10%" y="-400%" width="120%" height="900%"><feGaussianBlur stdDeviation="5"/></filter>
<filter id="blur28" x="-40%" y="-200%" width="180%" height="500%"><feGaussianBlur stdDeviation="28"/></filter>
"""


def svg(w, h, body, css="", label="", defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
        f'role="img" aria-label="{label}"><defs>{DEFS}{defs}</defs><style>{BASE_CSS}{css}</style>{body}</svg>'
    )


def write(name, text):
    (OUT / name).write_text(text, encoding="utf-8")


def stars(n, w, h, seed, rmax=1.5):
    r = random.Random(seed)
    out = []
    for _ in range(n):
        out.append(
            f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(0, h):.0f}" r="{r.choice([.6, .9, 1.2, rmax])}" '
            f'fill="#efeaff" class="tw" style="animation-duration:{r.uniform(2.5, 6):.1f}s;'
            f'animation-delay:-{r.uniform(0, 6):.1f}s"/>'
        )
    return "".join(out)


def edge(w, y, pad=0, sweep=True):
    s = (
        f'<rect x="{pad}" y="{y}" width="{w - 2 * pad}" height="2.4" fill="url(#edge)"/>'
        f'<rect x="{pad}" y="{y - 1}" width="{w - 2 * pad}" height="5" fill="url(#edge)" opacity=".4" filter="url(#blur)"/>'
    )
    if sweep:
        s += (
            f'<g style="overflow:hidden"><rect x="{w * .15:.0f}" y="{y - .5}" width="{w * .6:.0f}" height="3.4" '
            f'fill="url(#sw)" style="animation:sweep 5.5s ease-in-out infinite"/></g>'
        )
    return s


def floor(w, h, ey, vx=None, lines=9, cols=15, dur=5):
    """Synthwave perspective grid receding from the edge — the world 'below'."""
    vx = w / 2 if vx is None else vx
    depth = h - ey
    g = [f'<g clip-path="url(#fl)" mask="url(#fm)">']
    for i in range(-cols, cols + 1):
        x2 = vx + i * (w / cols) * 1.6
        g.append(f'<line x1="{vx}" y1="{ey}" x2="{x2:.0f}" y2="{h}" stroke="url(#neon)" stroke-opacity=".34" stroke-width="1"/>')
    for i in range(lines):
        d = -dur * i / lines
        g.append(
            f'<rect x="0" y="{ey}" width="{w}" height="1.2" fill="url(#neon)" class="gl" '
            f'style="animation:gridrun {dur}s cubic-bezier(.55,0,.9,.6) {d:.2f}s infinite;--run:{depth}px"/>'
        )
    g.append("</g>")
    defs = (
        f'<clipPath id="fl"><rect x="0" y="{ey + 3}" width="{w}" height="{depth}"/></clipPath>'
        f'<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity=".05"/></linearGradient>'
        f'<mask id="fm"><rect x="0" y="{ey}" width="{w}" height="{depth}" fill="url(#fade)"/></mask>'
    )
    css = "@keyframes gridrun{0%{transform:translateY(0);opacity:0}8%{opacity:.9}100%{transform:translateY(var(--run));opacity:0}}.gl{opacity:0}"
    return "".join(g), defs, css


def panel_defs(w, ey, rx=18):
    return f'<clipPath id="pc"><rect width="{w}" height="{ey}" rx="{rx}"/></clipPath>'


def figure(cx, y, scale=1.0, ring=True):
    s = f'<g transform="translate({cx},{y}) scale({scale})">'
    if ring:
        s += f'<circle cx="0" cy="0" r="6" fill="none" stroke="{LILAC}" stroke-width="1.2" style="transform-box:fill-box;transform-origin:center;animation:ring 3.6s ease-out infinite"/>'
    s += (
        f'<g style="animation:bob 3.6s ease-in-out infinite"><circle cx="0" cy="0" r="12" fill="url(#glow)"/>'
        f'<circle cx="0" cy="0" r="4.4" fill="#fff"/><rect x="-1.5" y="4" width="3" height="12" rx="1.5" fill="{LILAC}"/></g></g>'
    )
    return s


RING_CSS = "@keyframes ring{0%{transform:scale(.5);opacity:.8}100%{transform:scale(3.4);opacity:0}}"

# --------------------------------------------------------------------------- hero


def hero():
    W, H, EY = 900, 500, 340
    r = random.Random(42)

    def layer(n, ymax, rmin, rmax, dur, k):
        o = "".join(
            f'<circle cx="{r.uniform(0, W):.0f}" cy="{r.uniform(0, ymax):.0f}" r="{r.uniform(rmin, rmax):.1f}" fill="#efeaff" class="tw" '
            f'style="animation-duration:{r.uniform(2.5, 6):.1f}s;animation-delay:-{r.uniform(0, 6):.1f}s"/>'
            for _ in range(n)
        )
        return f'<g style="animation:par{k} {dur}s ease-in-out infinite alternate">{o}</g>'

    parts = "".join(
        f'<circle cx="{r.uniform(60, W - 60):.0f}" cy="{EY}" r="{r.choice([1.2, 1.8, 2.4])}" fill="{r.choice([LILAC, CYAN, "#fff"])}" class="rise" '
        f'style="animation-duration:{r.uniform(6, 12):.1f}s;animation-delay:-{r.uniform(0, 12):.1f}s;--dx:{r.uniform(-40, 40):.0f}px"/>'
        for _ in range(34)
    )
    shoots = "".join(
        f'<line x1="{x}" y1="{y}" x2="{x + 110}" y2="{y + 46}" stroke="url(#sw)" stroke-width="1.6" class="shoot" style="animation-delay:{d}s;animation-duration:{p}s"/>'
        for x, y, d, p in [(40, 20, 1, 9), (380, 10, 4.5, 11), (120, 70, 8, 13), (560, 30, 12, 10)]
    )
    # eclipse rising behind the figure: the "past it" the motto talks about
    ecx, er = 450, 118
    rays = "".join(
        f'<line x1="{ecx}" y1="{EY}" x2="{ecx + math.cos(math.radians(a)) * 420:.0f}" y2="{EY + math.sin(math.radians(a)) * 420:.0f}" stroke="url(#ray)" stroke-width="{w_}"/>'
        for a, w_ in [(a, 1 if i % 3 else 1.6) for i, a in enumerate(range(184, 360, 9))]
    )
    floor_g, floor_defs, floor_css = floor(W, H, EY)
    body = f"""<rect width="{W}" height="{H}" rx="18" fill="url(#bg2)"/>
<g clip-path="url(#hc)">
<g filter="url(#blur30)" opacity=".7"><ellipse cx="230" cy="150" rx="260" ry="46" fill="#5b3fd0" style="animation:drift 11s ease-in-out infinite alternate"/><ellipse cx="660" cy="120" rx="280" ry="40" fill="#1fa3b8" opacity=".55" style="animation:drift 14s ease-in-out infinite alternate-reverse"/><ellipse cx="450" cy="210" rx="320" ry="34" fill="#a04bd0" opacity=".45" style="animation:drift 17s ease-in-out infinite alternate"/></g>
{layer(46, 320, .5, .9, 26, 'a')}{layer(34, 320, .9, 1.4, 18, 'b')}{layer(14, 280, 1.4, 2, 12, 'c')}
{shoots}
<g style="transform-origin:{ecx}px {EY}px;animation:spin 90s linear infinite" opacity=".3">{rays}</g>
<circle cx="{ecx}" cy="{EY}" r="{er + 46}" fill="url(#corona)" style="transform-origin:{ecx}px {EY}px;animation:halo 5s ease-in-out infinite"/>
<circle cx="{ecx}" cy="{EY}" r="{er}" fill="#030208"/>
<circle cx="{ecx}" cy="{EY}" r="{er}" fill="none" stroke="url(#neon)" stroke-width="2.2" style="animation:rim 6s ease-in-out infinite"/>
<circle cx="{ecx}" cy="{EY}" r="{er + 8}" fill="none" stroke="url(#neon)" stroke-opacity=".28" stroke-width="1" stroke-dasharray="2 7" style="transform-origin:{ecx}px {EY}px;animation:spin 40s linear infinite reverse"/>
{parts}
</g>
{edge(W, EY)}
<g clip-path="url(#hall)"><rect x="0" y="{EY + 3}" width="{W}" height="{H - EY - 3}" fill="#05040b" opacity=".72"/>
{floor_g}</g>
{figure(ecx, EY - 16)}
<text x="450" y="98" text-anchor="middle" class="m1" clip-path="url(#c1)">Every system has an edge.</text>
<text x="450" y="146" text-anchor="middle" class="m2" clip-path="url(#c2)">I like to stand on it, curious,</text>
<text x="450" y="180" text-anchor="middle" class="m2" clip-path="url(#c3)">and see what&#8217;s past it.</text>
<rect class="cur" x="0" y="0" width="9" height="22"/>
<text x="450" y="{H - 26}" text-anchor="middle" class="tag">XYNORASH &#183; A COORDINATE</text>
<rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="17" fill="none" stroke="{PURPLE}" stroke-opacity=".35"/>"""
    css = f"""
.rise{{animation:rise 8s linear infinite;opacity:0}}
@keyframes rise{{0%{{transform:translate(0,0);opacity:0}}12%{{opacity:.95}}100%{{transform:translate(var(--dx),-300px);opacity:0}}}}
@keyframes halo{{0%,100%{{transform:scale(.9);opacity:.75}}50%{{transform:scale(1.12);opacity:1}}}}
@keyframes rim{{0%,100%{{stroke-opacity:.65}}50%{{stroke-opacity:1}}}}
@keyframes para{{from{{transform:translateX(-6px)}}to{{transform:translateX(6px)}}}}
@keyframes parb{{from{{transform:translateX(-12px)}}to{{transform:translateX(12px)}}}}
@keyframes parc{{from{{transform:translateX(-22px)}}to{{transform:translateX(22px)}}}}
.m1{{font:700 34px {FONT};fill:url(#txt);letter-spacing:.5px}}
.m2{{font:500 20px {FONT};fill:#c5b6ff}}
.tag{{font:500 12px {FONT};fill:#7f70b8;letter-spacing:5px}}
.cur{{fill:{PURPLE};animation:blink 1s steps(1) infinite,curmove 9s steps(1) forwards}}
#r1,#r2,#r3{{transform-box:fill-box;transform-origin:left}}
#r1{{animation:grow 1.6s steps(25) .4s both}}#r2{{animation:grow 1.6s steps(31) 2.2s both}}#r3{{animation:grow 1.4s steps(26) 4s both}}
@keyframes curmove{{0%{{transform:translate(712px,72px)}}22%{{transform:translate(712px,72px)}}23%{{transform:translate(640px,130px)}}43%{{transform:translate(640px,130px)}}44%{{transform:translate(594px,164px)}}100%{{transform:translate(594px,164px)}}}}
{RING_CSS}{floor_css}"""
    defs = f"""<linearGradient id="bg2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#05040c"/><stop offset=".55" stop-color="#150f30"/><stop offset="1" stop-color="#2a1d5a"/></linearGradient>
<filter id="blur30" x="-30%" y="-150%" width="160%" height="400%"><feGaussianBlur stdDeviation="30"/></filter>
<radialGradient id="corona" cx=".5" cy=".5" r=".5"><stop offset=".62" stop-color="{MAGENTA}" stop-opacity=".55"/><stop offset=".8" stop-color="{PURPLE}" stop-opacity=".25"/><stop offset="1" stop-color="{PURPLE}" stop-opacity="0"/></radialGradient>
<linearGradient id="ray" gradientUnits="userSpaceOnUse" x1="{ecx}" y1="{EY}" x2="{ecx}" y2="{EY - 420}"><stop offset="0" stop-color="{LILAC}" stop-opacity=".5"/><stop offset="1" stop-color="{LILAC}" stop-opacity="0"/></linearGradient>
<clipPath id="hall"><rect width="{W}" height="{H}" rx="18"/></clipPath><clipPath id="hc"><rect width="{W}" height="{EY}" rx="18"/></clipPath>
<clipPath id="c1"><rect id="r1" x="170" y="64" width="560" height="46"/></clipPath>
<clipPath id="c2"><rect id="r2" x="240" y="124" width="420" height="30"/></clipPath>
<clipPath id="c3"><rect id="r3" x="270" y="158" width="360" height="30"/></clipPath>{floor_defs}"""
    write("hero.svg", svg(W, H, body, css, "Every system has an edge. I like to stand on it, curious, and see what's past it.", defs))


# --------------------------------------------------------------------------- section headers


def section(name, num, title, sub, seed):
    W, H = 900, 110
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/>
<g clip-path="url(#rc)"><g filter="url(#blur22)" opacity=".55"><ellipse cx="200" cy="40" rx="190" ry="26" fill="#6b4fd8" style="animation:drift 9s ease-in-out infinite alternate"/><ellipse cx="700" cy="50" rx="200" ry="24" fill="#3aa8c8" opacity=".6" style="animation:drift 12s ease-in-out infinite alternate-reverse"/></g>
{stars(26, W, 70, seed)}
<line x1="0" y1="0" x2="90" y2="40" stroke="url(#sw)" stroke-width="1.5" class="shoot" style="animation-duration:7s;animation-delay:{seed % 5}s"/></g>
<ellipse cx="450" cy="92" rx="360" ry="34" fill="url(#glow)" style="animation:pulse 4s ease-in-out infinite"/>
{edge(W, 92, 30)}
<path d="M14 26V14h12M886 26V14h-12M14 84v12h12M886 84v12h-12" stroke="{PURPLE}" stroke-opacity=".6" fill="none" style="animation:pulse 3s infinite"/>
<text x="450" y="38" text-anchor="middle" class="n">{num}</text>
<text x="450" y="68" text-anchor="middle" class="t">{title}</text>
<text x="450" y="86" text-anchor="middle" class="s">{sub}</text>"""
    css = f""".n{{font:500 11px {FONT};fill:#7f70b8;letter-spacing:6px;animation:in 1s ease both}}
.t{{font:700 26px {FONT};fill:url(#txt);letter-spacing:2px;animation:in 1s .15s ease both}}
.s{{font:400 11px {FONT};fill:#9d8fd6;animation:in 1s .3s ease both}}"""
    defs = '<clipPath id="rc"><rect width="900" height="110" rx="14"/></clipPath><filter id="blur22" x="-30%" y="-150%" width="160%" height="400%"><feGaussianBlur stdDeviation="22"/></filter>'
    write(name, svg(W, H, body, css, title, defs))


# --------------------------------------------------------------------------- ticker


def ticker():
    W, H = 900, 44
    words = ["RUST", "DART", "FLUTTER", "LUA", "POWERSHELL", "NEOVIM", "ARCH", "HYPRLAND", "SYSTEMD"]
    unit = "  ◆  ".join(words) + "  ◆  "
    tl = 1500  # fixed length for a seamless loop
    body = f"""<rect width="{W}" height="{H}" rx="10" fill="url(#bg)"/>
<g clip-path="url(#tc)"><g class="tk"><text x="0" y="27" class="w" textLength="{tl}" lengthAdjust="spacing">{unit}</text><text x="{tl}" y="27" class="w" textLength="{tl}" lengthAdjust="spacing">{unit}</text></g>
<rect width="120" height="{H}" fill="url(#fl2)"/><rect x="{W - 120}" width="120" height="{H}" fill="url(#fr2)"/></g>
<rect x="30" y="{H - 2}" width="{W - 60}" height="1.6" fill="url(#edge)"/>"""
    css = f".w{{font:500 12px {FONT};fill:#9d8fd6;letter-spacing:3px;white-space:pre}}.tk{{animation:tick 28s linear infinite}}@keyframes tick{{to{{transform:translateX(-{tl}px)}}}}"
    defs = (
        f'<clipPath id="tc"><rect width="{W}" height="{H}" rx="10"/></clipPath>'
        '<linearGradient id="fl2"><stop offset="0" stop-color="#05040c"/><stop offset="1" stop-color="#05040c" stop-opacity="0"/></linearGradient>'
        '<linearGradient id="fr2"><stop offset="0" stop-color="#05040c" stop-opacity="0"/><stop offset="1" stop-color="#05040c"/></linearGradient>'
    )
    write("ticker.svg", svg(W, H, body, css, "Rust, Dart, Flutter, Lua, PowerShell, Neovim, Arch, Hyprland", defs))


# --------------------------------------------------------------------------- about (editor)


def about():
    W, H = 900, 296
    lines = [
        ("spec first.", " measure before believing."),
        ("document", " what was verified, not what was intended."),
        ("when a heuristic can be wrong,", " make the failure a test."),
        ("fail closed.", " if safety can’t be established, say no."),
    ]
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/><g>{stars(26, W, H - 40, 5)}</g>
<rect x="0" y="0" width="{W}" height="38" rx="14" fill="#0c0920"/><rect x="0" y="24" width="{W}" height="14" fill="#0c0920"/>
<circle cx="26" cy="19" r="5" fill="#ff6b8b"/><circle cx="46" cy="19" r="5" fill="#f2c86a"/><circle cx="66" cy="19" r="5" fill="#6ad6a0"/>
<rect x="110" y="8" width="170" height="30" rx="8" fill="#150f30"/><rect x="110" y="36" width="170" height="2" fill="url(#neon)"/>
<text x="126" y="28" class="tab">principles.md</text>
<rect x="56" y="38" width="1" height="{H - 76}" fill="{PURPLE}" opacity=".25"/>"""
    css = f".ln{{font:400 15px {FONT};fill:#4d4382}}.p{{font:500 17px {FONT}}}.tab{{font:500 12px {FONT};fill:#c9b8ff}}.sl{{font:600 11px {FONT}}}"
    defs = ""
    for i, (a, b) in enumerate(lines):
        y = 82 + i * 38
        n = len(a) + len(b)
        cw = 10.25
        d = 0.5 + i * 1.5
        body += (
            f'<text x="34" y="{y}" class="ln" text-anchor="end" transform="translate(12 0)">{i + 1}</text>'
            f'<text x="74" y="{y}" class="p" clip-path="url(#l{i})"><tspan fill="#fff" font-weight="700">{a}</tspan><tspan fill="#b9a8ff">{b}</tspan></text>'
        )
        defs += f'<clipPath id="l{i}"><rect class="rv" id="lr{i}" x="70" y="{y - 20}" width="{n * cw + 12:.0f}" height="28"/></clipPath>'
        css += f"#lr{i}{{transform-box:fill-box;transform-origin:left;animation:grow {n * .035:.2f}s steps({n}) {d}s both}}"
    # cursor line + statusline
    body += f"""<text x="34" y="{82 + 4 * 38}" class="ln" text-anchor="end" transform="translate(12 0)">5</text>
<rect x="74" y="{82 + 4 * 38 - 17}" width="10" height="21" fill="{LILAC}" style="animation:blink 1s steps(1) infinite"/>
<rect y="{H - 30}" width="{W}" height="30" fill="#0c0920"/><rect x="0" y="{H - 30}" width="{W}" height="1" fill="{PURPLE}" opacity=".3"/>
<g class="mode m-n"><rect x="0" y="{H - 30}" width="92" height="30" fill="{PURPLE}"/><text x="46" y="{H - 11}" text-anchor="middle" class="sl" fill="#0c0920">NORMAL</text></g>
<g class="mode m-i"><rect x="0" y="{H - 30}" width="92" height="30" fill="{CYAN}"/><text x="46" y="{H - 11}" text-anchor="middle" class="sl" fill="#0c0920">INSERT</text></g>
<g class="mode m-v"><rect x="0" y="{H - 30}" width="92" height="30" fill="{MAGENTA}"/><text x="46" y="{H - 11}" text-anchor="middle" class="sl" fill="#0c0920">VISUAL</text></g>
<text x="108" y="{H - 11}" class="sl" fill="#9d8fd6">xynorash/principles.md</text><text x="{W - 20}" y="{H - 11}" text-anchor="end" class="sl" fill="#7f70b8">utf-8  &#183;  markdown  &#183;  5:1</text>"""
    css += """.mode{opacity:0;animation:modes 12s steps(1) infinite}
.m-n{animation-name:mn}.m-i{animation-name:mi}.m-v{animation-name:mv}
@keyframes mn{0%,40%{opacity:1}41%,100%{opacity:0}}
@keyframes mi{0%,40%{opacity:0}41%,70%{opacity:1}71%,100%{opacity:0}}
@keyframes mv{0%,70%{opacity:0}71%,85%{opacity:1}86%,100%{opacity:0}}
"""
    write("about.svg", svg(W, H, body, css, "principles.md: spec first, measure before believing, document what was verified, fail closed", defs))


# --------------------------------------------------------------------------- stack


GLYPHS = {
    # simple geometric marks, drawn in a 0..24 box
    "rust": '<circle cx="12" cy="12" r="6.5" fill="none" stroke="{c}" stroke-width="2"/><circle cx="12" cy="12" r="2" fill="{c}"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M5 19l2-2" stroke="{c}" stroke-width="2" stroke-linecap="round"/>',
    "dart": '<path d="M4 12L12 4l8 4-4 4 4 4-8 4z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/>',
    "ps": '<path d="M5 6l8 6-8 6" fill="none" stroke="{c}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M14 19h6" stroke="{c}" stroke-width="2.4" stroke-linecap="round"/>',
    "nvim": '<path d="M5 20V4l14 16V4" fill="none" stroke="{c}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>',
    "arch": '<path d="M12 3L4 21c3-2 5-3 8-3s5 1 8 3z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/><path d="M9 15c1.5-3 3-5 3-8" fill="none" stroke="{c}" stroke-width="1.6"/>',
}


def stack():
    W, H, EY = 900, 250, 188
    items = [
        ("Rust", "systems", "#f0a56a", "rust"),
        ("Dart/Flutter", "UI · this site", "#4fd1e0", "dart"),
        ("PowerShell+Lua", "where I live", "#9bd77a", "ps"),
        ("Neovim", "the cockpit", "#7ad66a", "nvim"),
        ("Arch/Hyprland", "the desktop", "#6ab4f0", "arch"),
    ]
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/><g>{stars(40, W, EY - 20, 11)}</g>
<ellipse cx="450" cy="{EY}" rx="420" ry="50" fill="url(#glow)" style="animation:pulse 5s infinite"/>{edge(W, EY, 20)}"""
    gap = (W - 80) / len(items)
    for i, (t, s, c, g) in enumerate(items):
        cx = 40 + gap * i + gap / 2
        d = 3 + (i % 3) * .7
        body += f"""<g style="animation:in .8s {.2 + i * .15:.2f}s ease both"><g style="animation:bob {d}s ease-in-out infinite;animation-delay:-{i * .6}s">
<rect x="{cx - 70:.0f}" y="64" width="140" height="92" rx="12" fill="#120e26" stroke="{c}" stroke-opacity=".5"/>
<rect x="{cx - 70:.0f}" y="64" width="140" height="92" rx="12" fill="url(#cardglow{i})"/>
<g transform="translate({cx - 12:.0f} 76) scale(1)"><circle cx="12" cy="12" r="19" fill="{c}" fill-opacity=".1" style="animation:pulse 3s {i * .4}s infinite"/>{GLYPHS[g].format(c=c)}</g>
<text x="{cx:.0f}" y="128" text-anchor="middle" class="k">{t}</text><text x="{cx:.0f}" y="145" text-anchor="middle" class="d">{s}</text></g>
<line x1="{cx:.0f}" y1="158" x2="{cx:.0f}" y2="{EY}" stroke="{c}" stroke-opacity=".4" stroke-dasharray="2 4"/><circle cx="{cx:.0f}" cy="{EY}" r="3" fill="{c}"/></g>"""
    body += f'<text x="450" y="{H - 22}" text-anchor="middle" class="d" style="letter-spacing:4px;fill:#7f70b8">STANDING ON THE EDGE</text>'
    defs = "".join(
        f'<radialGradient id="cardglow{i}" cx=".5" cy="0" r=".9"><stop offset="0" stop-color="{c}" stop-opacity=".16"/><stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>'
        for i, (_, _, c, _) in enumerate(items)
    )
    css = f".k{{font:700 13px {FONT};fill:#fff}}.d{{font:400 10.5px {FONT};fill:#9d8fd6}}"
    write("stack.svg", svg(W, H, body, css, "Stack: Rust, Dart/Flutter, PowerShell and Lua, Neovim, Arch and Hyprland", defs))


# --------------------------------------------------------------------------- projects (terminal)


def projects():
    W = 900
    rows = [
        ("heaplens/", "live heap inspector for Windows", "Rust", "#f0a56a"),
        ("xynovim/", "my Neovim, tuned until it disappears", "Lua", "#7ad66a"),
        ("xyno-scholar/", "AI research-topic explorer", "Dart", "#4fd1e0"),
        ("xynorash-pwsh/", "a PowerShell cockpit with neon vitals", "PowerShell", "#9bd77a"),
        ("xyno-arch/", "my whole Arch desktop, reproducible", "Arch", "#6ab4f0"),
    ]
    rh, top = 52, 108
    H = top + rh * len(rows) + 24
    cmd = "ls ~/past-the-edge"
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/><g>{stars(34, W, H, 21)}</g>
<rect width="{W}" height="40" rx="14" fill="#0c0920"/><rect y="26" width="{W}" height="14" fill="#0c0920"/>
<circle cx="26" cy="20" r="5" fill="#ff6b8b"/><circle cx="46" cy="20" r="5" fill="#f2c86a"/><circle cx="66" cy="20" r="5" fill="#6ad6a0"/>
<text x="450" y="24" text-anchor="middle" class="d">xynorash@edge: ~</text>
<rect x="20" y="40" width="{W - 40}" height="1" fill="{PURPLE}" opacity=".3"/>
<text x="30" y="76" class="ps"><tspan fill="{CYAN}">xynorash</tspan><tspan fill="#7f70b8">@</tspan><tspan fill="{MAGENTA}">edge</tspan><tspan fill="#7f70b8"> ~ </tspan><tspan fill="{PURPLE}">&#10095;</tspan></text>
<text x="206" y="76" class="cmd" clip-path="url(#cc)">{cmd}</text>
<rect class="cur2" x="0" y="0" width="9" height="19"/>"""
    css = f""".d{{font:400 11px {FONT};fill:#7f70b8}}.ps{{font:600 14px {FONT}}}.cmd{{font:500 14px {FONT};fill:#fff}}
.pr{{font:700 14px {FONT};fill:{PURPLE}}}.nm{{font:700 15px {FONT};fill:#fff}}.d2{{font:400 13px {FONT};fill:#b9a8ff}}.tag{{font:500 11px {FONT};letter-spacing:2px}}
#cr{{transform-box:fill-box;transform-origin:left;animation:grow 1.2s steps({len(cmd)}) .5s both}}
.cur2{{fill:{LILAC};animation:blink 1s steps(1) infinite,c2 6s steps(1) forwards}}
@keyframes c2{{0%{{transform:translate(206px,61px)}}30%{{transform:translate({206 + len(cmd) * 8.4:.0f}px,61px)}}100%{{transform:translate({206 + len(cmd) * 8.4:.0f}px,61px)}}}}
.row{{opacity:0;animation:in .7s ease both}}"""
    defs = f'<clipPath id="cc"><rect id="cr" x="202" y="60" width="{len(cmd) * 8.6 + 8:.0f}" height="22"/></clipPath>'
    for i, (n, d_, l, c) in enumerate(rows):
        y = top + i * rh
        body += f"""<g class="row" style="animation-delay:{1.9 + i * .22:.2f}s"><rect x="20" y="{y}" width="{W - 40}" height="{rh - 8}" rx="9" fill="{c}" fill-opacity=".06" stroke="{c}" stroke-opacity=".18"/>
<rect x="20" y="{y}" width="3" height="{rh - 8}" rx="1.5" fill="{c}"/>
<g style="overflow:hidden"><rect x="40" y="{y}" width="160" height="{rh - 8}" fill="url(#sw)" opacity=".07" style="animation:sweep 6s {i * .9:.1f}s ease-in-out infinite"/></g>
<text x="44" y="{y + 28}" class="pr">&#10095;</text><text x="70" y="{y + 28}" class="nm">{n}</text><text x="290" y="{y + 28}" class="d2">{d_}</text>
<circle cx="{W - 160}" cy="{y + 23}" r="4" fill="{c}" style="animation:pulse 2.4s {i * .3:.1f}s infinite"/><text x="{W - 40}" y="{y + 27}" text-anchor="end" class="tag" fill="{c}">{l.upper()}</text></g>"""
    write("projects.svg", svg(W, H, body, css, "Projects: heaplens, xynovim, xyno-scholar, xynorash-pwsh, xyno-arch", defs))


# --------------------------------------------------------------------------- connect buttons

ICONS = {
    "gh": '<path transform="scale(1.5)" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" fill="{c}"/>',
    "mail": '<rect x="3" y="5" width="18" height="14" rx="2.500" fill="none" stroke="{c}" stroke-width="2"/><path d="M3.500 7l8.500 6 8.500-6" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/>',
    "in": '<rect x="3" y="3" width="18" height="18" rx="3.500" fill="none" stroke="{c}" stroke-width="2"/><path d="M8 10.500V17M8 7.200v.1M12 17v-3.500a2.500 2.500 0 0 1 5 0V17M12 10.500V17" fill="none" stroke="{c}" stroke-width="2" stroke-linecap="round"/>',
    "fb": '<rect x="3" y="3" width="18" height="18" rx="3.500" fill="none" stroke="{c}" stroke-width="2"/><path d="M15.500 21v-7h2.300M13 14h2.500M15.500 14v-2.300c0-1.200.7-1.700 1.700-1.700h.8" fill="none" stroke="{c}" stroke-width="2" stroke-linecap="round" transform="translate(-1 0)"/>',
    "dd": '<path d="M3 12l5-5 4 4M21 12l-5 5-4-4M8 17l-3-3M16 7l3 3" fill="none" stroke="{c}" stroke-width="2.200" stroke-linecap="round" stroke-linejoin="round"/>',
}


def button(name, icon, label, sub, col):
    W, H = 270, 68
    body = f"""<rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="13" fill="url(#bg)" stroke="{col}" stroke-opacity=".55"/>
<rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="13" fill="url(#bglow)"/>
<g style="overflow:hidden"><rect x="0" y="0" width="120" height="{H}" fill="url(#sw)" opacity=".1" style="animation:sweep 5s ease-in-out infinite"/></g>
<circle cx="38" cy="34" r="16" fill="none" stroke="{col}" stroke-opacity=".6" style="transform-box:fill-box;transform-origin:center;animation:sig 3s ease-out infinite"/>
<circle cx="38" cy="34" r="16" fill="{col}" fill-opacity=".12"/>
<g transform="translate(26 22)">{ICONS[icon].format(c=col)}</g>
<text x="68" y="31" class="b">{label}</text><text x="68" y="49" class="u">{sub}</text>
<path d="M{W - 34} 28l8 6-8 6" fill="none" stroke="{col}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="animation:nudge 2.4s ease-in-out infinite"/>"""
    css = f".b{{font:700 15px {FONT};fill:#fff}}.u{{font:400 10.5px {FONT};fill:#9d8fd6}}@keyframes sig{{0%{{transform:scale(.8);opacity:.9}}100%{{transform:scale(1.9);opacity:0}}}}@keyframes nudge{{0%,100%{{transform:translateX(0)}}50%{{transform:translateX(4px)}}}}"
    defs = f'<radialGradient id="bglow" cx="0" cy=".5" r="1"><stop offset="0" stop-color="{col}" stop-opacity=".16"/><stop offset="1" stop-color="{col}" stop-opacity="0"/></radialGradient>'
    write(name, svg(W, H, body, css, label, defs))


# --------------------------------------------------------------------------- coordinate radar


def coordinate():
    W, H = 900, 260
    cx, cy = 450, 130
    rings = "".join(
        f'<circle cx="{cx}" cy="{cy}" r="{rr}" fill="none" stroke="{PURPLE}" stroke-opacity="{.5 - i * .1:.2f}" stroke-dasharray="{2 + i * 2} 6"/>'
        for i, rr in enumerate([30, 60, 90, 120])
    )
    blips = "".join(
        f'<circle cx="{cx + math.cos(a) * rr:.0f}" cy="{cy + math.sin(a) * rr:.0f}" r="3" fill="{CYAN}" class="bl" style="animation-delay:{d}s"/>'
        for a, rr, d in [(0.6, 70, .8), (2.2, 95, 2.2), (3.9, 50, 3.6), (5.2, 108, 4.9), (1.4, 38, 1.5)]
    )
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/><g>{stars(30, W, H, 9)}</g>{rings}
<line x1="{cx - 140}" y1="{cy}" x2="{cx + 140}" y2="{cy}" stroke="{PURPLE}" stroke-opacity=".35"/><line x1="{cx}" y1="0" x2="{cx}" y2="{H}" stroke="{PURPLE}" stroke-opacity=".25"/>
<g style="transform-origin:{cx}px {cy}px;animation:spin 5s linear infinite"><path d="M{cx} {cy} L{cx} {cy - 120} A120 120 0 0 0 {cx - 104} {cy - 60} Z" fill="url(#rad)"/><line x1="{cx}" y1="{cy}" x2="{cx}" y2="{cy - 120}" stroke="{LILAC}" stroke-width="1.5"/></g>
{blips}
<circle cx="{cx}" cy="{cy}" r="5" fill="#fff"/><circle cx="{cx}" cy="{cy}" r="5" fill="none" stroke="#fff" style="transform-box:fill-box;transform-origin:center;animation:ping 2.4s ease-out infinite"/>
<text x="40" y="52" class="l">XYNORASH</text><text x="40" y="72" class="s">isn&#8217;t a name.</text>
<text x="860" y="52" text-anchor="end" class="l">COORDINATE</text><text x="860" y="72" text-anchor="end" class="s">x &#8594; unknown &#183; y &#8594; unknown &#183; z &#8594; past the edge</text>
<text x="40" y="232" class="s">scanning<tspan style="animation:blink 1s steps(1) infinite"> &#9646;</tspan></text><text x="860" y="232" text-anchor="end" class="s">5 signals locked</text>"""
    css = f""".l{{font:700 16px {FONT};fill:#fff;letter-spacing:4px}}.s{{font:400 11px {FONT};fill:#9d8fd6}}
@keyframes ping{{0%{{transform:scale(1);opacity:.8}}100%{{transform:scale(7);opacity:0}}}}
.bl{{transform-box:fill-box;transform-origin:center;animation:blip 5s infinite}}
@keyframes blip{{0%,28%{{opacity:0;transform:scale(.3)}}34%{{opacity:1;transform:scale(1.6)}}70%{{opacity:.5;transform:scale(1)}}100%{{opacity:0}}}}"""
    defs = f'<linearGradient id="rad" gradientUnits="userSpaceOnUse" x1="{cx}" y1="{cy - 120}" x2="{cx - 104}" y2="{cy - 60}"><stop offset="0" stop-color="{PURPLE}" stop-opacity=".6"/><stop offset="1" stop-color="{PURPLE}" stop-opacity="0"/></linearGradient>'
    write("coordinate.svg", svg(W, H, body, css, "Xynorash is not a name, it is a coordinate", defs))


# --------------------------------------------------------------------------- footer + statusline


def footer():
    W, H, EY = 900, 190, 140
    body = f"""<rect width="{W}" height="{H}" rx="14" fill="url(#bg)"/><g>{stars(40, W, EY - 20, 3)}</g>
<ellipse cx="450" cy="{EY}" rx="400" ry="42" fill="url(#glow)" style="animation:pulse 4s infinite"/>{edge(W, EY, 20)}
{figure(450, EY - 12, .9)}
<text x="450" y="62" text-anchor="middle" class="f1">past the edge, there&#8217;s always more.</text>
<text x="450" y="{H - 14}" text-anchor="middle" class="f2">XYNORASH &#183; A COORDINATE &#183; NASH TEFISON</text>"""
    css = f".f1{{font:600 22px {FONT};fill:url(#txt);animation:in 1.2s ease both}}.f2{{font:500 11px {FONT};fill:#7f70b8;letter-spacing:4px}}{RING_CSS}"
    write("footer.svg", svg(W, H, body, css, "past the edge, there's always more"))


# --------------------------------------------------------------------------- logo + dev card panels


def data_uri(img):
    b = io.BytesIO()
    img.save(b, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()


def logo_panel():
    logo = Image.open(ROOT / "xynorash_logo.png").convert("RGBA").crop((225, 180, 1325, 850))
    logo = logo.resize((int(logo.width * .8), int(logo.height * .8)), Image.LANCZOS)
    url = data_uri(logo)
    W, H, EY = 560, 440, 340
    dw = 460
    dh = dw * logo.height / logo.width
    lx, ly = (W - dw) / 2, EY - dh - 14
    floor_g, floor_defs, floor_css = floor(W, H, EY, lines=7, cols=11)
    body = f"""<rect width="{W}" height="{H}" rx="18" fill="url(#bg)"/>
<g clip-path="url(#pc)"><g filter="url(#blur28)" opacity=".75"><ellipse cx="170" cy="150" rx="170" ry="60" fill="{CYAN}" opacity=".28" style="animation:drift 10s ease-in-out infinite alternate"/><ellipse cx="400" cy="200" rx="170" ry="70" fill="{MAGENTA}" opacity=".3" style="animation:drift 13s ease-in-out infinite alternate-reverse"/></g>
{stars(42, W, EY, 17)}<ellipse cx="{W / 2}" cy="{EY}" rx="270" ry="60" fill="url(#glow)" style="animation:pulse 4s infinite"/></g>
{edge(W, EY)}
<g clip-path="url(#pall)"><rect x="0" y="{EY + 3}" width="{W}" height="{H - EY - 3}" fill="#05040b" opacity=".7"/>
{floor_g}</g>
<g class="lg"><use href="#lg"/><g mask="url(#lm)"><rect x="{lx:.0f}" y="{ly:.0f}" width="140" height="{dh:.0f}" fill="url(#sw)" style="animation:sweep2 4.5s ease-in-out infinite"/></g></g>
<text x="{W / 2}" y="{H - 20}" text-anchor="middle" class="tg">XYNORASH</text>
<rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="17" fill="none" stroke="{PURPLE}" stroke-opacity=".35"/>"""
    css = f""".lg{{animation:bob 4.5s ease-in-out infinite;filter:drop-shadow(0 0 14px rgba(160,90,255,.55))}}
@keyframes sweep2{{0%{{transform:translateX(-180px)}}100%{{transform:translateX({dw + 120}px)}}}}
.tg{{font:500 12px {FONT};fill:#7f70b8;letter-spacing:8px}}{floor_css}"""
    defs = (
        panel_defs(W, EY)
        + f'<clipPath id="pall"><rect width="{W}" height="{H}" rx="18"/></clipPath>'
        + floor_defs
        + f'<image id="lg" href="{url}" x="{lx:.0f}" y="{ly:.0f}" width="{dw}" height="{dh:.0f}"/>'
        + f'<mask id="lm"><use href="#lg"/></mask>'
    )
    write("logo.svg", svg(W, H, body, css, "Xynorash logo", defs))


def card_panel():
    src = ROOT / "devcard.png"
    card = Image.open(src).convert("RGBA")
    card = card.resize((470, int(470 * card.height / card.width)), Image.LANCZOS)
    url = data_uri(card)
    W, H, EY = 330, 440, 416
    cw = 262
    ch = cw * card.height / card.width
    cx, cy = (W - cw) / 2, (EY - ch) / 2 + 4
    body = f"""<rect width="{W}" height="{H}" rx="18" fill="url(#bg)"/>
<g clip-path="url(#pc)"><g filter="url(#blur26)" opacity=".8"><ellipse cx="80" cy="120" rx="110" ry="80" fill="#5b3fd0" style="animation:drift 9s ease-in-out infinite alternate"/><ellipse cx="260" cy="300" rx="110" ry="80" fill="{CYAN}" opacity=".5" style="animation:drift 12s ease-in-out infinite alternate-reverse"/></g>{stars(30, W, EY, 31)}</g>
<g style="transform-origin:165px {EY / 2:.0f}px;animation:spin 14s linear infinite"><ellipse cx="165" cy="{EY / 2:.0f}" rx="152" ry="196" fill="none" stroke="{PURPLE}" stroke-opacity=".35" stroke-dasharray="3 9"/><circle cx="165" cy="{EY / 2 - 196:.0f}" r="3" fill="{CYAN}"/></g>
<g class="cd"><rect x="{cx - 4:.0f}" y="{cy - 4:.0f}" width="{cw + 8}" height="{ch + 8:.0f}" rx="26" fill="none" stroke="url(#neon)" stroke-width="2"/>
<use href="#cdi"/><g mask="url(#cm)"><rect x="{cx:.0f}" y="{cy:.0f}" width="80" height="{ch:.0f}" fill="url(#sw)" opacity=".6" style="animation:sweep3 5s ease-in-out infinite"/></g></g>
{edge(W, EY, 0, False)}
<rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="17" fill="none" stroke="{PURPLE}" stroke-opacity=".35"/>"""
    css = f""".cd{{transform-origin:165px {EY / 2:.0f}px;animation:wob 6s ease-in-out infinite;filter:drop-shadow(0 8px 18px rgba(120,80,255,.35))}}
@keyframes wob{{0%,100%{{transform:translateY(0) rotate(-1.2deg)}}50%{{transform:translateY(-6px) rotate(1.2deg)}}}}
@keyframes sweep3{{0%{{transform:translateX(-120px)}}100%{{transform:translateX({cw + 60}px)}}}}"""
    defs = (
        panel_defs(W, EY)
        + '<filter id="blur26" x="-30%" y="-150%" width="160%" height="400%"><feGaussianBlur stdDeviation="26"/></filter>'
        + f'<image id="cdi" href="{url}" x="{cx:.0f}" y="{cy:.0f}" width="{cw}" height="{ch:.0f}"/><mask id="cm"><use href="#cdi"/></mask>'
    )
    write("devcard.svg", svg(W, H, body, css, "Nash Tefison daily.dev card", defs))


# --------------------------------------------------------------------------- run


def main():
    hero()
    for name, num, title, sub, seed in [
        ("s-edge.svg", "01 · THE EDGE", "WHO STANDS HERE", "systems from the inside — if it has a feedback loop, I want it faster", 3),
        ("s-stack.svg", "02 · FOOTING", "WHAT I STAND ON", "the ground under my feet", 8),
        ("s-past.svg", "03 · PAST IT", "WHAT I FOUND OUT THERE", "every project is a directory — go explore", 13),
        ("s-signal.svg", "04 · SIGNAL", "SEND A SIGNAL ACROSS", "I read everything", 21),
    ]:
        section(name, num, title, sub, seed)
    ticker()
    about()
    stack()
    projects()
    coordinate()
    button("c-github.svg", "gh", "GitHub", "github.com/Xynorash", LILAC)
    button("c-mail.svg", "mail", "Email", "nashtefison@gmail.com", "#ff7a6b")
    button("c-linkedin.svg", "in", "LinkedIn", "nash-tefison", "#4a9ae8")
    button("c-dailydev.svg", "dd", "daily.dev", "xynorash", CYAN)
    button("c-facebook.svg", "fb", "Facebook", "profile", "#6a8ff5")
    footer()
    logo_panel()
    card_panel()


if __name__ == "__main__":
    main()
