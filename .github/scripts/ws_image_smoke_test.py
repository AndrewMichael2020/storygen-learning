#!/usr/bin/env python3
import asyncio
import json
import os
import sys
import time
from urllib.parse import urlparse

try:
    import websockets
except ImportError:
    print("websockets package not installed", file=sys.stderr)
    sys.exit(2)


def build_ws_url(http_url: str, user_id: str = "ci-smoke") -> str:
    parsed = urlparse(http_url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"Unsupported URL scheme: {parsed.scheme}")
    ws_scheme = "wss" if parsed.scheme == "https" else "ws"
    netloc = parsed.netloc
    return f"{ws_scheme}://{netloc}/ws/{user_id}"


async def run_test():
    backend_url = os.environ.get("BACKEND_URL") or (sys.argv[1] if len(sys.argv) > 1 else None)
    if not backend_url:
        print("BACKEND_URL not provided", file=sys.stderr)
        return 2

    ws_url = build_ws_url(backend_url)
    print(f"Connecting to {ws_url}")

    timeout_seconds = int(os.environ.get("WS_SMOKE_TIMEOUT", "90"))
    # Allow larger frames (e.g., base64 images) by increasing or disabling max_size
    max_size_env = os.environ.get("WS_MAX_SIZE_BYTES", "10485760")  # default 10 MiB
    if str(max_size_env).strip().lower() in ("0", "none", "unlimited"):
        max_size = None
    else:
        try:
            max_size = int(max_size_env)
        except ValueError:
            max_size = 10 * 1024 * 1024  # fallback 10 MiB
    ping_interval = float(os.environ.get("WS_PING_INTERVAL", "20"))
    ping_timeout = float(os.environ.get("WS_PING_TIMEOUT", "20"))
    started = time.time()
    expected = int(os.environ.get("WS_EXPECTED_IMAGES", "1"))
    got_images = 0
    received_types = []

    async with websockets.connect(ws_url, ping_interval=ping_interval, ping_timeout=ping_timeout, max_size=max_size) as ws:
        # confirm handshake
        # send generate request
        payload = {"type": "generate_story", "data": "Squamish demo"}
        await ws.send(json.dumps(payload))

        while time.time() - started < timeout_seconds:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=5)
            except asyncio.TimeoutError:
                continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            mtype = data.get("type")
            if mtype:
                received_types.append(mtype)
            if mtype == "image_generated":
                got_images += 1
                print(f"✅ Received image_generated event ({got_images}/{expected})")
                if got_images >= expected:
                    break
            if mtype == "error":
                print(f"❌ Backend error: {data.get('message')}", file=sys.stderr)
                break
            if mtype == "turn_complete":
                # finished without image
                break

    if got_images >= expected:
        return 0
    print(f"❌ Expected {expected} image_generated events, got {got_images} within {timeout_seconds}s. Seen events: {received_types}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    exit_code = asyncio.run(run_test())
    sys.exit(exit_code)
