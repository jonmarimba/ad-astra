#!/usr/bin/env python3
"""Print Ollama Cloud model keys from an OpenCode JSONC config.

Only a quoted key followed by an object is a model entry. A display name may
also begin with `ollamacloud/`; it must never be treated as a route ID.
"""
from pathlib import Path
import sys

for line in Path(sys.argv[1]).read_text().splitlines():
    stripped = line.strip()
    if not stripped.startswith('"ollamacloud/'):
        continue
    key, separator, remainder = stripped.partition('":')
    if separator and remainder.lstrip().startswith('{'):
        print(key[1:])
