"""Generates game/scripts/player/ability_text.gd from design/classes.md: the "Real time" column
of each class's ability table becomes the tooltip text, passives are listed per class.

python3 tools/docs/ability_text.py
"""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
md = (root / "design/classes.md").read_text()
CLASSES = ["Warrior", "Mage", "Rogue", "Priest", "Paladin", "Warlock", "Hunter", "Shaman", "Druid"]
cls = None
header = None
text = {}
passives = {}
for line in md.splitlines():
    h = re.match(r"^#{2,4} .*?\b(" + "|".join(CLASSES) + r")\b", line)
    if h:
        cls = h.group(1).lower()
        header = None
        continue
    if not line.startswith("|") or cls is None:
        if not line.startswith("|"):
            header = None
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if header is None:
        header = cells
        continue
    if set("".join(cells)) <= set("-: "):
        continue
    if "Real time" not in header or not cells[0].isdigit():
        continue
    name_col = 1
    name = re.sub(r"\*\*|\(.*?\)", "", cells[name_col]).strip()
    desc = cells[header.index("Real time")].replace('"', "'")  # TEXT values are written in double quotes
    if "passive" in cells[name_col].lower():
        passives.setdefault(cls, []).append([int(cells[0]), name, desc])
    else:
        text[f"{cls}:{name}"] = desc



def split_top(s):
    """Splits at commas outside parentheses."""
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


# Section 5: one row per class, "Name (level, text)" items.
for line in md.splitlines():
    m = re.match(r"^\| (Priest|Paladin|Warlock|Hunter|Shaman|Druid) \|[^|]*\| (.*) \|$", line)
    if not m:
        continue
    c = m.group(1).lower()
    items = []
    for it in split_top(m.group(2)):
        items += [x.strip() for x in it.replace("; passive ", "|passive ").split("|")]
    for item in items:
        passive = item.startswith("passive ")
        item = item.removeprefix("passive ").strip()
        item = item[:1].upper() + item[1:]
        mm = re.match(r"^([A-Z][A-Za-z' ]+?)\s*(?:\((.*?)\))?\s*(?::\s*(.*))?$", item)
        if not mm:
            continue
        name, paren, after = mm.group(1).strip(), mm.group(2) or "", mm.group(3) or ""
        level = 1
        pm = re.match(r"^(\d+)(?:,\s*(.*))?$", paren)
        if pm:
            level = int(pm.group(1))
            paren = pm.group(2) or ""
        desc = (paren + ("; " if paren and after else "") + after).strip()
        desc = desc[:1].upper() + desc[1:]
        if passive:
            passives.setdefault(c, []).append([level, name, desc])
        elif desc:
            text[f"{c}:{name}"] = desc

# Rogue passives paragraph: **Name** (level): text.
for m in re.finditer(r"\*\*([A-Z][A-Za-z ]+)\*\* \((\d+)\): ([^*]+?)(?= \*\*|$)", md.split("## 4. Rogue")[1].split("## 5.")[0].replace("\n", " ")):
    passives.setdefault("rogue", []).append([int(m.group(2)), m.group(1), m.group(3).strip()])

out = ['class_name AbilityText', 'extends RefCounted',
       '## Ability descriptions for tooltips and the spell book, generated from design/classes.md',
       '## by tools/docs/ability_text.py (don\'t edit by hand).', '', 'const TEXT := {']
for k, v in sorted(text.items()):
    out.append(f'\t"{k}": "{v}",')
out += ['}', '', '## class -> [[level, name, text]]', 'const PASSIVES := {']
for k, v in passives.items():
    out.append(f'\t"{k}": {json.dumps(v, ensure_ascii=False)},')
out += ['}', '', '',
        '## Tooltip: name and key, level, cost and cooldown, what it does.',
        'static func describe(cls: String, a: Dictionary) -> String:',
        '\tvar cost := ""',
        '\tfor r in ["rage", "mana", "energy"]:',
        '\t\tif int(a.get(r, 0)) > 0:',
        '\t\t\tcost = "%d %s" % [int(a[r]), r]',
        '\tvar cd := float(a.get("cd", 0.0))',
        '\tvar parts := ["Level %d" % int(a.level)]',
        '\tif cost != "":',
        '\t\tparts.append(cost)',
        '\tif cd > 0.0:',
        '\t\tparts.append(("%d s cooldown" % roundi(cd)) if cd < 60.0 else ("%d min cooldown" % roundi(cd / 60.0)))',
        '\treturn "%s (%d)\\n%s\\n%s" % [a.name, int(a.key), ", ".join(parts), TEXT.get("%s:%s" % [cls, a.name], "")]',
        '']
(root / "game/scripts/player/ability_text.gd").write_text("\n".join(out))
print(len(text), "abilities,", sum(len(v) for v in passives.values()), "passives")
