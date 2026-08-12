#!/usr/bin/env python3
# toml_set.py — set keys in a TOML file, format- and comment-preserving (tomlkit).
# Usage: toml_set.py <file.toml> dotted.key=value [dotted.key=value ...]
# Values: true/false -> bool, ints -> int, everything else -> string.
# Dotted keys create/traverse nested tables (e.g. sandbox_workspace_write.network_access=false).
import sys, tomlkit

def coerce(v):
    if v in ("true", "false"):
        return v == "true"
    try:
        return int(v)
    except ValueError:
        return v

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = tomlkit.parse(f.read())

for pair in sys.argv[2:]:
    key, _, val = pair.partition("=")
    parts = key.split(".")
    node = doc
    for p in parts[:-1]:
        if p not in node or not isinstance(node.get(p), (dict,)) and not hasattr(node.get(p), "value"):
            node[p] = tomlkit.table()
        node = node[p]
    node[parts[-1]] = coerce(val)

with open(path, "w", encoding="utf-8") as f:
    f.write(tomlkit.dumps(doc))
print(f"toml_set: updated {len(sys.argv) - 2} key(s) in {path}")
