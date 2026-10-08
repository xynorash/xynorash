import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.local/bin/intl-speedtest',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'intl-speedtest — is it my machine or my line'),
    cm('#', 'a 22-line instrument built on fast.com’s servers'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'prints download speed to the servers fast.com picks'),
    kv('language', 'Python 3, standard library, curl as the data mover'),
    kv('size', '22 lines, one commit: d552dfd (2026-09-19)'),
    kv('used by', 'nothing in the repo; a tool to run by hand'),
    kv('checked here', 'the scraping chain against the live site, the maths by hand'),

    ...sec('the question it answers'),
    ...para(
        '#',
        r'Most of this repository is about making one machine fast '
        r'for games. A speed test is the odd one out: it measures '
        r'the line, not the machine. Its docstring gives the use '
        r'case in three sentences: “Local vs international '
        r'download speed, using Netflix’s fast.com servers. Run it '
        r'on any Linux (e.g. an Omarchy live USB) at the same hour '
        r'to compare. Pause Steam first, or its traffic will share '
        r'the line with the test.”'),
    blank,
    ...para(
        '#',
        r'That is an experiment design in miniature. The variable '
        r'is the operating system (this Arch install against a live '
        r'USB of Omarchy, the distribution whose tuning the repo '
        r'borrows from in several places); everything else is held '
        r'still, the time of day by instruction, the competing '
        r'traffic by asking you to pause Steam. If both systems '
        r'see the same numbers, the install is not the cause of '
        r'a slow download. The repo does not say which problem '
        r'prompted it. My inference is the long-distance '
        r'download slowness that the network tuning file describes.'),

    ...sec('the evidence around it'),
    ...para(
        '#',
        r'Three other files in the repo describe the same line, and '
        r'together they make the tool’s purpose readable:'),
    ...pt(
        '#',
        'system/etc/sysctl.d/99-network-tuning.conf',
        r'calls the WAN “PPPoE, MTU 1492” and sizes socket buffers '
        r'for “high bandwidth-delay paths (e.g. ~100 Mbps at 200+ ms '
        r'to Europe/Google)”.'),
    ...pt(
        '#',
        'home/.local/share/Steam/steam_dev.cfg',
        r'three undocumented Steam settings for the download client, '
        r'added in the commit that the message calls “the Steam '
        r'download tweaks”.'),
    ...pt(
        '#',
        'the bar',
        r'commit 7569527 (2026-09-21) made the network widget show '
        r'live download speed. The bar watches continuously; this '
        r'script measures on demand, against a known reference.'),
    blank,
    ...para(
        '#',
        r'Read as a set: a line with a long round trip to far '
        r'servers, a download client tuned to open more connections '
        r'and a way to check whether any of it helps. The word '
        r'“international” in the docstring is the user’s '
        r'framing. The script itself prints only a city, a country '
        r'and a speed, and never classifies anything as local or '
        r'international; you compare the rows.'),

    ...sec('step one: borrow the browser’s token'),
    ...code('python', 'home/.local/bin/intl-speedtest · docstring and discovery', r'''
#!/usr/bin/env python3
"""Local vs international download speed, using Netflix's fast.com servers.
Run it on any Linux (e.g. an Omarchy live USB) at the same hour to compare.
Pause Steam first, or its traffic will share the line with the test."""
import json, re, subprocess, time, urllib.request

def get(url):
    return urllib.request.urlopen(url, timeout=15).read().decode()

js = re.search(r'app-[a-z0-9]+\.js', get("https://fast.com")).group(0)
token = re.search(r'token:"([A-Za-z0-9]+)"', get(f"https://fast.com/{js}")).group(1)
targets = json.loads(get(f"https://api.fast.com/netflix/speedtest/v2?https=true&token={token}&urlCount=5"))["targets"]'''),
    ...para(
        '#',
        r'fast.com is a page whose JavaScript asks an API for a '
        r'list of test servers, and the API wants a token that '
        r'the page’s own script contains. The script does what the '
        r'browser does, by hand and in three requests. First '
        r'fetch the page and find the name of its bundle, which is '
        r'app- followed by a hash. Then fetch the bundle and '
        r'pull the token out of it with a regular expression. Then '
        r'ask the API for five targets over HTTPS.'),
    blank,
    ...para(
        '#',
        r'This is the fragile part. It depends on the bundle name '
        r'pattern and on the token being written as token:"..." '
        r'in the source. A redesign of the site would break it, '
        r'and there is no error handling; a failed regular '
        r'expression raises on .group() and the script dies with a '
        r'traceback. I checked the chain on 2026-10-08 from the '
        r'sandbox where I wrote this page: the page contained a '
        r'matching bundle name, the bundle contained a matching '
        r'token, and the API answered with a client object and five '
        r'targets. Each target had a name, a url, and a location with '
        r'city and country, and each url contained the /speedtest? '
        r'fragment that the next step rewrites. I downloaded '
        r'nothing from the targets. The servers returned were '
        r'all in the US and under nflxvideo.net, which says '
        r'where my sandbox is, not where yours is: the API '
        r'picks servers near the caller.'),

    ...sec('step two: pull bytes, count them'),
    ...code('python', 'home/.local/bin/intl-speedtest · the measurement', r'''
print(f"{'server':34} {'speed':>10}")
for t in targets:
    url = t["url"].replace("/speedtest?", "/speedtest/range/0-52428800?")
    procs = [subprocess.Popen(["curl", "-s", "-o", "/dev/null", "--max-time", "15",
                               "-w", "%{size_download}", url], stdout=subprocess.PIPE) for _ in range(4)]
    t0 = time.time()
    got = sum(int(p.communicate()[0] or 0) for p in procs)
    loc = f'{t["location"]["city"].title()}, {t["location"]["country"]}'
    print(f"{loc:34} {got * 8 / (time.time() - t0) / 1e6:7.1f} Mbps")'''),
    ...para(
        '#',
        r'One target at a time, so the servers never compete with '
        r'each other. For each, the script rewrites the URL so '
        r'that the server returns a byte range (0-52428800, which '
        r'is 50 MiB give or take one byte) and starts four '
        r'curl processes on it at once. Each curl writes its '
        r'body to /dev/null and, through -w, prints only the '
        r'number of bytes it received. The script adds the four '
        r'numbers, multiplies by 8 for bits, divides by the '
        r'elapsed seconds and by 10^6 for megabits per second.'),
    blank,
    ...pt(
        '#',
        'why four connections',
        r'the file gives no reason. Elementary arithmetic gives one. '
        r'A single TCP stream cannot go faster than its window '
        r'divided by the round-trip time. A 256 KiB window at '
        r'200 ms is 10.5 Mbps; four of them are 42 Mbps. On a long '
        r'path, parallel streams are how a browser fills the line, '
        r'and the settings in steam_dev.cfg are, judging by their '
        r'names, about the same thing for Steam. This is a '
        r'calculation, not a measurement of this line.'),
    ...pt(
        '#',
        'why --max-time 15',
        r'it caps the cost of a bad server. And it matters for '
        r'the maths below: curl still prints the bytes received '
        r'when it is stopped by the time limit. I confirmed that '
        r'against a local slow server: with a one second limit it '
        r'exited with status 28 and still wrote the byte count.'),
    ...pt(
        '#',
        'why int(... or 0)',
        r'communicate returns bytes. int accepts bytes, which I '
        r'checked, and an empty answer (curl failed before any '
        r'data) becomes 0 instead of an exception.'),
    ...pt(
        '#',
        'where t0 sits',
        r'the timer starts after the four processes are launched, '
        r'so process creation is not counted, but the TCP and TLS '
        r'handshakes and slow start are. On a long path those '
        r'are a real share of a short test.'),

    ...sec('what the numbers mean'),
    ...para(
        '#',
        r'Four streams of 50 MiB is 209,715,200 bytes per target, '
        r'or 1.68 gigabits. Dividing by a line speed gives the time '
        r'it would take to finish:'),
    blank,
    plain('    50 Mbps   33.6 s    (cut off at 15 s)'),
    plain('   100 Mbps   16.8 s    (cut off at 15 s)'),
    plain('   200 Mbps    8.4 s'),
    plain('   500 Mbps    3.4 s'),
    plain('  1000 Mbps    1.7 s'),
    blank,
    ...para(
        '#',
        r'Two consequences, both from arithmetic. On a line near '
        r'the ~100 Mbps that the sysctl file mentions, every '
        r'target hits the 15 second cap, so the result is the '
        r'average over a 15 second window that includes the ramp '
        r'up, which is a fair thing to compare between two '
        r'systems. And on a gigabit line the download would be '
        r'over in under two seconds, where connection setup is '
        r'a large part of the time; the tool would understate '
        r'such a line. It was written for the first case.'),
    blank,
    ...para(
        '#',
        r'The sequential design has a cost: five targets at up to '
        r'15 seconds each is up to 75 seconds of full-line '
        r'traffic, which is why the docstring says to pause Steam '
        r'first.'),

    ...sec('limits'),
    ...pt(
        '#',
        'download only',
        r'there is no upload or latency measurement. A path that '
        r'is fast to download and slow to answer would look healthy.'),
    ...pt(
        '#',
        'depends on a third party',
        r'the API, the token scheme and the choice of servers are '
        r'Netflix’s. The tool measures the path to Netflix’s '
        r'caches, which is a proxy for the path to Steam’s.'),
    ...pt(
        '#',
        'no repetition',
        r'one pass per server, no median, no warm-up. The '
        r'instruction to run it at the same hour is the only '
        r'control for variance.'),
    ...pt(
        '#',
        'no error handling',
        r'a network error raises through the whole script. For a '
        r'tool run by hand once or twice, that is a reasonable '
        r'price for 22 lines.'),
    ...pt(
        '#',
        'the default user agent',
        r'urllib announces itself as Python. The three requests '
        r'worked from my sandbox with it, but there is no '
        r'guarantee for another network.'),
    ...pt(
        '#',
        'unreferenced',
        r'nothing in install.sh, the README or the Hyprland config '
        r'mentions the script. It is linked into ~/.local/bin '
        r'with everything else under home/, and found only by '
        r'knowing it is there.'),

    ...sec('what to take from it'),
    ...para(
        '#',
        r'A good diagnostic is small enough to read in one '
        r'sitting, and has its experimental protocol written '
        r'where the code is. The docstring’s second and third '
        r'sentences are not decoration; they are what makes two '
        r'runs on two systems comparable. If I were extending it, '
        r'I would add a median over several passes and a flag for '
        r'the byte range, and leave the structure alone.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
