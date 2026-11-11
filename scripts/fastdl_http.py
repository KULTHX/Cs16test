#!/usr/bin/env python3
"""HTTP FastDL origin with transparent GoldSrc/Xash3D .bz2 support.

GoldSrc clients prefer <file>.bz2 when it exists. The server creates that
representation on first request and caches it outside the public root; the
original assets remain untouched.
"""
from __future__ import annotations

import argparse
import bz2
import hashlib
import http.server
import os
from pathlib import Path
from urllib.parse import unquote, urlsplit


class FastDLHandler(http.server.SimpleHTTPRequestHandler):
    server_version = "CS16-FastDL/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        # Keep the action log useful without dumping request headers or secrets.
        super().log_message(fmt, *args)

    def _safe_source(self, request_path: str) -> tuple[Path | None, bool]:
        path = unquote(urlsplit(request_path).path)
        if not path.startswith("/"):
            return None, False
        relative = Path(path.lstrip("/"))
        if relative.is_absolute() or ".." in relative.parts:
            return None, False
        compressed = relative.name.lower().endswith(".bz2")
        source_relative = Path(str(relative)[:-4]) if compressed else relative
        root = Path(self.directory).resolve()
        source = (root / source_relative).resolve()
        try:
            source.relative_to(root)
        except ValueError:
            return None, compressed
        if not source.is_file():
            return None, compressed
        return source, compressed

    def _compressed_path(self, source: Path) -> Path:
        cache_root = Path(self.server.fastdl_cache).resolve()  # type: ignore[attr-defined]
        root = Path(self.directory).resolve()
        relative = source.relative_to(root)
        digest = hashlib.sha256(str(relative).encode("utf-8")).hexdigest()[:16]
        cached = cache_root / relative.parent / f"{relative.name}.{digest}.bz2"
        cached.parent.mkdir(parents=True, exist_ok=True)
        if not cached.exists() or cached.stat().st_mtime_ns < source.stat().st_mtime_ns:
            temporary = cached.with_suffix(cached.suffix + ".tmp")
            with source.open("rb") as source_file, temporary.open("wb") as output:
                compressor = bz2.BZ2Compressor(9)
                while True:
                    block = source_file.read(1024 * 1024)
                    if not block:
                        break
                    output.write(compressor.compress(block))
                output.write(compressor.flush())
            os.replace(temporary, cached)
            print(f"FastDL compressed: /{relative} -> {cached.stat().st_size} bytes", flush=True)
        return cached

    def do_GET(self) -> None:
        source, compressed = self._safe_source(self.path)
        if compressed:
            if source is None:
                self.send_error(404, "FastDL source file not found")
                return
            try:
                cached = self._compressed_path(source)
            except (OSError, ValueError) as exc:
                self.send_error(500, f"FastDL compression failed: {exc}")
                return
            original_path = self.path
            self.path = "/" + str(cached.relative_to(Path(self.server.fastdl_cache).resolve()))  # type: ignore[attr-defined]
            self.directory = str(Path(self.server.fastdl_cache).resolve())
            try:
                super().do_GET()
            finally:
                self.path = original_path
                self.directory = str(Path(self.server.fastdl_root).resolve())  # type: ignore[attr-defined]
            return
        super().do_GET()

    def do_HEAD(self) -> None:
        self.do_GET()


class FastDLServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    cache = Path(args.cache).resolve()
    root.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    handler = lambda *handler_args, **handler_kwargs: FastDLHandler(
        *handler_args, directory=str(root), **handler_kwargs
    )
    server = FastDLServer((args.bind, args.port), handler)
    server.fastdl_root = str(root)  # type: ignore[attr-defined]
    server.fastdl_cache = str(cache)  # type: ignore[attr-defined]
    print(f"FastDL origin listening on {args.bind}:{args.port}; bz2 cache: {cache}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
