# @astra tool tests — the standard

Every tool in `tools/` gets a `test-<tool>.sh` here, and **no tool change ships without a green `run-all.sh`**. The rules are Jonathan's own, from the kicker test-truthfulness work (`js-llmKicker/docs/TAUTOLOGY-AUDIT-20260801.md`, `docs/planning/07d-test-truthfulness/SPEC.md`). A test that goes red is worth more than a paragraph that is true.

## The four rules

1. **Real world, by effect.** Run the shipped script against real dependencies (real pandoc, real whisper, real git repos, live HF API). Assert the effect in the world — the PDF's text layer, the routed message file, the exit code. The only things faked are transports that would touch a human or a sleeping host (texting Jonathan's phone, ssh-ing the M5). Those are swapped at the tool's own injectable-binary seam (`IMSG_BIN`, `CURL_BIN`, `SSH_BIN`) with payloads recorded from the live systems. The faking is never done by asserting that a mock was called.
2. **Every test file carries RED controls** (`red` in lib.sh): inputs that MUST fail — the one-letter-off template, the missing binary, the replayed watermark. A control declares the exact exit code and a literal fragment of the guard's error message (`red "label" 64 "unknown flag" cmd...`). So it passes only when the guard rejected the input for the claimed reason — a command that dies some other way fails the control. If a RED control passes against bad input, the test file fails: that's the tautology detector.
3. **No silent skips.** A missing dependency is a loud FAIL with the install command (`need` in lib.sh). If an assert had to be weakened (e.g. pymupdf absent → size floor instead of text layer), the pass message SAYS so.
4. **Names don't overclaim.** `test-ambrosio.sh` tests ambrosio's loop with a recorded trending payload. The live-delivery leg on a real M5 is a separate claim it doesn't make.

## Running — two tiers

```
tools/tests/run-all.sh             # FAST tier: parallel, budgeted at 20s (scaled by machine load), fails itself if over
tools/tests/run-slow.sh            # SLOW tier: tens of seconds, serial. Nothing needs this machine: tests that touch OmniRoute or Xcode start their own stubs
bash tools/tests/test-botline.sh   # one file
```

A file joins the slow tier by carrying `# TIER: slow — <reason>` in its first three lines. The ship gate is BOTH tiers green. The fast tier asserts its own time budget. A test that grows past it turns the suite red rather than quietly making it something nobody runs. `test-run-tiers.sh` tests the runners themselves.

## Writing a new one

Copy the shape of `test-botline.sh`. Source `lib.sh`, sandbox via `$SB`, gate deps with `need`, assert by effect, include RED controls, end with `finish`. If the tool's transport can't be exercised without side effects on a human or another machine, give the TOOL an injectable-binary env seam. Use the `IMSG_BIN` pattern rather than giving the test a mock framework.

## A throwaway machine for install, upgrade and uninstall

`tools/tests/fakeworld/` holds stand-ins for `brew`, `pipx`, `uv`, `npm` and `python3 -m pip`. Each keeps real state under `$FAKE_WORLD`: a prefix, a cellar with versions, shims in a sandbox `~/.local/bin`, and a call log. Each fails with exit 99 on any verb the installers are not meant to use.

Every astra script that puts Homebrew on `PATH` lets `ASTRA_PATH` replace it. That lets a test build a machine that sees nothing the real one has. `test-machine-lifecycle.sh` uses this to run `astra upgrade`, the uninstallers, a wrapper-app build, and a template install and uninstall against an empty machine.

The fakes encode Homebrew behavior that bit us on the real machine. `bundle list` can print a banner on stdout. `upgrade` and `uninstall` autoremove orphaned dependencies, including ones the tool never installed. When you add a brew verb to an installer, add it to the fake first.

### The real Homebrew

`test-real-brew.sh` installs a genuine Homebrew into a mktemp directory with `git clone`. It takes the real Homebrew out of `PATH`, including its `opt/` directories, and runs the verbs astra's tools use against the new one. This checks the fake's assumptions instead of repeating them. It proved that a bare `brew uninstall` autoremoves unrelated orphans, and that the `HOMEBREW_NO_AUTOREMOVE` guard stops it. It needs the network and says so when it has none.

Only relocatable bottles pour into another prefix: `jq`, `uv` and `exiftool` do. Bottles tied to `/opt/homebrew/Cellar` (`poppler`, `gettext`, `ffmpeg`) cannot be installed anywhere else, so the full upgrade of every tool stays on the stand-in. Formulae that build from source, such as `axe` and `imsg`, fail inside another sandbox (an agent's shell) because Homebrew refuses to nest its own. They work in an ordinary terminal.

## Review step

New tools and non-trivial changes get an adversarial review before shipping. The review is the `code-review` skill on the diff, or a `panel` round (skills/convocation) with the other CLIs as independent reviewers. Findings get fixed in place, not appended.
