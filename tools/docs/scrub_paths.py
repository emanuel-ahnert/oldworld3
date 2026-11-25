"""Keeps machine-specific paths out of the generated-asset records.

    python3 tools/docs/scrub_paths.py

The gen3d client writes each job's absolute folder on the GPU box (`server_dir`) next to its
downloads (game_src/raw/**/*.json, spike/**/*.json), and the motion reports (game_src/motion/*/report.json)
name absolute files there too. Only the last two parts identify them (`<date>/<job>`,
`<batch>/<clip>.npy`); this keeps those and drops the rest, so no server path ends up in the
repository. tools/docs/manifest.py applies the same rule. Where the archive lives is in
design/local/gen3d-access.md (not in the repository).
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KEYS = ("server_dir", "file")


def relative(p):
    """An absolute path -> its last two parts; anything else unchanged."""
    if isinstance(p, str) and p.startswith("/"):
        return "/".join(p.rstrip("/").split("/")[-2:])
    return p


def scrub(x):
    if isinstance(x, dict):
        return {k: (relative(v) if k in KEYS else scrub(v)) for k, v in x.items()}
    if isinstance(x, list):
        return [scrub(v) for v in x]
    return x


if __name__ == "__main__":
    changed = 0
    for f in sorted([*(ROOT / "game_src").rglob("*.json"), *(ROOT / "spike").rglob("*.json")]):
        text = f.read_text()
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            continue
        new = scrub(data)
        if new != data:
            f.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
            changed += 1
    print(f"scrubbed {changed} files")
