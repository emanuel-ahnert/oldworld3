"""A listening page for a batch of generated takes (music from ACE-Step, sounds from Stable
Audio on the GPU box): every <name>_<take>.flac/.wav in a folder, grouped by name, with its
prompt (from the .json next to it), as compressed copies for the browser.

    python3 tools/audio/listen.py <folder>     -> <folder>/listen.html (open it in a browser)

Tell Claude which takes to keep ("grassland 2, fight 1")."""
import html
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

folder = Path(sys.argv[1])
groups = defaultdict(list)
for f in sorted(folder.iterdir()):
    m = re.match(r"(.+)_(\d+)\.(flac|wav)$", f.name)
    if not m:
        continue
    ogg = f.with_suffix(".listen.ogg")
    if not ogg.exists():
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(f), "-c:a", "libvorbis", "-q:a", "5", str(ogg)], check=True)
    meta = {}
    if f.with_suffix(".json").exists():
        meta = json.loads(f.with_suffix(".json").read_text())
    groups[m.group(1)].append((int(m.group(2)), ogg.name, meta))

rows = []
for name, takes in groups.items():
    prompt = html.escape(str(takes[0][2].get("caption", takes[0][2].get("prompt", ""))))
    players = "".join(
        f'<div class="take"><b>{n}</b><audio controls preload="none" src="{html.escape(src)}"></audio></div>'
        for n, src, _ in sorted(takes))
    rows.append(f'<section><h2>{html.escape(name)}</h2><p>{prompt}</p>{players}</section>')
page = f"""<!doctype html><meta charset="utf-8"><title>Takes: {html.escape(folder.name)}</title>
<style>body{{font:15px system-ui;background:#1b1712;color:#eee6d8;max-width:900px;margin:24px auto;padding:0 16px}}
h2{{color:#f2cc73;margin:28px 0 4px}}p{{color:#b8ae9c;margin:0 0 10px}}
.take{{display:flex;align-items:center;gap:12px;margin:6px 0}}audio{{width:100%}}</style>
<h1>Takes: {html.escape(folder.name)}</h1>
<p>Play them, then tell Claude the numbers to keep per name.</p>
{''.join(rows)}"""
(folder / "listen.html").write_text(page)
print(folder / "listen.html", sum(len(t) for t in groups.values()), "takes")
