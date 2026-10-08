#!/usr/bin/env python3
"""A stand-in OmniRoute: an OpenAI-compatible HTTP server for tests, so nothing needs the real one.

  stub_omniroute.py --port-file FILE [--model ID]... [--no-listing ID]...

Serves /v1/models (the ids given with --model) and /v1/chat/completions. A chat request for a
model that is not served gets a 404 error body, like the real thing. A served model answers with the
marker from the prompt ("Reply with exactly: X"), streaming it when the request asks for a stream.
--no-listing ids answer chats but are absent from /v1/models, which is the real server's behaviour for
some models. The chosen port is written to --port-file once the server is listening.
"""
import argparse, json, re, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ap = argparse.ArgumentParser()
ap.add_argument("--port-file", required=True)
ap.add_argument("--model", action="append", default=[])
ap.add_argument("--no-listing", action="append", default=[])
args = ap.parse_args()
LISTED = set(args.model)
SERVED = LISTED | set(args.no_listing)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            return self._json(200, {"object": "list", "data": [
                {"id": m, "object": "model", "context_length": 128000} for m in sorted(LISTED)]})
        self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._json(404, {"error": {"message": "not found"}})
        model = req.get("model", "")
        if model not in SERVED:
            return self._json(404, {"error": {"message": f"model {model} not served by the stub"}})
        text = " ".join(m.get("content", "") if isinstance(m.get("content"), str) else
                        " ".join(p.get("text", "") for p in m.get("content", []))
                        for m in req.get("messages", []))
        found = re.findall(r"Reply with exactly:\s*(\S+)", text)
        answer = found[-1] if found else "stub-answer"
        if req.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            def chunk(delta, finish=None):
                return "data: " + json.dumps({"id": "c1", "object": "chat.completion.chunk", "model": model,
                    "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}) + "\n\n"
            self.wfile.write(chunk({"role": "assistant", "content": ""}).encode())
            self.wfile.write(chunk({"content": answer}).encode())
            self.wfile.write(chunk({}, "stop").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            return
        self._json(200, {"id": "c1", "object": "chat.completion", "model": model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": answer}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(args.port_file, "w").write(str(srv.server_address[1]))
try:
    srv.serve_forever()
except KeyboardInterrupt:
    pass
