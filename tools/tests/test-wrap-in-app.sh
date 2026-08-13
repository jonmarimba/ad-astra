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

# ---- RED controls ----
red "existing app must be refused, not clobbered (it may hold a grant)" "$WIA" "$SB/job.sh" --log "$SB/logs/job.log" --name TestJobWrapper --outdir "$SB/out"
red "missing --log must fail (stdout has nowhere to go)" "$WIA" "$SB/job.sh" --outdir "$SB/out"
printf '#!/bin/bash\n' > "$SB/noexec.sh"
red "non-executable script must fail" "$WIA" "$SB/noexec.sh" --log "$SB/l.log" --outdir "$SB/out"
red "unknown flag must fail" "$WIA" "$SB/job.sh" --log "$SB/l.log" --outdri "$SB/out"
red "missing script must fail" "$WIA" --log "$SB/l.log"

finish
