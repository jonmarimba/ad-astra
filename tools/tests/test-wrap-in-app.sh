#!/usr/bin/env bash
# test-wrap-in-app.sh — wraps a real fixture script, LAUNCHES the generated app (same
# open -g -W path the scheduler uses), and proves the whole contract by effect: output
# lands in the log, the shim prints only what the script printed, a silent run pokes
# nothing, and editing the script does NOT change the app's code hash (the grant-survival
# property the design exists for). TCC itself can't be asserted from a test — that part
# is proven by the live HOA wrapper's nightly runs.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
WIA="$HERE/../wrap-in-app/wrap-in-app"
need codesign "xcode-select --install"
need plutil "macOS"
need lipo "xcode-select --install"

# guard the template itself: the stub this tool clones must be arm64-native, or every app it
# ever mints inherits the Rosetta-removal time bomb (the real one-time-resave cause)
STUB="$HERE/../wrap-in-app/template.app/Contents/MacOS/Automator Application Stub"
lipo -archs "$STUB" 2>/dev/null | grep -qw arm64 && pass "template stub is arm64-native (won't die when Rosetta goes)" || fail "template stub is Intel-only — refresh template.app on Apple Silicon"

cat > "$SB/job.sh" <<'EOF'
#!/bin/bash
[ -f "$(dirname "$0")/be_noisy" ] && echo "MARKER-OUTPUT-1122"
exit 0
EOF
chmod +x "$SB/job.sh"

# ---- build ----
assert_rc 0 "wrap succeeds" "$WIA" "$SB/job.sh" --log "$SB/logs/job.log" --name TestJobWrapper --outdir "$SB/out"
APP="$SB/out/TestJobWrapper.app"; SHIM="$SB/out/testjobwrapper_launch.sh"
assert_dir "$APP" "app bundle created"
assert_file "$SHIM" "launch shim created"
assert_contains "$APP/Contents/document.wflow" "$SB/job.sh" "app references the script by absolute path"
assert_contains "$APP/Contents/document.wflow" "$SB/logs/job.log" "app redirects output into the log"
assert_eq "com.apple.automator.TestJobWrapper" "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" "bundle identifier set"
codesign -v "$APP" 2>/dev/null && pass "signature verifies" || fail "signature does not verify"
# the stub must be arm64-native — an Intel-only stub is the real reason an old applet needs a
# one-time re-save (macOS is dropping Rosetta); a minted app must not carry that time bomb
lipo -archs "$APP/Contents/MacOS/Automator Application Stub" 2>/dev/null | grep -qw arm64 && pass "minted app's stub runs natively on Apple Silicon (survives Rosetta removal)" || fail "minted app's stub is not arm64-native — will die when macOS drops Rosetta"

# ---- run it for real: noisy run -> log + shim output ----
touch "$SB/be_noisy"
out="$(bash "$SHIM")"; rc=$?
assert_eq "0" "$rc" "shim exits 0"
assert_contains "$SB/logs/job.log" "MARKER-OUTPUT-1122" "script output captured in the log (stdout was swallowed by the app, not lost)"
assert_contains "$SB/logs/job.log" "=== run start" "run markers bracket the log entry"
case "$out" in *MARKER-OUTPUT-1122*) pass "shim surfaced the script's output (poke fires)";; *) fail "shim lost the script's output";; esac
case "$out" in *"=== run"*) fail "shim leaked the run markers (would poke every run)";; *) pass "shim filtered the run markers";; esac

# ---- silent run -> shim prints NOTHING (schd stays quiet) ----
rm "$SB/be_noisy"
out="$(bash "$SHIM")"
assert_empty "$out" "silent script run produces no shim output"

# ---- the meat: editing the SCRIPT must not change the app's code hash ----
h1="$(codesign -dvvv "$APP" 2>&1 | grep '^CDHash=')"
echo 'echo more stuff' >> "$SB/job.sh"
h2="$(codesign -dvvv "$APP" 2>&1 | grep '^CDHash=')"
assert_eq "$h1" "$h2" "script edit left the app's CDHash untouched (FDA grant survives)"
codesign -v "$APP" 2>/dev/null && pass "signature still verifies after script edit" || fail "script edit broke the app signature"

# ---- deprecated-runtime warning: the one thing that ever forces re-touching an app ----
cat > "$SB/py2job.sh" <<'EOF'
#!/usr/bin/python
print "old"
EOF
chmod +x "$SB/py2job.sh"
warn="$("$WIA" "$SB/py2job.sh" --log "$SB/logs/p.log" --name Py2Wrapper --outdir "$SB/out" 2>&1 >/dev/null)"
case "$warn" in *"deprecated"*|*"will remove"*) pass "warns when the wrapped script runs on a doomed system runtime";; *) fail "no deprecation warning for a /usr/bin/python shebang";; esac
# but it still BUILDS (warning, not a block — the script is the user's call)
assert_dir "$SB/out/Py2Wrapper.app" "still builds despite the warning (warn, don't block)"
cat > "$SB/hbjob.sh" <<'EOF'
#!/opt/homebrew/bin/python3
print("fine")
EOF
chmod +x "$SB/hbjob.sh"
warn="$("$WIA" "$SB/hbjob.sh" --log "$SB/logs/h.log" --name HbWrapper --outdir "$SB/out" 2>&1 >/dev/null)"
case "$warn" in *deprecated*) fail "false deprecation warning for a Homebrew interpreter";; *) pass "no warning when the shebang is a Homebrew interpreter";; esac

# ---- RED controls ----
red "existing app must be refused, not clobbered (it may hold a grant)" 1 "already exists — refusing to overwrite" "$WIA" "$SB/job.sh" --log "$SB/logs/job.log" --name TestJobWrapper --outdir "$SB/out"
red "missing --log must fail (stdout has nowhere to go)" 64 "--log is required" "$WIA" "$SB/job.sh" --outdir "$SB/out"
printf '#!/bin/bash\n' > "$SB/noexec.sh"
red "non-executable script must fail" 1 "is not executable" "$WIA" "$SB/noexec.sh" --log "$SB/l.log" --outdir "$SB/out"
red "unknown flag must fail" 64 "unknown flag '--outdri'" "$WIA" "$SB/job.sh" --log "$SB/l.log" --outdri "$SB/out"
red "missing script must fail" 64 "usage: wrap-in-app" "$WIA" --log "$SB/l.log"

finish
