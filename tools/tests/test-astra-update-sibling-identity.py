#!/usr/bin/env python3
# RED-capable regression for astra-update sibling-identity canonicalization (GhOST-OpenClaw peer
# review of 3daaada7). The SAME repository recorded with an SSH URL and reached by an HTTPS sibling
# clone (or vice-versa) must VERIFY, not REFUSE; an impostor (different repo) must still REFUSE.
import importlib.util, importlib.machinery, os, sys, tempfile
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "lib" / "astra-update"
loader = importlib.machinery.SourceFileLoader("astra_update_mod", str(SRC))
spec = importlib.util.spec_from_loader("astra_update_mod", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
os.environ.pop("ASTRA_SOURCE", None)   # the env fallback must not pre-empt the sibling path under test

ok = 0; fail = 0
def check(name, cond):
    global ok, fail
    if cond: print("  ok:   " + name); ok += 1
    else:    print("  FAIL: " + name); fail += 1

SSH    = "git@github.com:jonmarimba/ad-astra.git"
HTTPS  = "https://github.com/jonmarimba/ad-astra.git"
SSHURL = "ssh://git@github.com/jonmarimba/ad-astra.git"
OTHER  = "https://github.com/someoneelse/ad-astra.git"
OTHERHOST = "https://gitlab.com/jonmarimba/ad-astra.git"

# 1. Canonicalization: every transport of the same repo is equal; a different owner OR host is not.
check("ssh scp-style == https (same repo)", m._canonical_remote(SSH) == m._canonical_remote(HTTPS))
check("ssh:// url == https (same repo)",     m._canonical_remote(SSHURL) == m._canonical_remote(HTTPS))
check("different owner is not equal",        m._canonical_remote(OTHER) != m._canonical_remote(HTTPS))
check("different host is not equal",         m._canonical_remote(OTHERHOST) != m._canonical_remote(HTTPS))
check("empty url -> None",                   m._canonical_remote("") is None)

# 2. resolve_source: recorded path dead, sibling present with a DIFFERENT-transport remote of the
#    same repo -> verified; impostor -> REFUSED. Both directions.
def run_resolve(recorded_remote, sibling_remote):
    tmp = Path(tempfile.mkdtemp())
    (tmp / "astra").mkdir()                       # stand-in for REPO
    sib = tmp / "ad-astra-sibling"
    (sib / "tools").mkdir(parents=True)           # a plausible sibling checkout
    m.REPO = tmp / "astra"                         # REPO.parent == tmp, so sib is REPO.parent/<name>
    recorded = tmp / "dead" / "ad-astra-sibling"   # name matches the sibling; dead (no tools dir)
    m._git_remote = lambda p: sibling_remote       # the sibling's actual remote
    return m.resolve_source(recorded, recorded_remote)

p, note = run_resolve(SSH, HTTPS)
check("ssh recorded + https sibling -> verified", p is not None and "verified sibling" in note)
p, note = run_resolve(HTTPS, SSH)
check("https recorded + ssh sibling -> verified", p is not None and "verified sibling" in note)
p, note = run_resolve(SSH, OTHER)
check("impostor sibling (diff owner) -> REFUSED", p is None and note == "REFUSED")
p, note = run_resolve(SSH, OTHERHOST)
check("impostor sibling (diff host) -> REFUSED",  p is None and note == "REFUSED")

print("== test-astra-update-sibling-identity: %d ok, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
