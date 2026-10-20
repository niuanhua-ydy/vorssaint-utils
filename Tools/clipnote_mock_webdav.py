#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""A minimal WebDAV server that behaves like Jianguoyun, for the ClipNote sync tests.
Usage: python3 Tools/clipnote_mock_webdav.py <storage folder> [port] [cert.pem key.pem]
Given a certificate it serves HTTPS (for the self-signed NAS case).
User test@example.com, password app-password, address http://127.0.0.1:<port>/dav/
"""
import base64, os, sys, shutil
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import unquote, quote

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
AUTH = "Basic " + base64.b64encode(b"test@example.com:app-password").decode()
PREFIX = "/dav/"
os.makedirs(ROOT, exist_ok=True)
STATS = {"requests": 0}

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def fs(self):
        path = unquote(self.path.split("?")[0])
        assert path.startswith(PREFIX)
        return os.path.join(ROOT, path[len(PREFIX):])

    def reply(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def check(self):
        STATS["requests"] += 1
        if self.headers.get("Authorization") != AUTH:
            self.reply(401, b"unauthorized")
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def missing(self, p):
        # 与坚果云一致：上级目录不存在时返回 409，否则 404
        self.reply(409 if not os.path.isdir(os.path.dirname(p.rstrip("/"))) else 404, b"not found")

    def do_GET(self):
        if not self.check(): return
        p = self.fs()
        if os.path.isfile(p):
            self.reply(200, open(p, "rb").read(), "application/octet-stream")
        else:
            self.missing(p)

    def do_PUT(self):
        if not self.check(): return
        data = self.body()
        p = self.fs()
        if not os.path.isdir(os.path.dirname(p)):
            self.reply(409, b"conflict"); return
        existed = os.path.exists(p)
        with open(p, "wb") as f: f.write(data)
        self.reply(204 if existed else 201)

    def do_MKCOL(self):
        if not self.check(): return
        self.body()
        p = self.fs().rstrip("/")
        if os.path.exists(p): self.reply(405, b"exists"); return
        if not os.path.isdir(os.path.dirname(p)): self.reply(409, b"conflict"); return
        os.mkdir(p); self.reply(201)

    def do_DELETE(self):
        if not self.check(): return
        p = self.fs().rstrip("/")
        if os.path.isdir(p): shutil.rmtree(p); self.reply(204)
        elif os.path.isfile(p): os.remove(p); self.reply(204)
        else: self.missing(p)

    def do_PROPFIND(self):
        if not self.check(): return
        self.body()
        p = self.fs().rstrip("/")
        if not os.path.exists(p): self.missing(p); return
        rel = os.path.relpath(p, ROOT)
        base = PREFIX + ("" if rel == "." else quote(rel) + "/")
        def entry(href, is_dir):
            rt = "<d:resourcetype><d:collection/></d:resourcetype>" if is_dir else "<d:resourcetype/>"
            return f"<d:response><d:href>{href}</d:href><d:propstat><d:prop>{rt}</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
        parts = [entry(base, os.path.isdir(p))]
        if os.path.isdir(p) and self.headers.get("Depth") == "1":
            for name in sorted(os.listdir(p)):
                full = os.path.join(p, name)
                parts.append(entry(base + quote(name) + ("/" if os.path.isdir(full) else ""), os.path.isdir(full)))
        xml = '<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">' + "".join(parts) + "</d:multistatus>"
        self.reply(207, xml.encode(), "application/xml; charset=utf-8")

server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
scheme = "http"
if len(sys.argv) > 4:
    import ssl
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(sys.argv[3], sys.argv[4])
    server.socket = context.wrap_socket(server.socket, server_side=True)
    scheme = "https"
print(f"mock webdav on {scheme}://127.0.0.1:{PORT}{PREFIX} root={ROOT}", flush=True)
server.serve_forever()
