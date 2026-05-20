import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def wait_for(url: str, timeout: float = 20.0):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return response.status, response.read().decode("utf-8")
        except Exception as exc:  # pragma: no cover - polling helper
            last_error = exc
            time.sleep(0.5)
    raise RuntimeError(f"Timed out waiting for {url}: {last_error}")


def test_health_and_known_tools():
    root = Path(__file__).resolve().parent
    env = os.environ.copy()
    env.setdefault("FASTMCP_HOST", "127.0.0.1")
    env.setdefault("FASTMCP_PORT", "18001")
    env.setdefault("DATA_DIR", str((root.parent / "data").resolve()))
    env.setdefault("CORPUS_DIR", str((root.parent / "corpus").resolve()))

    process = subprocess.Popen(
        [sys.executable, str(root / "server.py")],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        status, body = wait_for("http://127.0.0.1:18001/health")
        assert status == 200
        payload = json.loads(body)
        assert payload["status"] == "ok"

        status, body = wait_for("http://127.0.0.1:18001/tools")
        assert status == 200
        payload = json.loads(body)
        names = [tool["name"] for tool in payload["tools"]]
        assert names == [
            "aggregate_preprocessed_dsn_like",
            "get_audit_scope",
            "get_exception_investigation_case",
            "search_documentary_sources",
        ]
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


if __name__ == "__main__":
    test_health_and_known_tools()
    print("OK")
