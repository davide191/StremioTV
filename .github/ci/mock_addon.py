#!/usr/bin/env python3
"""Faux add-on Stremio de flux pour les tests UI tvOS (CI).

Répond à toute requête `/stream/...` par la même liste : un torrent, un flux
HTTP direct (lisible), puis un autre torrent. Le simulateur partage le réseau
de la machine hôte : l'app l'atteint via http://localhost:<port>.

Usage : python3 .github/ci/mock_addon.py 8765
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MANIFEST = {
    "id": "ci.mock.streams",
    "name": "Mock Streams",
    "version": "1.0.0",
    "resources": ["stream"],
    "types": ["movie", "series"],
    "catalogs": [],
}

STREAMS = {
    "streams": [
        {"name": "MockTorrentTop", "title": "4K torrent", "infoHash": "a" * 40},
        {
            "name": "MockDirect",
            "title": "Direct HLS (Apple bipbop sample)",
            "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8",
        },
        {"name": "MockTorrentBottom", "title": "720p torrent", "infoHash": "b" * 40},
    ]
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/manifest.json":
            body = MANIFEST
        elif self.path.startswith("/stream/"):
            body = STREAMS
        else:
            self.send_error(404)
            return
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("", port), Handler).serve_forever()
