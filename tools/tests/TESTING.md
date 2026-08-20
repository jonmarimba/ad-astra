# @astra tool tests — the standard

Every tool in `tools/` gets a `test-<tool>.sh` here, and **no tool change ships without a green `run-all.sh`**. The rules are Jonathan's own, from the kicker test-truthfulness work (`js-llmKicker/docs/TAUTOLOGY-AUDIT-20260801.md`, `docs/planning/07d-test-truthfulness/SPEC.md`): a test that goes red is worth more than a paragraph that is true.

## The four rules

1. **Real world, by effect.** Run the shipped script against real dependencies (real pandoc, real whisper, real git repos, live HF API) and assert the effect in the world — the PDF's text layer, the routed message file, the exit code. The only things faked are transports that would touch a human or a sleeping host (texting Jonathan's phone, ssh-ing the M5), and those are swapped at the tool's own injectable-binary seam (`IMSG_BIN`, `CURL_BIN`, `SSH_BIN`) with payloads recorded from the live systems — never by asserting that a mock was called.
2. **Every test file carries RED controls** (`red` in lib.sh): inputs that MUST fail — the one-letter-off template, the missing binary, the replayed watermark. If a RED control passes, the test file fails: that's the tautology detector.
3. **No silent skips.** A missing dependency is a loud FAIL with the install command (`need` in lib.sh). If an assert had to be weakened (e.g. pymupdf absent → size floor instead of text layer), the pass message SAYS so.
4. **Names don't overclaim.** `test-ambrosio.sh` tests ambrosio's loop with a recorded trending payload; the live-delivery leg on a real M5 is a separate claim it doesn't make.

## Running

    tools/tests/run-all.sh          # everything; nonzero exit on any failure
    bash tools/tests/test-botline.sh   # one file

## Writing a new one

Copy the shape of `test-botline.sh`. Source `lib.sh`, sandbox via `$SB`, gate deps with `need`, assert by effect, include RED controls, end with `finish`. If the tool's transport can't be exercised without side effects on a human or another machine, give the TOOL an injectable-binary env seam (the `IMSG_BIN` pattern) rather than the test a mock framework.

## Review step

New tools and non-trivial changes get an adversarial review before shipping: the `code-review` skill on the diff, or a `convoke` round (skills/convocation) with the other CLIs as independent reviewers. Findings get fixed in place, not appended.
