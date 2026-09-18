#!/usr/bin/env python3
"""Zero-dependency tangle for the pinga blueprint.

Blocks are fenced like:

    ```lang #chunk-name path="src/foo.rs"
    ...code...
    ```

Attributes on the info string:
    path="rel/path"   -> (re)create the file with this block's content
    append="rel/path" -> append this block's content to that file

Blocks apply in document order; the first path= block to a given file wins a
truncate, everything after appends. `python3 tools/tangle.py blueprint.md`.
"""
import pathlib
import re
import sys

FENCE = re.compile(r"^(`{3,})([^\n]*)\n(.*?)^\1[ \t]*$", re.MULTILINE | re.DOTALL)
ATTR = re.compile(r'\b(path|append)\s*=\s*"([^"]+)"')

def tangle(doc: pathlib.Path) -> None:
    text = doc.read_text()
    seen = set()
    out = {}
    for m in FENCE.finditer(text):
        attrs = dict(ATTR.findall(m.group(2)))
        rel = attrs.get("path") or attrs.get("append")
        if not rel:
            continue
        body = m.group(3)
        if not body.endswith("\n"):
            body += "\n"
        target = pathlib.Path(rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        if attrs.get("path") and rel not in seen:
            target.write_text(body)
            seen.add(rel)
        else:
            with target.open("a") as fh:
                fh.write(body)
        out.setdefault(rel, 0)
        out[rel] += body.count("\n")
    for rel, lines in sorted(out.items()):
        print(f"tangled {rel} ({lines} lines)")

if __name__ == "__main__":
    tangle(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "blueprint.md"))