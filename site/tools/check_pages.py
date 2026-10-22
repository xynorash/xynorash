"""Check that page code excerpts are verbatim from the real source repo.

usage: check_pages.py <repo_root> <project_prefix> <page.dart>...
"""
import os
import re
import sys

repo, prefix, *files = sys.argv[1:]
bad = 0
for f in files:
    s = open(f).read()
    m = re.search(r"makePage\(\s*'([^']+)'", s)
    if not m:
        print(f, 'NO makePage path'); bad += 1; continue
    path = m.group(1)
    if not path.startswith(prefix + '/'):
        print(f, 'path', path, 'lacks prefix', prefix); bad += 1
    if not os.path.exists(os.path.join(repo, path[len(prefix) + 1:])):
        print(f, 'no such repo file', path); bad += 1
    if len(s.splitlines()) < 60:
        print(f, 'WARN thin page')
    for c in re.finditer(r"\.\.\.code\(\s*'[^']*',\s*r?'([^']+)',\s*r'''(.*?)'''", s, re.S):
        src = c.group(1).split(' · ')[0].strip()
        sp = os.path.join(repo, src)
        if not os.path.exists(sp):
            print(f, 'excerpt file missing:', src); bad += 1; continue
        have = set(l.strip() for l in open(sp, errors='ignore').read().splitlines())
        for ln in c.group(2).strip('\n').splitlines():
            if ln.strip() and ln.strip() not in ('...', '…', '# ...', '-- ...', '// ...') \
                    and ln.strip() not in have:
                print(f, 'NOT VERBATIM in', src, ':', ln[:90]); bad += 1; break
    if re.search(r"Span\(\s*''", s):
        print(f, 'empty span'); bad += 1
print('FAILURES:', bad)
sys.exit(1 if bad else 0)
