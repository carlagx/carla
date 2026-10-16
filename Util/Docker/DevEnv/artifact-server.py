#!/usr/bin/env python3
"""Download server for build artifacts: directory listing, single files with
resume (Range), whole directories as streamed zip (?zip=1). Basic auth."""
import base64
import hmac
import html
import os
import posixpath
import re
import shutil
import time
import urllib.parse
import zipfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.realpath(os.environ.get("ARTIFACT_DIR", "/artifacts"))
USER = os.environ.get("ARTIFACT_USER", "carla")
PASSWORD = os.environ.get("ARTIFACT_PASSWORD", "")
PORT = int(os.environ.get("ARTIFACT_PORT", "8081"))


class Stream:
    """Write-only file object for ZipFile to stream into the socket."""

    def __init__(self, wfile):
        self.wfile, self.pos = wfile, 0

    def write(self, data):
        self.wfile.write(data)
        self.pos += len(data)
        return len(data)

    def tell(self):
        return self.pos

    def flush(self):
        self.wfile.flush()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def authorized(self):
        header = self.headers.get("Authorization", "")
        if PASSWORD and header.startswith("Basic "):
            try:
                user, _, pw = base64.b64decode(header[6:]).decode().partition(":")
            except Exception:
                return False
            return hmac.compare_digest(user, USER) and hmac.compare_digest(pw, PASSWORD)
        return not PASSWORD

    def do_GET(self):
        if not self.authorized():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="CARLA artifacts"')
            self.end_headers()
            return
        parts = urllib.parse.urlsplit(self.path)
        fs_path = os.path.realpath(self.translate_path(parts.path))
        if fs_path != ROOT and not fs_path.startswith(ROOT + os.sep):
            return self.send_error(403)
        if os.path.isdir(fs_path):
            if "zip" in urllib.parse.parse_qs(parts.query):
                return self.send_zip(fs_path)
            return self.send_listing(fs_path, parts.path)
        if os.path.isfile(fs_path):
            return self.send_file(fs_path)
        self.send_error(404)

    do_HEAD = do_GET

    def send_file(self, path):
        size = os.path.getsize(path)
        start, end = 0, size - 1
        match = re.match(r"bytes=(\d*)-(\d*)$", self.headers.get("Range", ""))
        if match and (match.group(1) or match.group(2)):
            if match.group(1):
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else end
            else:
                start = max(0, size - int(match.group(2)))
            if start > end or start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else:
            self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Disposition", f'attachment; filename="{os.path.basename(path)}"')
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = f.read(min(1 << 20, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def send_zip(self, directory):
        name = os.path.basename(directory.rstrip(os.sep)) or "artifacts"
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Disposition", f'attachment; filename="{name}.zip"')
        self.send_header("Connection", "close")  # length unknown: body ends at close
        self.end_headers()
        self.close_connection = True
        if self.command == "HEAD":
            return
        with zipfile.ZipFile(Stream(self.wfile), "w", zipfile.ZIP_DEFLATED, compresslevel=1) as zf:
            for base, _, files in os.walk(directory):
                for fname in sorted(files):
                    full = os.path.join(base, fname)
                    if os.path.isfile(full):
                        zf.write(full, os.path.relpath(full, directory))

    def send_listing(self, directory, url_path):
        url_path = posixpath.normpath(urllib.parse.unquote(url_path)).rstrip("/") + "/"
        if url_path == "//":
            url_path = "/"
        rows = []
        if url_path != "/":
            rows.append('<tr><td><a href="../">../</a></td><td></td><td></td><td></td></tr>')
        entries = sorted(os.scandir(directory), key=lambda e: (not e.is_dir(), e.name))
        for e in entries:
            href = urllib.parse.quote(e.name) + ("/" if e.is_dir() else "")
            st = e.stat()
            size = "" if e.is_dir() else f"{st.st_size / 1e6:,.1f} MB"
            zip_link = f'<a href="{href}?zip=1">zip</a>' if e.is_dir() else ""
            rows.append(
                f'<tr><td><a href="{href}">{html.escape(e.name)}{"/" if e.is_dir() else ""}</a></td>'
                f"<td>{size}</td><td>{time.strftime('%Y-%m-%d %H:%M', time.localtime(st.st_mtime))}</td>"
                f"<td>{zip_link}</td></tr>"
            )
        host = self.headers.get("Host", "HOST:8081")
        page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>CARLA artifacts</title>
<style>body{{font:15px system-ui;margin:2rem auto;max-width:60rem;padding:0 1rem}}
td{{padding:.25rem .8rem .25rem 0}}code{{background:#eee;padding:.1rem .3rem}}</style>
<h1>CARLA artifacts: {html.escape(url_path)}</h1>
<table>{''.join(rows)}</table>
<p>Download with curl (resumable):<br>
<code>curl -C - -O -u {USER}:PASSWORD http://{html.escape(host)}{html.escape(url_path)}FILE</code><br>
Whole folder: <code>curl -u {USER}:PASSWORD -o latest.zip "http://{html.escape(host)}{html.escape(url_path)}?zip=1"</code></p>"""
        data = page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    os.makedirs(ROOT, exist_ok=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
