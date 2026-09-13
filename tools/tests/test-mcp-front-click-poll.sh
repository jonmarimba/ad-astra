#!/usr/bin/env bash
# TIER: fast -- proves the daemon never spawns overlapping or Xcode-absent
# approval polls, and reaps an osascript child when its wait times out.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DAEMON_DIR="$HERE/../xcode-mcp-front"

XCODE_MCP_FRONT_OSASCRIPT_TIMEOUT_S=0.02 DAEMON_DIR="$DAEMON_DIR" \
  uv run --with 'mcp>=2.0.0' --with uvicorn python3 - <<'PY'
import asyncio
import os
import sys

sys.path.insert(0, os.environ["DAEMON_DIR"])
import daemon


async def main():
    calls = 0

    async def must_not_spawn(*args, **kwargs):
        nonlocal calls
        calls += 1
        raise AssertionError("absent Xcode must not launch osascript")

    original_spawn = asyncio.create_subprocess_exec
    original_running = daemon._xcode_is_running
    original_unlocked = daemon._click_allow_if_present_unlocked
    try:
        daemon._xcode_is_running = lambda: False
        asyncio.create_subprocess_exec = must_not_spawn
        assert await daemon._click_allow_if_present() is False
        assert calls == 0

        active = 0
        maximum = 0

        async def slow_poll():
            nonlocal active, maximum
            active += 1
            maximum = max(maximum, active)
            await asyncio.sleep(0.01)
            active -= 1
            return False

        daemon._xcode_is_running = lambda: True
        daemon._click_allow_if_present_unlocked = slow_poll
        await asyncio.gather(*(daemon._click_allow_if_present() for _ in range(8)))
        assert maximum == 1, maximum

        class HungProcess:
            returncode = None
            def __init__(self):
                self.killed = False
                self.done = asyncio.Event()
            async def communicate(self):
                await self.done.wait()
                return b"", b""
            def kill(self):
                self.killed = True
                self.returncode = -9
                self.done.set()
            async def wait(self):
                await self.done.wait()
                return self.returncode

        proc = HungProcess()
        async def spawn_hung(*args, **kwargs):
            return proc

        asyncio.create_subprocess_exec = spawn_hung
        daemon._click_allow_if_present_unlocked = original_unlocked
        try:
            await daemon._run_osascript("return \"\"")
        except asyncio.TimeoutError:
            pass
        else:
            raise AssertionError("hung osascript did not time out")
        assert proc.killed
    finally:
        asyncio.create_subprocess_exec = original_spawn
        daemon._xcode_is_running = original_running
        daemon._click_allow_if_present_unlocked = original_unlocked


asyncio.run(main())
print("ok: Xcode-absent gate, single-flight poll, and timed-out child reap")
PY
