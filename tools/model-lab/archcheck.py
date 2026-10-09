#!/usr/bin/env python3
"""archcheck: which model architectures does each runtime support? Scans runtime binaries for the architecture names.
  python archcheck.py qwen4exp gemma4 glm5-next --runtime C:/path/to/runtime_dir_or_binary [--runtime ...]
Prints a table (yes/no per runtime). Use it BEFORE downloading a big model: GGUF repos on Hugging Face report their
architecture in the API (gguf.architecture; scout.py shows it), so an unsupported architecture can be skipped for free."""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scout import runtime_files, arch_supported

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("archs", nargs="+")
ap.add_argument("--runtime", action="append", required=True)
a = ap.parse_args()
def label(p):
    parts = [x for x in os.path.normpath(p).replace(chr(92), "/").split("/") if x]
    return '/'.join(parts[-3:-1] if parts[-1] in ('bin', 'Release') else parts[-2:])
rts = {label(p): runtime_files([p]) for p in a.runtime}
print("%-16s" % "architecture" + "".join("%-30s" % n[-28:] for n in rts))
for arch in a.archs:
    print("%-16s" % arch + "".join("%-30s" % ("yes" if arch_supported(arch, f) else "NO") for f in rts.values()))
