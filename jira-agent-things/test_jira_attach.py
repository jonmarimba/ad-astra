#!/usr/bin/env python3
"""Regression tests for jira-attach. Standard library only: the network traffic goes to a
server on 127.0.0.1 started by the tests, and nothing touches the keychain.

    python3 test_jira_attach.py                          # tests the jira-attach beside this file
    JIRA_ATTACH_SCRIPT=/path/to/jira-attach python3 test_jira_attach.py
"""

import email.message
import http.server
import io
import json
import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

SCRIPT = os.environ.get("JIRA_ATTACH_SCRIPT") or str(Path(__file__).with_name("jira-attach"))
os.environ["JIRA_CLOUD_ID"] = "CLOUD"  # keeps gateway_url_for_fetch off the network
GATEWAY_PREFIX = "https://api.atlassian.com/ex/jira/CLOUD"
SITE = "https://team.atlassian.net"


def load_script():
    loader = SourceFileLoader("jira_attach", SCRIPT)
    module = module_from_spec(spec_from_loader("jira_attach", loader))
    # dataclasses resolve string annotations through sys.modules on Python 3.9.
    sys.modules["jira_attach"] = module
    loader.exec_module(module)
    return module


ja = load_script()
SETTINGS = ja.Settings(site=SITE, email="a@b.com", keychain_service="test")
CREDENTIALS = ja.Credentials(email="a@b.com", token="token")

BINARY_BODY = b"\xff\xd8\xff\xe0" + bytes(range(256)) * 400
TEXT_BODY = json.dumps({"key": "MHMAPPS-1", "summary": "café"}).encode()
SLOW_CHUNK, SLOW_CHUNK_COUNT, SLOW_DELAY = 4096, 60, 0.05


class _Handler(http.server.BaseHTTPRequestHandler):
    # HTTP/1.0: the server closes the connection after each response, which is what
    # lets /short end its body early.
    def log_message(self, *args):
        pass

    def _start(self, length):
        self.send_response(200)
        self.send_header("Content-Length", str(length))
        self.end_headers()

    def do_GET(self):
        try:
            if self.path == "/binary":
                self._start(len(BINARY_BODY))
                self.wfile.write(BINARY_BODY)
            elif self.path == "/text":
                self._start(len(TEXT_BODY))
                self.wfile.write(TEXT_BODY)
            elif self.path == "/short":
                self._start(100000)
                self.wfile.write(BINARY_BODY[:1000])
            elif self.path == "/slow":
                self._start(SLOW_CHUNK * SLOW_CHUNK_COUNT)
                for _ in range(SLOW_CHUNK_COUNT):
                    self.wfile.write(b"x" * SLOW_CHUNK)
                    self.wfile.flush()
                    time.sleep(SLOW_DELAY)
            elif self.path == "/hang":
                time.sleep(5)
            elif self.path == "/landing":
                body = json.dumps([{"id": "1", "filename": "landing.png"}]).encode()
                self._start(len(body))
                self.wfile.write(body)
            else:
                self.send_error(404)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _write(self):
        """Answer a write with the status named by the path's first segment
        (/303/..., /500/...); a 3xx points at /landing, which a followed redirect
        would GET."""
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        status = int(self.path.split("/")[1])
        self.send_response(status)
        if 300 <= status < 400:
            self.send_header("Location", "/landing")
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_POST = do_PUT = _write


def setUpModule():
    global SERVER, BASE
    SERVER = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    SERVER.daemon_threads = True
    threading.Thread(target=SERVER.serve_forever, daemon=True).start()
    BASE = f"http://127.0.0.1:{SERVER.server_address[1]}"


def tearDownModule():
    SERVER.shutdown()


def fetch_to_stdout_in_process(url):
    """Run fetch() in stdout mode with stdout captured; returns (bytes, SystemExit|None)."""
    captured = io.BytesIO()
    wrapper = io.TextIOWrapper(captured)
    real_stdout = sys.stdout
    sys.stdout = wrapper
    try:
        ja.fetch(url, CREDENTIALS, None)
        exit_error = None
    except SystemExit as error:
        exit_error = error
    finally:
        sys.stdout = real_stdout
        wrapper.flush()
        # Detached so the wrapper's eventual collection can't close the BytesIO.
        wrapper.detach()
    return captured.getvalue(), exit_error


CHILD_FETCH = r"""
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
loader = SourceFileLoader("jira_attach", sys.argv[1])
ja = module_from_spec(spec_from_loader("jira_attach", loader))
sys.modules["jira_attach"] = ja
loader.exec_module(ja)
destination = Path(sys.argv[3]) if len(sys.argv) > 3 else None
ja.fetch(sys.argv[2], ja.Credentials(email="a@b.com", token="token"), destination)
"""


def child_fetch_command(url, destination=None):
    command = [sys.executable, "-c", CHILD_FETCH, SCRIPT, url]
    return command + ([str(destination)] if destination else [])


def run_cli(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                          env={**os.environ, "JIRA_SITE": "team.atlassian.net",
                               "JIRA_EMAIL": "a@b.com"})


class TemporaryDirectoryTest(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())


# --------------------------------------------------------------------------- #
# URL mapping
# --------------------------------------------------------------------------- #

class GatewayUrlForFetch(unittest.TestCase):
    def assertMaps(self, url, expected):
        self.assertEqual(ja.gateway_url_for_fetch(url, SETTINGS), expected)

    def assertRefused(self, url):
        with self.assertRaises(ValueError):
            ja.gateway_url_for_fetch(url, SETTINGS)

    def test_rest_path_and_query(self):
        self.assertMaps(f"{SITE}/rest/api/3/issue/X-1?fields=summary,status",
                        f"{GATEWAY_PREFIX}/rest/api/3/issue/X-1?fields=summary,status")

    def test_host_is_case_insensitive(self):
        self.assertMaps("https://TEAM.atlassian.net/rest/api/3/myself", f"{GATEWAY_PREFIX}/rest/api/3/myself")

    def test_surrounding_whitespace_ignored(self):
        self.assertMaps(f"  {SITE}/rest/api/3/myself\n", f"{GATEWAY_PREFIX}/rest/api/3/myself")

    def test_attachment_page_becomes_attachment_content(self):
        self.assertMaps(f"{SITE}/secure/attachment/10001/shot%20one.png",
                        f"{GATEWAY_PREFIX}/rest/api/3/attachment/content/10001")
        self.assertMaps(f"{SITE}/secure/attachment/10001", f"{GATEWAY_PREFIX}/rest/api/3/attachment/content/10001")

    def test_gateway_url_passes_through(self):
        url = "https://api.atlassian.com/ex/jira/OTHER/rest/api/3/issue/X-1?a=b"
        self.assertMaps(url, url)

    def test_illegal_characters_escaped_and_existing_escapes_kept(self):
        self.assertMaps(f"{SITE}/rest/api/3/search/jql?jql=project = X&maxResults=1",
                        f"{GATEWAY_PREFIX}/rest/api/3/search/jql?jql=project%20=%20X&maxResults=1")
        self.assertMaps(f'{SITE}/rest/api/3/search/jql?jql=text ~ "café"',
                        f"{GATEWAY_PREFIX}/rest/api/3/search/jql?jql=text%20~%20%22caf%C3%A9%22")
        self.assertMaps(f"{SITE}/rest/api/3/search/jql?jql=project%20%3D%20X",
                        f"{GATEWAY_PREFIX}/rest/api/3/search/jql?jql=project%20%3D%20X")

    def test_dots_inside_names_and_queries_allowed(self):
        self.assertMaps(f"{SITE}/secure/attachment/123/name.v2.png", f"{GATEWAY_PREFIX}/rest/api/3/attachment/content/123")
        self.assertMaps(f"{SITE}/rest/api/3/x/a..b?jql=../..", f"{GATEWAY_PREFIX}/rest/api/3/x/a..b?jql=../..")

    def test_refused(self):
        for url in ("http://team.atlassian.net/rest/api/3/myself",
                    "https://evil.com/rest/api/3/myself",
                    "https://team.atlassian.net.evil.com/rest/api/3/myself",
                    "https://evil.com@team.atlassian.net/rest/api/3/myself",
                    "https://team.atlassian.net:8443/rest/api/3/myself",
                    f"{SITE}/browse/X-1",
                    f"{SITE}/secure/attachment/abc/a.png",
                    "https://api.atlassian.com/ex/confluence/C/wiki/rest/api/content",
                    "MHMAPPS-1"):
            with self.subTest(url=url):
                self.assertRefused(url)

    def test_dot_segments_refused(self):
        for url in (f"{SITE}/rest/../../ex/confluence/wiki",
                    "https://api.atlassian.com/ex/jira/../confluence/x",
                    "https://api.atlassian.com/ex/jira/%2e%2e/confluence/x",
                    f"{SITE}/rest/api/3/./myself",
                    f"{SITE}/rest/api/3/..%2Fx",
                    f"{SITE}/rest/api/3/..;x/y"):
            with self.subTest(url=url):
                self.assertRefused(url)

    def test_foreign_host_refusal_wins_over_dot_segment_refusal(self):
        with self.assertRaisesRegex(ValueError, "refusing to send"):
            ja.gateway_url_for_fetch("https://evil.com/rest/../x", SETTINGS)


# --------------------------------------------------------------------------- #
# Fetching
# --------------------------------------------------------------------------- #

class Fetch(TemporaryDirectoryTest):
    def test_full_body_saved(self):
        destination = self.directory / "a.bin"
        self.assertEqual(ja.fetch(f"{BASE}/binary", CREDENTIALS, destination), len(BINARY_BODY))
        self.assertEqual(destination.read_bytes(), BINARY_BODY)

    def test_full_body_to_stdout(self):
        body, exit_error = fetch_to_stdout_in_process(f"{BASE}/binary")
        self.assertIsNone(exit_error)
        self.assertEqual(body, BINARY_BODY)

    def test_short_body_to_file_fails_and_leaves_no_file(self):
        destination = self.directory / "a.bin"
        with self.assertRaises(SystemExit) as raised:
            ja.fetch(f"{BASE}/short", CREDENTIALS, destination)
        self.assertIn("short of its Content-Length", str(raised.exception.code))
        self.assertFalse(destination.exists())

    def test_short_body_to_stdout_fails(self):
        _, exit_error = fetch_to_stdout_in_process(f"{BASE}/short")
        self.assertIsNotNone(exit_error)
        self.assertIn("short of its Content-Length", str(exit_error.code))

    def test_timeout_reported_as_timeout(self):
        original_timeout = ja.HTTP_TIMEOUT
        ja.HTTP_TIMEOUT = 0.5
        try:
            with self.assertRaises(SystemExit) as raised:
                ja.fetch(f"{BASE}/hang", CREDENTIALS, self.directory / "a.bin")
        finally:
            ja.HTTP_TIMEOUT = original_timeout
        self.assertIn("Timed out", str(raised.exception.code))
        self.assertFalse((self.directory / "a.bin").exists())


class SaveToNewFile(TemporaryDirectoryTest):
    def test_existing_file_untouched(self):
        # A file that appears after main()'s up-front check must still not be overwritten.
        destination = self.directory / "a.bin"
        destination.write_bytes(b"keep")
        with self.assertRaises(SystemExit):
            ja._save_to_new_file(io.BytesIO(b"new"), destination)
        self.assertEqual(destination.read_bytes(), b"keep")

    def test_failed_copy_removes_partial_file(self):
        class DropsAfterTwoReads(io.RawIOBase):
            reads = 0

            def readinto(self, buffer):
                DropsAfterTwoReads.reads += 1
                if DropsAfterTwoReads.reads > 2:
                    raise ConnectionResetError("dropped")
                buffer[:4] = b"abcd"
                return 4

        destination = self.directory / "a.bin"
        with self.assertRaises(ConnectionResetError):
            ja._save_to_new_file(DropsAfterTwoReads(), destination)
        self.assertFalse(destination.exists())


class Interruption(TemporaryDirectoryTest):
    def start_slow_download(self, **popen_options):
        destination = self.directory / "slow.bin"
        child = subprocess.Popen(child_fetch_command(f"{BASE}/slow", destination),
                                 stderr=subprocess.PIPE, text=True, **popen_options)
        deadline = time.monotonic() + 10
        while not (destination.exists() and destination.stat().st_size > 0):
            self.assertLess(time.monotonic(), deadline, "download never started")
            time.sleep(0.02)
        return child, destination

    def assertInterruptedCleanly(self, signum):
        child, destination = self.start_slow_download()
        child.send_signal(signum)
        _, stderr = child.communicate(timeout=10)
        self.assertEqual(child.returncode, -signum, stderr)
        self.assertFalse(destination.exists(), "partial download left behind")
        self.assertIn("Interrupted", stderr)
        self.assertNotIn("Traceback", stderr)

    def test_sigterm_removes_partial_download(self):
        self.assertInterruptedCleanly(signal.SIGTERM)

    def test_sighup_removes_partial_download(self):
        self.assertInterruptedCleanly(signal.SIGHUP)

    def test_ctrl_c_removes_partial_download_without_traceback(self):
        self.assertInterruptedCleanly(signal.SIGINT)

    def test_ignored_sighup_stays_ignored(self):
        # nohup sets SIGHUP to ignored; the download must then run to completion.
        child, destination = self.start_slow_download(
            preexec_fn=lambda: signal.signal(signal.SIGHUP, signal.SIG_IGN))
        child.send_signal(signal.SIGHUP)
        _, stderr = child.communicate(timeout=20)
        self.assertEqual(child.returncode, 0, stderr)
        self.assertEqual(destination.stat().st_size, SLOW_CHUNK * SLOW_CHUNK_COUNT)


class BinaryToTerminal(unittest.TestCase):
    def run_with_terminal_stdout(self, url):
        controller, terminal = pty.openpty()
        child = subprocess.Popen(child_fetch_command(url), stdout=terminal,
                                 stderr=subprocess.PIPE, text=True)
        os.close(terminal)
        received = b""
        while True:
            ready, _, _ = select.select([controller], [], [], 10)
            if not ready:
                break
            try:
                chunk = os.read(controller, 65536)
            except OSError:  # EIO once the child has closed its end
                break
            if not chunk:
                break
            received += chunk
        _, stderr = child.communicate(timeout=10)
        os.close(controller)
        return child.returncode, received, stderr

    def test_binary_refused_on_terminal_with_nothing_written(self):
        returncode, received, stderr = self.run_with_terminal_stdout(f"{BASE}/binary")
        self.assertNotEqual(returncode, 0)
        self.assertEqual(received, b"")
        self.assertIn("binary", stderr)
        self.assertNotIn("Traceback", stderr)

    def test_text_printed_on_terminal(self):
        returncode, received, stderr = self.run_with_terminal_stdout(f"{BASE}/text")
        self.assertEqual(returncode, 0, stderr)
        self.assertIn(b"MHMAPPS-1", received)

    def test_binary_through_pipe_unchanged(self):
        child = subprocess.run(child_fetch_command(f"{BASE}/binary"), capture_output=True)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertEqual(child.stdout, BINARY_BODY)


# --------------------------------------------------------------------------- #
# Redirects
# --------------------------------------------------------------------------- #

class Redirects(unittest.TestCase):
    def redirect(self, from_url, to_url):
        request = urllib.request.Request(from_url, headers={"Authorization": "Basic secret"})
        return ja._StripAuthCrossOrigin().redirect_request(
            request, io.BytesIO(b""), 302, "Found", email.message.Message(), to_url)

    def test_redirect_to_http_refused(self):
        for target in ("http://api.atlassian.com/y", "http://elsewhere.example/y"):
            with self.subTest(target=target):
                with self.assertRaises(urllib.error.HTTPError) as raised:
                    self.redirect("https://api.atlassian.com/x", target)
                self.assertIn("non-https", str(raised.exception))

    def test_cross_host_redirect_drops_token(self):
        redirected = self.redirect("https://api.atlassian.com/x", "https://api.media.atlassian.com/y")
        self.assertFalse(redirected.has_header("Authorization"))

    def test_same_host_redirect_keeps_token_regardless_of_case(self):
        redirected = self.redirect("https://api.atlassian.com/x", "https://API.atlassian.com/y")
        self.assertTrue(redirected.has_header("Authorization"))


class RedirectedWrites(TemporaryDirectoryTest):
    """A redirect answering a write must not be followed (urllib would re-send a POST as
    a GET of the new URL and hand back that body as the write's result), and must count
    as uncertain: a 303 says the write was processed, so rolling back could delete
    attachments that committed content references."""

    def setUp(self):
        super().setUp()
        # The test server is plain http, which the real opener refuses to redirect to;
        # a plain following opener isolates "writes are never followed" from that rule.
        self.real_opener = ja._opener
        ja._opener = urllib.request.build_opener()

    def tearDown(self):
        ja._opener = self.real_opener

    def test_redirected_writes_are_uncertain(self):
        for method in ("POST", "PUT"):
            for status in (301, 302, 303, 307, 308):
                with self.subTest(method=method, status=status):
                    with self.assertRaises(ja._Ambiguous) as raised:
                        ja.api(method, f"{BASE}/{status}/issue/X-1/comment", CREDENTIALS, json_body={})
                    self.assertIn("may or may not have committed", str(raised.exception))

    def test_server_error_on_write_stays_uncertain(self):
        with self.assertRaises(ja._Ambiguous):
            ja.api("POST", f"{BASE}/500/issue/X-1/comment", CREDENTIALS, json_body={})

    def test_rejected_write_stays_definitive(self):
        with self.assertRaises(SystemExit):
            ja.api("POST", f"{BASE}/400/issue/X-1/comment", CREDENTIALS, json_body={})

    def test_redirected_or_failed_upload_reported_as_uncertain(self):
        upload = self.directory / "shot.png"
        upload.write_bytes(b"png")
        for status in (303, 307, 500):
            with self.subTest(status=status):
                with self.assertRaises(SystemExit) as raised:
                    ja.attach_one(f"{BASE}/{status}", CREDENTIALS, "X-1", upload)
                self.assertIn("may or may not have been attached", str(raised.exception.code))


# --------------------------------------------------------------------------- #
# Error messages
# --------------------------------------------------------------------------- #

class HttpErrorMessages(unittest.TestCase):
    def message_for(self, code, body):
        error = urllib.error.HTTPError("https://x/y", code, "Reason", email.message.Message(),
                                       io.BytesIO(body))
        with self.assertRaises(SystemExit) as raised:
            ja._die_http(error, "https://x/y")
        return str(raised.exception.code)

    def test_404_names_both_causes(self):
        message = self.message_for(404, b'{"errorMessages":["The attachment does not exist"]}')
        self.assertIn("does not exist or the stored token can't see it", message)
        self.assertNotIn("issue/comment", message)

    def test_401_missing_scope_says_create_a_token(self):
        message = self.message_for(401, b'{"code":401,"message":"Unauthorized; scope does not match"}')
        self.assertIn("lacks a scope", message)
        self.assertIn("--reset-token", message)
        self.assertNotIn("Add the scope", message)

    def test_401_other_says_revoked(self):
        self.assertIn("may be revoked", self.message_for(401, b"{}"))


# --------------------------------------------------------------------------- #
# Command line
# --------------------------------------------------------------------------- #

class CommandLine(TemporaryDirectoryTest):
    FETCH = ("--fetch-url", f"{SITE}/rest/api/3/myself")

    def assertUsageError(self, result, expected_text):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(expected_text, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_fetch_rejects_issue_and_setup_options(self):
        self.assertUsageError(run_cli(*self.FETCH, "X-1"), "--fetch-url only fetches")
        self.assertUsageError(run_cli(*self.FETCH, "--configure"), "--fetch-url only fetches")

    def test_setup_rejects_issue(self):
        self.assertUsageError(run_cli("--configure", "X-1"), "only change stored settings")

    def test_output_requires_fetch(self):
        self.assertUsageError(run_cli("X-1", "a.png", "-o", "x.jpg"), "--output only applies to --fetch-url")

    def test_foreign_host_refused_before_any_token_lookup(self):
        self.assertUsageError(run_cli("--fetch-url", "https://evil.com/rest/api/3/myself"), "refusing")

    def test_output_dash_refused(self):
        self.assertUsageError(run_cli(*self.FETCH, "-o", "-"), "stdout")

    def test_output_existing_file_refused(self):
        existing = self.directory / "a.jpg"
        existing.write_bytes(b"keep")
        self.assertUsageError(run_cli(*self.FETCH, "-o", str(existing)), "already exists")
        self.assertEqual(existing.read_bytes(), b"keep")

    def test_output_directory_refused(self):
        self.assertUsageError(run_cli(*self.FETCH, "-o", str(self.directory)), "is a directory")

    def test_output_missing_directory_refused(self):
        self.assertUsageError(run_cli(*self.FETCH, "-o", str(self.directory / "no" / "x.jpg")),
                              "does not exist")

    def test_output_dangling_symlink_refused(self):
        link = self.directory / "dangling.jpg"
        link.symlink_to(self.directory / "nowhere")
        self.assertUsageError(run_cli(*self.FETCH, "-o", str(link)), "already exists")

    def test_output_under_file_refused(self):
        (self.directory / "afile").write_bytes(b"")
        self.assertUsageError(run_cli(*self.FETCH, "-o", str(self.directory / "afile" / "x.jpg")),
                              "Not a directory")

    def test_output_under_unreadable_directory_refused(self):
        locked = self.directory / "locked"
        locked.mkdir()
        locked.chmod(0)
        try:
            self.assertUsageError(run_cli(*self.FETCH, "-o", str(locked / "sub" / "x.jpg")),
                                  "Permission denied")
        finally:
            locked.chmod(0o700)


if __name__ == "__main__":
    unittest.main()
