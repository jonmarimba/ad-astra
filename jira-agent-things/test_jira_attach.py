#!/usr/bin/env python3
"""Regression tests for jira-attach. Standard library only: the network traffic goes to a
server on 127.0.0.1 started by the tests, and nothing touches the keychain.

    python3 test_jira_attach.py                          # tests the jira-attach beside this file
    JIRA_ATTACH_SCRIPT=/path/to/jira-attach python3 test_jira_attach.py
"""

import contextlib
import email.message
import functools
import http.server
import io
import json
import os
import pty
import re
import select
import shutil
import signal
import ssl
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


def load_script_copy():
    """A separate instance of the script, so its module-level openers are built anew
    (from Python 3.12 an HTTPSHandler fixes its trusted roots when it is built)."""
    original = sys.modules["jira_attach"]
    try:
        return load_script()
    finally:
        sys.modules["jira_attach"] = original


ja = load_script()
SETTINGS = ja.Settings(site=SITE, email="a@b.com", keychain_service="test")
CREDENTIALS = ja.Credentials(email="a@b.com", token="token")

BINARY_BODY = b"\xff\xd8\xff\xe0" + bytes(range(256)) * 400
TEXT_BODY = json.dumps({"key": "MHMAPPS-1", "summary": "café"}).encode()
# The slow body must outsize shutil.COPY_BUFSIZE (256 KiB from Python 3.14), or the
# first byte reaches disk only once the download is complete and an interruption
# test signals a process that has already finished.
SLOW_CHUNK, SLOW_CHUNK_COUNT, SLOW_DELAY = 64 * 1024, 60, 0.05
# Each request a test server receives, as (method, Host header, path, whether it carried
# Authorization). Recorded before the answer is sent, so all of a call's requests are
# here by the time it returns.
REQUESTS = []
UPLOADED = []  # filenames the test server received on .../attachments, in order


def requests_to(*hosts):
    return [request for request in REQUESTS if request[1] in hosts]
# A client timeout far below how long /hang holds back an answer.
TEST_TIMEOUT, WRITE_HANG = 0.5, 5


def _answer_with(handler, status, body, declared_length=None):
    handler.send_response(status)
    handler.send_header("Content-Length", str(len(body) if declared_length is None else declared_length))
    handler.end_headers()
    handler.wfile.write(body)


# Ways a write's answer goes wrong once the whole request was received: urllib wraps
# none of them in URLError, since the request itself went out.
LOST_ANSWERS = {
    "drop": lambda handler: None,  # the connection closes with no response
    "hang": lambda handler: time.sleep(WRITE_HANG),
    "short": lambda handler: _answer_with(handler, 200, b'{"id": "', declared_length=100),
    "notjson": lambda handler: _answer_with(handler, 200, b"<html></html>"),
    "non-utf8": lambda handler: _answer_with(handler, 200, b"\xc3\x28"),
}


class _Handler(http.server.BaseHTTPRequestHandler):
    # HTTP/1.0: the server closes the connection after each response, which is what
    # lets /short end its body early.
    def log_message(self, *args):
        pass

    def _start(self, length):
        self.send_response(200)
        self.send_header("Content-Length", str(length))
        self.end_headers()

    def _record(self):
        REQUESTS.append((self.command, self.headers.get("Host"), self.path,
                         "Authorization" in self.headers))

    def do_GET(self):
        self._record()
        try:
            if self.path.startswith("/goto/"):
                # /goto/<status>/<absolute URL>: a redirect a read follows.
                _, _, status, target = self.path.split("/", 3)
                self.send_response(int(status))
                self.send_header("Location", target)
                self.send_header("Content-Length", "0")
                self.end_headers()
            elif self.path == "/binary":
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
        would GET. /reset/... closes without reading the body, so the client's send
        fails. After reading the whole body, /drop/..., /hang/... and the rest of
        LOST_ANSWERS answer as it describes. An upload through the gateway path main()
        builds (/CLOUD/...) is accepted unless its filename starts with "rejected"."""
        self._record()
        first_segment = self.path.split("/")[1]
        if first_segment == "reset":
            return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path.startswith("/CLOUD/") and self.path.endswith("/attachments"):
            return self._upload(body)
        if first_segment in LOST_ANSWERS:
            return LOST_ANSWERS[first_segment](self)
        status = int(first_segment)
        self.send_response(status)
        if 300 <= status < 400:
            self.send_header("Location", "/landing")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _upload(self, body):
        filename = body.split(b'filename="', 1)[1].split(b'"', 1)[0].decode()
        UPLOADED.append(filename)
        if filename.startswith("rejected"):
            status, answer = 400, {"errorMessages": [f"{filename} rejected"]}
        else:
            status, answer = 200, [{"id": str(len(UPLOADED)), "filename": filename, "size": 2048}]
        payload = json.dumps(answer).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_POST = do_PUT = do_DELETE = _write


def setUpModule():
    global SERVER, BASE
    SERVER = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    SERVER.daemon_threads = True
    threading.Thread(target=SERVER.serve_forever, daemon=True).start()
    BASE = f"http://127.0.0.1:{SERVER.server_address[1]}"


def tearDownModule():
    SERVER.shutdown()
    SERVER.server_close()


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


CHILD_MAIN = r"""
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
loader = SourceFileLoader("jira_attach", sys.argv[1])
ja = module_from_spec(spec_from_loader("jira_attach", loader))
sys.modules["jira_attach"] = ja
loader.exec_module(ja)
# A renamed seam must fail here rather than leave the real config and keychain in use.
for name in ("GATEWAY", "resolve_settings", "obtain_credentials"):
    getattr(ja, name)
ja.GATEWAY, ja.HTTP_TIMEOUT = sys.argv[2], float(sys.argv[3])
ja.resolve_settings = lambda *args, **kwargs: ja.Settings(
    site="https://team.atlassian.net", email="a@b.com", keychain_service="test")
ja.obtain_credentials = lambda *args, **kwargs: ja.Credentials(email="a@b.com", token="token")
sys.argv = ["jira-attach", *sys.argv[4:]]
ja.main()
"""


def child_main_command(gateway, timeout, *args):
    """main() in a child whose gateway is a test server and whose settings and token are
    stubbed, so no config file or keychain is touched."""
    return [sys.executable, "-c", CHILD_MAIN, SCRIPT, gateway, str(timeout), *args]


def run_main_against_test_server(*args):
    return subprocess.run(child_main_command(BASE, ja.HTTP_TIMEOUT, *args),
                          capture_output=True, text=True, timeout=30)


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


class PartialAttach(TemporaryDirectoryTest):
    """Attach-only mode has no rollback, so when a later upload fails the files already
    attached must still be reported, or a retry would attach them again."""

    def setUp(self):
        super().setUp()
        UPLOADED.clear()
        self.files = []
        for name in ("first.png", "rejected.png", "never.png"):
            path = self.directory / name
            path.write_bytes(b"png")
            self.files.append(str(path))

    def test_files_attached_before_a_failure_are_reported(self):
        result = run_main_against_test_server("MHMAPPS-1", *self.files)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("Attached 1 file(s) to MHMAPPS-1:\n"
                                                 "  first.png  (2 KB)\nJira returned 400"),
                        result.stderr)
        self.assertIn("rejected.png rejected", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(UPLOADED, ["first.png", "rejected.png"])

    def test_first_upload_failing_reports_nothing_attached(self):
        result = run_main_against_test_server("MHMAPPS-1", *self.files[1:])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("Jira returned 400"), result.stderr)
        self.assertIn("rejected.png rejected", result.stderr)

    def test_all_uploads_succeeding_is_unchanged(self):
        result = run_main_against_test_server("MHMAPPS-1", self.files[0], self.files[2])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "Attached 2 file(s) to MHMAPPS-1:\n  first.png  (2 KB)\n"
                                        "  never.png  (2 KB)\n"
                                        "  https://team.atlassian.net/browse/MHMAPPS-1\n")
        self.assertEqual(result.stderr, "")


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
                with raised.exception:
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


class RealOpenerOverTls(TemporaryDirectoryTest):
    """The plain-http tests cannot show the real opener following a redirect, since it
    refuses any redirect to http. These run a fresh copy of the script, its openers
    untouched, against an https server on 127.0.0.1 whose self-signed certificate is the
    only trusted root. The certificate names both 127.0.0.1 and localhost, so a redirect
    between them is a redirect to another host, as attachment content's redirect to
    api.media.atlassian.com is."""

    @classmethod
    def setUpClass(cls):
        openssl = shutil.which("openssl")
        if openssl is None:
            raise RuntimeError("the openssl command is needed to make the test certificate")
        # Made per run rather than committed: a committed key trips secret scanners, and
        # a committed certificate expires. The key never outlives this block.
        with tempfile.TemporaryDirectory() as directory:
            certificate, key = Path(directory, "cert.pem"), Path(directory, "key.pem")
            made = subprocess.run(
                [openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                 "-subj", "/CN=jira-attach-test",
                 "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost",
                 "-keyout", str(key), "-out", str(certificate)],
                capture_output=True, text=True, timeout=60)
            if made.returncode != 0:
                raise RuntimeError(f"openssl could not make the test certificate:\n{made.stderr}")
            server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            server_context.load_cert_chain(str(certificate), str(key))
            trusted_root = certificate.read_text()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        cls.addClassCleanup(server.server_close)
        server.daemon_threads = True
        server.socket = server_context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        cls.addClassCleanup(server.shutdown)
        port = server.server_address[1]
        cls.host, cls.other_host = f"127.0.0.1:{port}", f"localhost:{port}"
        cls.base, cls.other_base = f"https://{cls.host}", f"https://{cls.other_host}"
        # PEP 476's documented hook for the context urllib uses when given none. Python
        # 3.9 calls it per connection and 3.12 when an opener is built, so it stays
        # replaced for the whole class and the script is loaded after. Verification
        # stays on, host name check included; only the trusted roots change.
        # (SSL_CERT_FILE would avoid the private name, but Python 3.9 on LibreSSL
        # ignores it.)
        cls.addClassCleanup(setattr, ssl, "_create_default_https_context",
                            ssl._create_default_https_context)
        ssl._create_default_https_context = functools.partial(ssl.create_default_context,
                                                              cadata=trusted_root)
        cls.script = load_script_copy()

    def setUp(self):
        super().setUp()
        REQUESTS.clear()

    def requests(self):
        return requests_to(self.host, self.other_host)

    def test_read_follows_same_host_redirect_keeping_token(self):
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status):
                REQUESTS.clear()
                start = f"/goto/{status}/{self.base}/landing"
                result = self.script.api("GET", f"{self.base}{start}", CREDENTIALS)
                self.assertEqual(result, [{"id": "1", "filename": "landing.png"}])
                self.assertEqual(self.requests(), [("GET", self.host, start, True),
                                                   ("GET", self.host, "/landing", True)])

    def test_read_follows_cross_host_redirect_dropping_token(self):
        start = f"/goto/303/{self.other_base}/landing"
        result = self.script.api("GET", f"{self.base}{start}", CREDENTIALS)
        self.assertEqual(result, [{"id": "1", "filename": "landing.png"}])
        self.assertEqual(self.requests(), [("GET", self.host, start, True),
                                           ("GET", self.other_host, "/landing", False)])

    def test_fetch_follows_cross_host_redirect_dropping_token(self):
        destination = self.directory / "a.bin"
        start = f"/goto/303/{self.other_base}/binary"
        self.assertEqual(self.script.fetch(f"{self.base}{start}", CREDENTIALS, destination),
                         len(BINARY_BODY))
        self.assertEqual(destination.read_bytes(), BINARY_BODY)
        self.assertEqual(self.requests(), [("GET", self.host, start, True),
                                           ("GET", self.other_host, "/binary", False)])

    def test_read_refuses_redirect_to_http(self):
        start = f"/goto/302/{BASE}/landing"
        with self.assertRaises(SystemExit) as raised:
            self.script.api("GET", f"{self.base}{start}", CREDENTIALS)
        self.assertIn("non-https", str(raised.exception.code))
        self.assertEqual(self.requests(), [("GET", self.host, start, True)])
        self.assertEqual(requests_to(BASE.split("//")[1]), [])

    def assertNotFollowed(self, method, path):
        # Exactly the one request: following would GET /landing.
        self.assertEqual(self.requests(), [(method, self.host, path, True)])

    def test_writes_never_follow(self):
        # urllib itself follows only a 301/302/303 POST (as a GET); the other cases
        # guard against its ever following more.
        for method in ("POST", "PUT"):
            for status in (301, 302, 303, 307, 308):
                with self.subTest(method=method, status=status):
                    REQUESTS.clear()
                    path = f"/{status}/issue/X-1/comment"
                    with self.assertRaises(self.script._Ambiguous) as raised:
                        self.script.api(method, f"{self.base}{path}", CREDENTIALS, json_body={})
                    # Naming the redirect rules out the network-error ambiguity a failed
                    # TLS handshake would also raise.
                    self.assertIn(f"returned {status} ", str(raised.exception))
                    self.assertIn("(redirect to /landing)", str(raised.exception))
                    self.assertNotFollowed(method, path)

    def test_upload_never_follows(self):
        upload = self.directory / "shot.png"
        upload.write_bytes(b"png")
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status):
                REQUESTS.clear()
                with self.assertRaises(SystemExit) as raised:
                    self.script.attach_one(f"{self.base}/{status}", CREDENTIALS, "X-1", upload)
                self.assertIn("(redirect to /landing)", str(raised.exception.code))
                self.assertIn("may or may not have been attached", str(raised.exception.code))
                self.assertNotFollowed("POST", f"/{status}/issue/X-1/attachments")


class UploadNetworkFailures(TemporaryDirectoryTest):
    """urllib wraps in URLError only a failure while connecting or sending, when Jira
    never received the whole upload; one while awaiting or reading the response escapes
    unwrapped after the whole upload was sent, so the file may have been stored."""

    # Larger than the client's send buffer and the server's receive buffer combined, so
    # the send is still under way when the server closes without reading.
    LARGER_THAN_SOCKET_BUFFERS = 32 * 1024 * 1024

    def setUp(self):
        super().setUp()
        self.upload = self.directory / "shot.png"
        self.upload.write_bytes(b"png")

    def upload_failure(self, base, upload=None):
        with self.assertRaises(SystemExit) as raised:
            ja.attach_one(base, CREDENTIALS, "X-1", upload or self.upload)
        return str(raised.exception.code)

    def assert_uncertain(self, message):
        self.assertIn("may or may not have been attached — verify X-1's attachments", message)

    def assert_never_received(self, message):
        self.assertIn("Jira never received the complete upload", message)
        self.assertNotIn("may or may not", message)

    def test_connection_closed_after_upload_is_uncertain(self):
        message = self.upload_failure(f"{BASE}/drop")
        self.assertIn("Got no usable response", message)
        self.assert_uncertain(message)

    def test_timeout_after_upload_is_uncertain(self):
        original_timeout = ja.HTTP_TIMEOUT
        ja.HTTP_TIMEOUT = 0.5
        try:
            message = self.upload_failure(f"{BASE}/hang")
        finally:
            ja.HTTP_TIMEOUT = original_timeout
        self.assertIn("Timed out", message)
        self.assert_uncertain(message)

    def test_non_json_success_is_uncertain(self):
        message = self.upload_failure(f"{BASE}/notjson")
        self.assertIn("200 OK", message)
        self.assertIn("not JSON", message)
        self.assert_uncertain(message)

    def test_unreachable_gateway_never_received_it(self):
        unused = http.server.HTTPServer(("127.0.0.1", 0), _Handler)
        closed_port = unused.server_address[1]
        unused.server_close()
        self.assert_never_received(self.upload_failure(f"http://127.0.0.1:{closed_port}"))

    def test_connection_closed_during_upload_never_received_it(self):
        large_upload = self.directory / "large.bin"
        large_upload.write_bytes(bytes(self.LARGER_THAN_SOCKET_BUFFERS))
        self.addCleanup(large_upload.unlink)
        self.assert_never_received(self.upload_failure(f"{BASE}/reset", large_upload))

    def test_invalid_url_sends_nothing(self):
        message = self.upload_failure(f"{BASE}/a b")
        self.assertIn("nothing was sent to Jira", message)
        self.assertNotIn("may or may not", message)

    def test_cut_off_or_non_utf8_reply_after_upload_is_uncertain(self):
        for answer in ("short", "non-utf8"):
            with self.subTest(answer=answer):
                self.assert_uncertain(self.upload_failure(f"{BASE}/{answer}"))


class LostWriteAnswers(unittest.TestCase):
    """Once the whole request was sent, a lost, cut-off or unparseable answer says
    nothing certain about whether a write committed."""

    def setUp(self):
        self.original_timeout = ja.HTTP_TIMEOUT
        ja.HTTP_TIMEOUT = TEST_TIMEOUT

    def tearDown(self):
        ja.HTTP_TIMEOUT = self.original_timeout

    def test_lost_answer_to_write_is_uncertain(self):
        for method in ("POST", "PUT"):
            for answer in LOST_ANSWERS:
                with self.subTest(method=method, answer=answer):
                    with self.assertRaises(ja._Ambiguous) as raised:
                        ja.api(method, f"{BASE}/{answer}/issue/X-1/comment", CREDENTIALS, json_body={})
                    self.assertIn("may or may not have committed", str(raised.exception))

    def test_invalid_url_write_sends_nothing(self):
        with self.assertRaises(SystemExit) as raised:
            ja.api("PUT", f"{BASE}/a b", CREDENTIALS, json_body={})
        self.assertIn("nothing was sent to Jira", str(raised.exception.code))

    def test_lost_or_unparseable_answer_to_read_is_definitive(self):
        for path, expected in (("/hang", "Timed out awaiting Jira's response to the GET"),
                               ("/binary", "the reply is not JSON")):
            with self.subTest(path=path):
                with self.assertRaises(SystemExit) as raised:
                    ja.api("GET", f"{BASE}{path}", CREDENTIALS)
                self.assertIn(expected, str(raised.exception.code))
                self.assertNotIn("may or may not", str(raised.exception.code))


class _FakeJira(http.server.BaseHTTPRequestHandler):
    """Just enough of Jira for the embed modes on issue X-1: its description, comment 5,
    uploads that become attachment 11, and the media id redirect. The server's
    `trouble` is (method, path, answer): the first such request commits as usual, then
    its answer is lost as LOST_ANSWERS names it, or replaced by a Ctrl-C sent to the
    client ("interrupt"); or it is rejected with a 400 ("reject")."""

    def log_message(self, *args):
        pass

    def _answer(self, status, payload=None, headers=()):
        body = json.dumps(payload).encode() if payload is not None else b""
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        server = self.server
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        body = json.loads(raw) if self.headers.get("Content-Type") == "application/json" else None
        path = re.sub(r"^/CLOUD/rest/api", "", self.path)
        request = (self.command, path)
        trouble = None
        if server.trouble[:2] == request:
            # Once only: rollback's restore PUT goes to the same path.
            trouble, server.trouble = server.trouble[2], (None, None, None)
        if trouble == "reject":
            return self._answer(400, {"errorMessages": ["rejected"]})
        if trouble == "interrupt" and self.command == "GET":
            server.interrupt_client()
            return time.sleep(WRITE_HANG)
        if request == ("POST", "/3/issue/X-1/attachments"):
            server.attachments.add("11")
            answer = (200, [{"id": "11", "filename": "notes.txt", "size": 5}])
        elif request == ("GET", "/3/attachment/content/11"):
            return self._answer(302, headers=[("Location", f"https://media/file/{FAKE_MEDIA_ID}/binary")])
        elif request == ("GET", "/3/issue/X-1?fields=description"):
            answer = (200, {"fields": {"description": server.description}})
        elif self.command == "PUT" and path in ("/2/issue/X-1", "/3/issue/X-1"):
            server.description = _as_adf(body["fields"]["description"])
            answer = (204, None)
        elif request == ("GET", "/3/issue/X-1/comment/5"):
            answer = (200, {"id": "5", "body": server.comment})
        elif request == ("PUT", "/3/issue/X-1/comment/5"):
            server.comment = body["body"]
            answer = (200, {"id": "5"})
        elif request == ("DELETE", "/3/attachment/11"):
            server.attachments.discard("11")
            answer = (204, None)
        else:
            answer = (404, None)
        if trouble == "interrupt":
            server.interrupt_client()
            return time.sleep(WRITE_HANG)
        if trouble:
            return LOST_ANSWERS[trouble](self)
        self._answer(*answer)

    do_GET = do_POST = do_PUT = do_DELETE = _handle


FAKE_MEDIA_ID = "12345678-1234-1234-1234-123456789abc"
ORIGINAL_DESCRIPTION = {"type": "doc", "version": 1,
                        "content": [{"type": "paragraph", "content": [{"type": "text", "text": "old"}]}]}


def _as_adf(description):
    """What Jira stores for a description PUT: ADF as given, or wiki converted one
    paragraph per blank-line-separated block (enough for the splice to find its tokens)."""
    if not isinstance(description, str):
        return description
    return {"type": "doc", "version": 1,
            "content": [{"type": "paragraph", "content": [{"type": "text", "text": block}]}
                        for block in description.split("\n\n")]}


def _references_media(document):
    return any(node["type"] in ("mediaSingle", "mediaGroup") for node in document["content"])


class RollbackAfterLostAnswer(TemporaryDirectoryTest):
    """An append's PUT is the write that makes content reference the uploads, and
    rollback has no undo for it. If its answer is lost, or Ctrl-C arrives once it is
    sent, it may have committed, so deleting the uploads could break the issue."""

    APPEND_MODES = {"description": ("--append-description",), "comment": ("--append-comment", "5")}
    APPEND_WRITES = {"description": ("PUT", "/3/issue/X-1"), "comment": ("PUT", "/3/issue/X-1/comment/5")}

    def setUp(self):
        super().setUp()
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _FakeJira)
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.upload = self.directory / "notes.txt"
        self.upload.write_text("notes")

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def run_main(self, trouble, *mode):
        """Run a whole embed in a child (so Ctrl-C is a real SIGINT); returns stderr."""
        self.server.description = json.loads(json.dumps(ORIGINAL_DESCRIPTION))
        self.server.comment = {"type": "doc", "version": 1, "content": []}
        self.server.attachments = set()
        self.server.trouble = trouble
        child = subprocess.Popen(
            child_main_command(f"http://127.0.0.1:{self.server.server_address[1]}", TEST_TIMEOUT,
                               "X-1", *mode, "--text", "see the notes", "--file", str(self.upload)),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.server.interrupt_client = lambda: child.send_signal(signal.SIGINT)
        _, stderr = child.communicate(timeout=30)
        self.assertNotEqual(child.returncode, 0, stderr)
        return stderr

    def content(self, target):
        return self.server.description if target == "description" else self.server.comment

    def test_lost_answer_to_append_keeps_uploads(self):
        for target, mode in self.APPEND_MODES.items():
            for answer in LOST_ANSWERS:
                with self.subTest(target=target, answer=answer):
                    stderr = self.run_main((*self.APPEND_WRITES[target], answer), *mode)
                    self.assertTrue(_references_media(self.content(target)), stderr)
                    self.assertIn("11", self.server.attachments, stderr)
                    self.assertIn("Left partial work in place", stderr)
                    self.assertIn("the write may or may not have committed", stderr)
                    self.assertNotIn("Traceback", stderr)

    def test_ctrl_c_once_append_sent_keeps_uploads(self):
        for target, mode in self.APPEND_MODES.items():
            with self.subTest(target=target):
                stderr = self.run_main((*self.APPEND_WRITES[target], "interrupt"), *mode)
                self.assertTrue(_references_media(self.content(target)), stderr)
                self.assertIn("11", self.server.attachments, stderr)
                self.assertIn("Left partial work in place", stderr)

    def test_rejected_append_still_removes_uploads(self):
        for target, mode in self.APPEND_MODES.items():
            with self.subTest(target=target):
                stderr = self.run_main((*self.APPEND_WRITES[target], "reject"), *mode)
                self.assertNotIn("11", self.server.attachments, stderr)
                self.assertIn("removed 1/1 attachment(s)", stderr)

    def test_ctrl_c_before_any_content_write_removes_uploads(self):
        stderr = self.run_main(("GET", "/3/issue/X-1?fields=description", "interrupt"),
                               "--append-description")
        self.assertEqual(self.server.description, ORIGINAL_DESCRIPTION)
        self.assertNotIn("11", self.server.attachments, stderr)
        self.assertIn("removed 1/1 attachment(s)", stderr)

    def test_ctrl_c_after_replace_still_restores_and_removes_uploads(self):
        # A replace records its undo before writing, so rolling back stays safe.
        stderr = self.run_main(("PUT", "/3/issue/X-1", "interrupt"), "--replace-description")
        self.assertEqual(self.server.description, ORIGINAL_DESCRIPTION, stderr)
        self.assertNotIn("11", self.server.attachments, stderr)
        self.assertIn("restored prior content; removed 1/1 attachment(s)", stderr)


class RollbackOutcomes(unittest.TestCase):
    """Attachments are deleted only after content cleanup definitely applied, and a
    cleanup request answered with a 3xx, a 5xx or nothing is reported as uncertain,
    not as failed: it may have applied."""
    LEFT = "LEFT 2 attachment(s) in place (content cleanup not confirmed; remove manually if orphaned).\n"

    def run_rollback(self, base3, *, restore_status=None, comment_id=None):
        """Content cleanup and attachment deletes go to base3; a restore goes to its own
        status. Returns the rollback report."""
        REQUESTS.clear()
        rollback = ja.Rollback(base3, CREDENTIALS, "X-1")
        rollback.attachment_ids = ["11", "12"]
        rollback.delete_comment_id = comment_id
        if restore_status is not None:
            rollback.restore = (f"{BASE}/{restore_status}/issue/X-1", {"fields": {"description": None}})
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            rollback.run(destructive=True)
        return report.getvalue()
    def attachment_deletes(self):
        return [path for method, _, path, _ in REQUESTS if method == "DELETE" and "/attachment/" in path]
    def test_attachments_kept_unless_restore_definitely_applied(self):
        for status in (301, 303, 307, 400, 404, 409, 500, 503, "drop"):
            with self.subTest(status=status):
                report = self.run_rollback(f"{BASE}/204", restore_status=status)
                self.assertEqual(self.attachment_deletes(), [])
                self.assertIn("LEFT 2 attachment(s) in place", report)

    def test_attachments_kept_unless_comment_delete_definitely_applied(self):
        for status in (303, 403, 503, "drop"):
            with self.subTest(status=status):
                self.run_rollback(f"{BASE}/{status}", comment_id="9")
                self.assertEqual(self.attachment_deletes(), [])

    def test_restore_reports(self):
        for status, expected in ((204, "restored prior content; removed 2/2 attachment(s).\n"),
                                 (400, "FAILED to restore prior content; " + self.LEFT),
                                 (404, "FAILED to restore prior content; " + self.LEFT),
                                 (303, "MAY OR MAY NOT have restored prior content; " + self.LEFT),
                                 (500, "MAY OR MAY NOT have restored prior content; " + self.LEFT),
                                 ("drop", "MAY OR MAY NOT have restored prior content; " + self.LEFT)):
            with self.subTest(status=status):
                self.assertEqual(self.run_rollback(f"{BASE}/204", restore_status=status),
                                 "Rollback: " + expected)

    def test_comment_delete_reports(self):
        for status, expected in ((204, "deleted comment 9; removed 2/2 attachment(s).\n"),
                                 (404, "FAILED to delete comment 9; " + self.LEFT),
                                 (303, "MAY OR MAY NOT have deleted comment 9; " + self.LEFT),
                                 (503, "MAY OR MAY NOT have deleted comment 9; " + self.LEFT)):
            with self.subTest(status=status):
                self.assertEqual(self.run_rollback(f"{BASE}/{status}", comment_id="9"),
                                 "Rollback: " + expected)

    def test_attachment_delete_reports(self):
        for status, expected in ((204, "Rollback: removed 2/2 attachment(s).\n"),
                                 (404, "Rollback: removed 0/2 attachment(s).\n"),
                                 (303, "Rollback: removed 0/2 attachment(s) "
                                       "(2 more MAY OR MAY NOT have been removed).\n"),
                                 (503, "Rollback: removed 0/2 attachment(s) "
                                       "(2 more MAY OR MAY NOT have been removed).\n")):
            with self.subTest(status=status):
                self.assertEqual(self.run_rollback(f"{BASE}/{status}"), expected)
                self.assertEqual(len(self.attachment_deletes()), 2)


# --------------------------------------------------------------------------- #
# Error messages
# --------------------------------------------------------------------------- #

class HttpErrorMessages(unittest.TestCase):
    def message_for(self, code, body):
        error = urllib.error.HTTPError("https://x/y", code, "Reason", email.message.Message(),
                                       io.BytesIO(body))
        with error, self.assertRaises(SystemExit) as raised:
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
