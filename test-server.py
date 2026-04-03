#!/usr/bin/env python3
"""
Simple HTTP server for testing video playback in NexusPVR.

Modes:
  recording (default) — Serves the file with range request support (seeking, known size).
                         Mimics how recorded videos are served by NextPVR/Dispatcharr.
  stream              — Streams the file continuously without Content-Length or range
                         support, looping when it reaches the end. Mimics live TV.

Usage:
    python3 test-server.py /path/to/video.mkv [port] [--stream]

Then in NexusPVR, play: http://<your-ip>:<port>/video
"""

import sys
import os
import argparse
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

parser = argparse.ArgumentParser(description="Test video server for NexusPVR")
parser.add_argument("video", help="Path to video file")
parser.add_argument("port", nargs="?", type=int, default=9000, help="Port (default: 9000)")
parser.add_argument("--stream", action="store_true",
                    help="Stream mode: continuous output without range support (mimics live TV)")
parser.add_argument("--bitrate", type=float, default=0,
                    help="Stream bitrate in Mbps (default: auto-detect from file size/duration)")
args = parser.parse_args()

VIDEO_PATH = os.path.abspath(args.video)
PORT = args.port
STREAM_MODE = args.stream

if not os.path.isfile(VIDEO_PATH):
    print(f"Error: {VIDEO_PATH} not found")
    sys.exit(1)

VIDEO_SIZE = os.path.getsize(VIDEO_PATH)
EXT = os.path.splitext(VIDEO_PATH)[1].lower()
CONTENT_TYPE = {
    ".mkv": "video/x-matroska",
    ".mp4": "video/mp4",
    ".ts": "video/mp2t",
    ".avi": "video/x-msvideo",
    ".webm": "video/webm",
    ".mov": "video/quicktime",
}.get(EXT, "application/octet-stream")

# Bitrate for throttled streaming (bits per second).
# Auto-detected from file using ffprobe, or estimated from file size.
def detect_bitrate():
    if args.bitrate > 0:
        return int(args.bitrate * 1_000_000)
    # Try ffprobe first
    import subprocess
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "quiet", "-show_entries", "format=duration,bit_rate",
             "-of", "default=noprint_wrappers=1", VIDEO_PATH],
            capture_output=True, text=True, timeout=10
        )
        info = {}
        for line in result.stdout.strip().split("\n"):
            if "=" in line:
                k, v = line.split("=", 1)
                info[k] = v
        if "bit_rate" in info and info["bit_rate"] != "N/A":
            br = int(info["bit_rate"])
            print(f"Bitrate: {br / 1_000_000:.1f} Mbps (from ffprobe)")
            return br
        if "duration" in info and info["duration"] != "N/A":
            duration = float(info["duration"])
            br = int(VIDEO_SIZE * 8 / duration)
            print(f"Bitrate: {br / 1_000_000:.1f} Mbps (estimated from duration)")
            return br
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        pass
    # Fallback: assume 2 hour video
    br = int(VIDEO_SIZE * 8 / 7200)
    print(f"Bitrate: {br / 1_000_000:.1f} Mbps (estimated, assuming 2h)")
    return br

STREAM_BITRATE = detect_bitrate() if STREAM_MODE else 5_000_000


class RecordingHandler(BaseHTTPRequestHandler):
    """Serves a video file with range requests — mimics recorded video playback."""

    def do_GET(self):
        if self.path not in ("/video", "/"):
            self.send_error(404)
            return

        range_header = self.headers.get("Range")
        if range_header:
            self._serve_range(range_header)
        else:
            self._serve_full()

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.send_header("Content-Length", str(VIDEO_SIZE))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

    def _serve_full(self):
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.send_header("Content-Length", str(VIDEO_SIZE))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(VIDEO_PATH, "rb") as f:
            while chunk := f.read(1024 * 1024):
                try:
                    self.wfile.write(chunk)
                except BrokenPipeError:
                    break

    def _serve_range(self, range_header):
        try:
            range_spec = range_header.replace("bytes=", "")
            start_str, end_str = range_spec.split("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else VIDEO_SIZE - 1
        except ValueError:
            self.send_error(416, "Invalid range")
            return

        if start >= VIDEO_SIZE:
            self.send_error(416, "Range not satisfiable")
            return

        end = min(end, VIDEO_SIZE - 1)
        length = end - start + 1

        self.send_response(206)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{VIDEO_SIZE}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

        with open(VIDEO_PATH, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk_size = min(1024 * 1024, remaining)
                chunk = f.read(chunk_size)
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except BrokenPipeError:
                    break
                remaining -= len(chunk)

    def log_message(self, format, *args):
        print(f"{self.address_string()} {args[0]}")


class StreamHandler(BaseHTTPRequestHandler):
    """Streams video continuously without Content-Length — mimics live TV."""

    def do_GET(self):
        if self.path not in ("/video", "/"):
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        # Stream at 1.2x bitrate to keep the client buffer healthy
        bytes_per_second = int(STREAM_BITRATE * 1.2) // 8
        chunk_size = max(188 * 1024, bytes_per_second // 10)  # ~100ms worth of data per chunk
        sleep_per_chunk = chunk_size / bytes_per_second

        with open(VIDEO_PATH, "rb") as f:
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    # Loop back to start to simulate continuous live stream
                    f.seek(0)
                    print("  [stream] looping back to start")
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                try:
                    self.wfile.write(f"{len(chunk):x}\r\n".encode())
                    self.wfile.write(chunk)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
                except BrokenPipeError:
                    break
                time.sleep(sleep_per_chunk)

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.end_headers()

    def log_message(self, format, *args):
        print(f"{self.address_string()} {args[0]}")


if __name__ == "__main__":
    import socket
    hostname = socket.gethostname()
    try:
        local_ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        local_ip = "localhost"

    mode = "stream (live TV)" if STREAM_MODE else "recording"
    handler = StreamHandler if STREAM_MODE else RecordingHandler

    print(f"Serving: {VIDEO_PATH}")
    print(f"Size:    {VIDEO_SIZE / (1024*1024):.1f} MB")
    print(f"Type:    {CONTENT_TYPE}")
    print(f"Mode:    {mode}")
    if STREAM_MODE:
        print(f"Rate:    {STREAM_BITRATE / 1_000_000:.1f} Mbps (streaming at 1.2x)")
    print(f"URL:     http://{local_ip}:{PORT}/video")
    print(f"         http://localhost:{PORT}/video")
    print()

    class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
        daemon_threads = True

    server = ThreadedHTTPServer(("0.0.0.0", PORT), handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
