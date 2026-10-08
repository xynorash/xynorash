import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/tools/generate-wallpaper.py',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'generate-wallpaper.py — a night sky written as code'),
    cm('#', 'gradient, noise, 4,449 stars and a hand-made PNG'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'renders wallpapers/starry-night-tokyo.png from a seed'),
    kv('language', 'Python 3, standard library only (math, os, random, struct, zlib)'),
    kv('size', '150 lines, one commit (d552dfd, 2026-09-19)'),
    kv('output', '1920x1080 RGB PNG, 1.77 MB, fixed seed 7749'),
    kv('cost', 'about 13 to 14 seconds; 13 of them in one loop'),
    kv('checked here', 'ran it, timed each phase, compared against the shipped PNG'),

    ...sec('why a wallpaper is a program'),
    ...para(
        '#',
        r'The wallpaper is the most visible thing on this desktop and '
        r'it is a binary file, which is the worst kind of thing to '
        r'keep in a repository whose point is reproducibility. A PNG '
        r'in git cannot be diffed, cannot be explained, and cannot '
        r'be recoloured when the theme changes. So the image is '
        r'treated as a build artifact with a recipe: a single file '
        r'of pure Python that can regenerate it, with the palette '
        r'taken from the same Tokyo Night values as the rest of the '
        r'desktop. The two seed-like constants at the top, SEED for '
        r'the sky and W/H for the display, are the interface.'),
    blank,
    ...para(
        '#',
        r'The image is still tracked, deliberately (install.sh '
        r'copies it from the checkout and noctalia’s config points '
        r'at the copy). The script is what makes that binary '
        r'honest: it says how the pixels came to be.'),

    ...sec('the header, and the constraint it states'),
    ...code('python', 'tools/generate-wallpaper.py · header', r'''
"""Generate the starry-night wallpaper. Pure stdlib: zlib + struct write the PNG.

Colours are taken from the Tokyo Night palette so the wallpaper matches the
rest of the desktop. Change SEED for a different sky, W/H for another display.

    ./generate-wallpaper.py > /dev/null && feh wallpapers/starry-night-tokyo.png
"""
import math, os, random, struct, zlib

W, H, SEED = 1920, 1080, 7749
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "wallpapers", "starry-night-tokyo.png")
random.seed(SEED)'''),
    ...para(
        '#',
        r'“Pure stdlib” is the design constraint, and it explains '
        r'almost everything about the shape of the file. There is no '
        r'imaging library, no NumPy, nothing to install on a fresh '
        r'Arch box where Python is whatever came along. The price is '
        r'speed: every pixel is computed in an interpreted loop and '
        r'the PNG container is assembled by hand with struct and '
        r'zlib. The rest of this page is what that choice looks '
        r'like in code, and what it costs.'),
    blank,
    ...para(
        '#',
        r'OUT is computed from __file__, two directories up and then '
        r'into wallpapers/, so the script writes into the checkout '
        r'wherever it is run from. random.seed(SEED) is the '
        r'reproducibility switch: every random draw in the file, '
        r'for noise nodes, stars and dither alike, comes from the '
        r'one seeded generator.'),

    ...sec('the palette'),
    ...code('python', 'tools/generate-wallpaper.py · colours', r'''
STOPS = [(0.00, (0x07, 0x08, 0x0e)),
         (0.38, (0x11, 0x13, 0x1e)),
         (0.70, (0x1a, 0x1b, 0x26)),
         (1.00, (0x25, 0x29, 0x3d))]

STAR_COLS = ([(0xc0, 0xca, 0xf5)] * 5 + [(0xa9, 0xb1, 0xd6)] * 3 +
             [(0x7a, 0xa2, 0xf7)] * 2 +
             [(0x7d, 0xcf, 0xff), (0xbb, 0x9a, 0xf7), (0xe0, 0xaf, 0x68), (0xf7, 0x76, 0x8e)])'''),
    ...para(
        '#',
        r'The docstring claims the colours come from the Tokyo '
        r'Night palette. The repo lets me check that, because '
        r'noctalia’s generated Ghostty theme is tracked '
        r'(home/.config/ghostty/themes/noctalia). Comparing the two:'),
    blank,
    ...pt(
        '#',
        'the background stop',
        r'STOPS at 0.70 is (0x1a, 0x1b, 0x26), which is #1a1b26, and '
        r'the Ghostty theme says background = #1a1b26. Exact match. '
        r'The two stops above it (#07080e, #11131e) are darker than '
        r'any palette entry, and the bottom stop (#25293d) is a '
        r'lighter shade. They are chosen shades in the palette’s '
        r'family, not palette values.'),
    ...pt(
        '#',
        'the stars',
        r'all seven star colours appear in the theme: #c0caf5 is '
        r'the foreground, #a9b1d6 is palette entry 7, #7aa2f7 blue, '
        r'#7dcfff cyan, #bb9af7 purple, #e0af68 yellow, #f7768e '
        r'red. The weights make the sky mostly neutral: of 14 '
        r'entries, 8 are the two near-white colours (57 percent), 2 '
        r'blue (14 percent), and the four accent colours one each '
        r'(7 percent apiece).'),
    ...pt(
        '#',
        'a third place they appear',
        r'greetd’s tuigreet command uses --matrix-colors '
        r'#7dcfff,#7aa2f7,#bb9af7, three of the star colours. The '
        r'login screen and the wallpaper are drawn from the same '
        r'small set.'),

    ...sec('the gradient: one formula for every stop'),
    ...code('python', 'tools/generate-wallpaper.py · grad()', r'''
def grad(v):
    """Smooth vertical gradient. Interpolating every stop avoids the visible
    seam a branch between two ranges would leave."""
    for i in range(len(STOPS) - 1):
        v0, c0 = STOPS[i]
        v1, c1 = STOPS[i + 1]
        if v <= v1:
            t = (v - v0) / (v1 - v0)
            t = t * t * (3 - 2 * t)
            return tuple(c0[k] + (c1[k] - c0[k]) * t for k in range(3))
    return STOPS[-1][1]'''),
    ...para(
        '#',
        r'The docstring gives the reason for the shape, in the '
        r'author’s words: interpolating every stop avoids the '
        r'visible seam a branch between two ranges would leave. '
        r'The loop finds the segment that contains v, rescales v '
        r'to t in [0, 1] within it, and then applies smoothstep, '
        r't*t*(3-2t). Smoothstep has zero slope at both ends, so at '
        r'each stop the colour arrives and leaves flat, and the '
        r'sky has no visible crease where one segment ends and the '
        r'next begins.'),
    blank,
    ...para(
        '#',
        r'A side effect is that the brightness is closer to a '
        r'staircase of plateaus joined by gentle ramps than to one '
        r'straight slope. That is also where the cost of the dark '
        r'palette shows. The red channel moves only from 7 to 37 '
        r'from the top of the screen to the bottom, about 30 '
        r'levels over 1,080 rows, so on an 8-bit display a smooth '
        r'gradient is made of wide flat bands. The next sections '
        r'are largely about hiding that.'),

    ...sec('value noise that tiles'),
    ...code('python', 'tools/generate-wallpaper.py · the noise grid', r'''
def make_grid(gw, gh):
    """Value-noise grid whose last row/column repeat the first, so sampling
    wraps without a seam."""
    g = [[random.random() for _ in range(gw)] for _ in range(gh)]
    for row in g:
        row.append(row[0])
    g.append(list(g[0]))
    return g


def sample(grid, gw, gh, x, y):
    x -= math.floor(x)
    y -= math.floor(y)
    fx, fy = x * gw, y * gh
    x0, y0 = int(fx), int(fy)
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = grid[y0][x0] + (grid[y0][x0 + 1] - grid[y0][x0]) * tx
    b = grid[y0 + 1][x0] + (grid[y0 + 1][x0 + 1] - grid[y0 + 1][x0]) * tx
    return a + (b - a) * ty'''),
    ...para(
        '#',
        r'This is classic value noise: random numbers on a coarse '
        r'grid, smoothly interpolated in between. Two details '
        r'matter. make_grid copies the first column onto the end of '
        r'each row and the first row onto the end of the grid, so '
        r'the last node equals the first, and sample() starts by '
        r'subtracting floor(x) and floor(y), so any coordinate '
        r'wraps into [0, 1). Together they make the noise periodic '
        r'in both directions. That is not a luxury here: the '
        r'caller asks for coordinates up to 2.2 and 2.5, and '
        r'without a periodic grid the wrap would show as a visible '
        r'seam in the middle of the sky.'),
    blank,
    ...para(
        '#',
        r'sample() also smoothsteps the fractional position (tx and '
        r'ty), the same trick as in the gradient, which removes the '
        r'grid-aligned look that plain bilinear interpolation '
        r'gives value noise.'),

    ...sec('four octaves that sum to one'),
    ...code('python', 'tools/generate-wallpaper.py · fbm()', r'''
OCT = [(make_grid(g, gh), g, gh, amp)
       for g, gh, amp in ((4, 3, 0.50), (9, 5, 0.27), (19, 11, 0.15), (37, 21, 0.08))]


def fbm(x, y):
    return sum(sample(gr, gw, gh, x, y) * a for gr, gw, gh, a in OCT)'''),
    ...para(
        '#',
        r'Fractal Brownian motion here is four layers of that '
        r'noise. The grids are 4x3, 9x5, 19x11 and 37x21 cells, '
        r'each roughly twice the frequency of the one before, and '
        r'the weights are 0.50, 0.27, 0.15 and 0.08. They sum to '
        r'exactly 1.00, so fbm() always returns a value in [0, 1], '
        r'and the callers can reason about ranges without '
        r'measuring. From the second octave on the cell counts are '
        r'close to 16:9, so cells are roughly square on a '
        r'widescreen picture. The first octave, 4x3, is the '
        r'exception, and it carries half the weight.'),

    ...sec('the per-pixel pass'),
    ...code('python', 'tools/generate-wallpaper.py · the sky (trimmed)', r'''
buf = bytearray(W * H * 3)
for y in range(H):
    v = y / (H - 1)
    br, bg, bb = grad(v)
    row = y * W * 3
    for x in range(W):
        u = x / (W - 1)
        d = (u * 0.48 + 0.26) - v                      # diagonal galactic band
        core = math.exp(-(d * d) / 0.0075)
        wing = math.exp(-(d * d) / 0.045)
        dust = 0.55 + 0.45 * fbm(u * 2.2 + 0.3, v * 2.2)
        band = (core * 0.72 + wing * 0.38) * dust
        n = fbm(u * 1.3, v * 1.3) - 0.5
        r, g, b = br + band * 30 + n * 4, bg + band * 33 + n * 4, bb + band * 58 + n * 7
        cx, cy = u - 0.5, v - 0.5
        vig = 1.0 - 0.26 * (cx * cx * 1.1 + cy * cy * 1.3)
        i = row + x * 3
        buf[i] = max(0, min(255, int(r * vig + random.random() * 1.6)))
        buf[i + 1] = max(0, min(255, int(g * vig + random.random() * 1.6)))
        buf[i + 2] = max(0, min(255, int(b * vig + random.random() * 1.6)))'''),
    ...para(
        '#',
        r'This is the loop that costs 13 seconds. Walking through '
        r'it:'),
    blank,
    ...pt(
        '#',
        'the band is a line and two Gaussians',
        r'd is the vertical offset, in normalised units, from the '
        r'line v = 0.48u + 0.26. That line runs from 26 percent of '
        r'the height at the left edge to 74 percent at the right, '
        r'so the Milky Way descends diagonally across the screen. '
        r'core uses exp(-d*d / 0.0075), a Gaussian with a standard '
        r'deviation of about 0.061, roughly 66 pixels of height. '
        r'wing uses 0.045, about 0.15 or 162 pixels. A narrow '
        r'bright core inside a wide soft wing is what makes the '
        r'band look like a glow and not like a stripe.'),
    ...pt(
        '#',
        'dust',
        r'0.55 + 0.45 * fbm(...) is in [0.55, 1.0] and multiplies '
        r'the band, so the glow is patchy: dark lanes cut across '
        r'it where the noise is low. The 2.2 scale means the dust '
        r'texture is finer than the background mottling.'),
    ...pt(
        '#',
        'the colour of the band',
        r'it adds (30, 33, 58) times a brightness of up to 1.1, '
        r'(core 0.72 plus wing 0.38 at the centre of the band). '
        r'Blue gets the biggest push, so the glow is a cool blue '
        r'haze over a neutral dark base. The background mottling n '
        r'runs from -0.5 to 0.5 and is multiplied by 4 for red and '
        r'green and by 7 for blue, so it moves the result by at '
        r'most about 2 levels in red and green and 3.5 in blue, '
        r'a faint variation to break up the flat gradient.'),
    ...pt(
        '#',
        'the vignette',
        r'1 - 0.26 * (cx*cx*1.1 + cy*cy*1.3) darkens toward the '
        r'corners. At a corner, cx and cy are both 0.5, which '
        r'gives 1 - 0.26*0.6 = 0.844: the corners sit at 84 '
        r'percent of the centre brightness. The weights 1.1 and '
        r'1.3 make the falloff a little stronger vertically than '
        r'horizontally.'),
    ...pt(
        '#',
        'the dither',
        r'int(r * vig + random.random() * 1.6). A uniform random '
        r'number in [0, 1.6) is added just before truncation to '
        r'an integer. This is dithering: instead of every pixel '
        r'in a stretch rounding to the same level, they round up '
        r'with a probability proportional to the fraction, and '
        r'the flat bands dissolve into grain. The amplitude is a '
        r'bit larger than the 1.0 a textbook truncation dither '
        r'needs, so it also adds a slight grain on top.'),

    ...sec('what the dither buys, and what it costs'),
    ...para(
        '#',
        r'I measured this by running a copy of the script with the '
        r'dither multiplied by zero, keeping the random draws '
        r'identical so the stars stay put. Down one column near the '
        r'left edge (x = 5) across the 1080 rows:'),
    blank,
    ...pt(
        '#',
        'without dither',
        r'175 distinct colours, a longest run of 79 identical '
        r'pixels, mean run 5.6. The file is 255,021 bytes.'),
    ...pt(
        '#',
        'with dither (the real script)',
        r'409 distinct colours, a longest run of 5, mean run 1.1. '
        r'The file is 1,856,015 bytes.'),
    blank,
    ...para(
        '#',
        r'So the grain takes the banding from visible steps up to '
        r'79 rows tall down to nothing longer than 5 rows, and it '
        r'costs a factor of 7.3 in file size. A PNG compresses '
        r'runs; random noise has none. That is a trade made with '
        r'open eyes, because an 8-bit dark gradient is exactly the '
        r'case where banding is the most visible defect and a '
        r'megabyte of disk is the cheapest thing on the machine. '
        r'It is also why the PNG compresses only 3.35 to 1 '
        r'(6,221,880 raw bytes in, about 1.86 MB out) despite '
        r'being mostly smooth sky.'),

    ...sec('stars: splat, then a power law'),
    ...code('python', 'tools/generate-wallpaper.py · splat()', r'''
def splat(cx, cy, rad, col, power):
    x0, x1 = max(0, int(cx - rad) - 1), min(W - 1, int(cx + rad) + 1)
    y0, y1 = max(0, int(cy - rad) - 1), min(H - 1, int(cy + rad) + 1)
    for yy in range(y0, y1 + 1):
        for xx in range(x0, x1 + 1):
            dx, dy = xx - cx, yy - cy
            dd = math.sqrt(dx * dx + dy * dy)
            if dd > rad:
                continue
            f = (1.0 - dd / rad) ** 2 * power
            i = (yy * W + xx) * 3
            for k in range(3):
                buf[i + k] = min(255, int(buf[i + k] + col[k] * f))'''),
    ...para(
        '#',
        r'One primitive draws every star. splat() takes a centre, '
        r'a radius, a colour and a power, clamps a bounding box to '
        r'the image, and for each pixel within the radius adds the '
        r'colour times (1 - distance/radius) squared times power. '
        r'The squared falloff gives a bright centre and a soft '
        r'edge. The addition saturates at 255, so overlapping '
        r'stars never wrap around to black. It is additive on top '
        r'of the sky, so a star adds light instead of replacing '
        r'it, which is how real stars behave against a glowing '
        r'background.'),
    ...code('python', 'tools/generate-wallpaper.py · the dense field', r'''
# Dense field, concentrated along the band; brightness follows a power law so
# most stars are faint and a few stand out.
for _ in range(9000):
    x, y = random.random() * W, random.random() * H
    u, v = x / W, y / H
    d = (u * 0.48 + 0.26) - v
    if random.random() > 0.22 + 0.78 * math.exp(-(d * d) / 0.040):
        continue
    mag = random.random() ** 2.6
    splat(x, y, 0.75 + mag * 1.9, random.choice(STAR_COLS), 0.45 + mag * 0.55)'''),
    ...para(
        '#',
        r'The comment states the two ideas, concentration along '
        r'the band and a brightness power law, and the numbers '
        r'implement them.'),
    blank,
    ...pt(
        '#',
        'rejection sampling for the band',
        r'9,000 candidate positions are drawn uniformly. Each '
        r'survives with probability 0.22 + 0.78*exp(-d*d/0.040): '
        r'a 22 percent floor far from the band and 100 percent on '
        r'its axis, with a Gaussian of deviation about 0.14 in '
        r'between. I counted the survivors: 4,449 of 9,000, so '
        r'the sky has 4,449 ordinary stars, denser along the '
        r'diagonal.'),
    ...pt(
        '#',
        'the power law',
        r'mag = random() ** 2.6 piles the values near zero. The '
        r'median star has mag = 0.5 ** 2.6 = 0.165, which gives '
        r'it a radius of 0.75 + 1.9*0.165 = 1.06 pixels and a '
        r'power of 0.54, a faint dot. Only the rare high draws '
        r'reach the maximum radius of 2.65 pixels at full power. '
        r'Most stars are barely there and a few stand out, which '
        r'is the comment’s “power law” in one line.'),
    ...pt(
        '#',
        'colour by chance',
        r'random.choice(STAR_COLS) picks from the weighted list '
        r'above, so the 14-entry list is the colour distribution.'),

    ...sec('showpiece stars'),
    ...code('python', 'tools/generate-wallpaper.py · halo and spikes', r'''
# A few showpiece stars with a halo and diffraction spikes.
for _ in range(22):
    x, y = random.random() * W, random.random() * H
    col = random.choice(STAR_COLS)
    splat(x, y, 11 + random.random() * 15, col, 0.10)
    for L in range(1, 13):
        f = (1 - L / 13) ** 2 * 0.22
        for dx, dy in ((L, 0), (-L, 0), (0, L), (0, -L)):
            xx, yy = int(x + dx), int(y + dy)
            if 0 <= xx < W and 0 <= yy < H:
                i = (yy * W + xx) * 3
                for k in range(3):
                    buf[i + k] = min(255, int(buf[i + k] + col[k] * f))'''),
    ...para(
        '#',
        r'Twenty-two stars get a special treatment. A very faint '
        r'halo (radius 11 to 26 pixels, power 0.10) is splatted '
        r'first. Then four arms of 12 pixels extend along the axes '
        r'with the falloff (1 - L/13) squared times 0.22. The '
        r'first pixel of an arm gets 18.7 percent of the star '
        r'colour, the last about 0.13 percent. The arms are '
        r'drawn by hand, pixel by pixel, because splat() makes '
        r'discs and a diffraction spike is a line.'),
    blank,
    ...para(
        '#',
        r'The spikes are horizontal and vertical only, and the '
        r'bounds check on every pixel is what lets a star sit '
        r'near the edge of the image without raising an error.'),

    ...sec('writing a PNG by hand'),
    ...code('python', 'tools/generate-wallpaper.py · the container', r'''
raw = bytearray()
for y in range(H):
    raw.append(0)                                       # filter type 0
    raw += buf[y * W * 3:(y + 1) * W * 3]


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))


png = (b"\x89PNG\r\n\x1a\n" +
       chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) +
       chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
       chunk(b"IEND", b""))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as fh:
    fh.write(png)
print(f"wrote {OUT} ({len(png) / 1024 / 1024:.2f} MB)")'''),
    ...para(
        '#',
        r'A PNG is a fixed signature followed by chunks, and this '
        r'is all of it. Each chunk is a 4-byte big-endian length, '
        r'a 4-byte tag, the data, and a CRC-32 of the tag and '
        r'data. The IHDR data is packed with ">IIBBBBB": width, '
        r'height, bit depth 8, colour type 2 (truecolour RGB), '
        r'then compression, filter and interlace methods all '
        r'zero. IDAT is the zlib-compressed pixel stream at level '
        r'9, the maximum. IEND is an empty chunk.'),
    blank,
    ...para(
        '#',
        r'The scanline prefix is the fiddly part. Every row of '
        r'IDAT begins with a filter-type byte; the code writes 0, '
        r'meaning no filtering, which is why the comment is there '
        r'and why the raw stream is 6,221,880 bytes: '
        r'1920*1080*3 plus 1,080 filter bytes. A smarter encoder '
        r'would pick a per-row filter. With the dither noise '
        r'above I would not expect it to help much, but I did not '
        r'try. Writing the whole stream as one IDAT chunk is '
        r'legal, if unusual.'),

    ...sec('measurements'),
    ...pt(
        '#',
        'determinism',
        r'a plain run and a run of an instrumented copy on this '
        r'machine (Python 3.13) produced byte-identical files. One '
        r'seed gives one sky.'),
    ...pt(
        '#',
        'time',
        r'a first run took 13.0 seconds total; a timed copy '
        r'measured the setup at under 0.01 s, the per-pixel pass '
        r'at 13.0 s, all star drawing at 0.07 s and PNG '
        r'encoding at 1.1 s. Nearly everything is in the sky '
        r'loop, which makes 8 sample() calls for each of its '
        r'2,073,600 pixels, 16.6 million in total.'),
    ...pt(
        '#',
        'size',
        r'1,856,015 bytes from a fresh run, 1,856,346 for the '
        r'file in the repo, both reported by the script as 1.77 '
        r'MB (mebibytes, despite the label).'),
    ...pt(
        '#',
        'syntax',
        r'the file parses cleanly. The repo has no tests for it.'),

    ...sec('the shipped image is not quite this script’s output'),
    ...para(
        '#',
        r'A reproducible build should reproduce, so I compared '
        r'the fresh PNG with wallpapers/starry-night-tokyo.png by '
        r'decoding both to raw pixels. The headers are identical '
        r'and 99.987 percent of the pixels are too. What differs '
        r'is 271 pixels out of 2,073,600, and they are not '
        r'scattered. All of them lie within 2.24 pixels of the '
        r'centres of the 22 showpiece stars (I instrumented a '
        r'copy to print where they are). At those spots the '
        r'committed image has bright cores, several pixels at full '
        r'white, and the script as committed draws only a faint '
        r'halo and the spikes, so the star centres stay dim.'),
    blank,
    ...para(
        '#',
        r'So the file on disk was rendered by a slightly different '
        r'revision of the code, one that also painted a small '
        r'core on each showpiece star, or it was touched up '
        r'afterwards. Both files arrived in the same commit, so '
        r'the history cannot say which. I tried adding a small '
        r'additive disc at each star as a guess; it did not '
        r'reproduce the pixels, so I do not know what code drew '
        r'them. The practical consequence is small, since the '
        r'wallpaper looks as intended, but the claim in the '
        r'docstring that the file is generated by this script is '
        r'true to 99.987 percent, not 100.'),

    ...sec('where it is used'),
    ...pt(
        '#',
        'install.sh',
        r'copies wallpapers/*.png into ~/Pictures/Wallpapers with '
        r'cp -n. Because of -n, regenerating the image does not '
        r'update an existing copy on a re-run.'),
    ...pt(
        '#',
        'noctalia/config.toml',
        r'its wallpaper.default path points at '
        r'/home/xynorash/Pictures/Wallpapers/starry-night-tokyo.png.'),
    ...pt(
        '#',
        'the usage line',
        r'the docstring suggests running the script and then '
        r'opening the result with feh. feh is in neither package '
        r'list, and the two halves of that line need different '
        r'working directories: ./generate-wallpaper.py works from '
        r'tools/, while wallpapers/starry-night-tokyo.png is '
        r'relative to the repo root. The script is executable '
        r'(mode 755), so it can also be run by its path from '
        r'anywhere.'),
    ...pt(
        '#',
        'python',
        r'no package list names Python; it must arrive as '
        r'another package’s dependency.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'resolution only half scales',
        r'the docstring says to change W/H for another display. The '
        r'noise, the gradient and the band are all in normalised '
        r'coordinates, so the composition scales. But the stars '
        r'are in pixels and their count is fixed at 9,000 + 22, '
        r'so at 4K the sky would be sparser and the stars '
        r'smaller. I did not try it.'),
    ...pt(
        '#',
        'slow by construction',
        r'the sky loop is 16.6 million Python calls. The '
        r'background term n uses the same noise at a scale where '
        r'the finest octave has a cell of about 40 pixels; '
        r'computing it once per small block and interpolating '
        r'would probably save a large part of the time. That is a '
        r'hypothesis, not a measurement.'),
    ...pt(
        '#',
        'no command line',
        r'seed, size and output are constants in the file, so '
        r'making a second sky means editing it. A small argparse '
        r'wrapper would be the first improvement.'),
    ...pt(
        '#',
        'Python version',
        r'I ran it on 3.13 only. The seeded generator is stable '
        r'across modern versions, but I did not check others.'),
    ...pt(
        '#',
        'no test',
        r'the checks above are one-off. A test that regenerates '
        r'the image and compares a hash would also have caught the '
        r'star-core difference at the moment it was introduced.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
