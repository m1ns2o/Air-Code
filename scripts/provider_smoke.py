#!/usr/bin/env python3
import argparse
import datetime as dt
import http.client
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.parse


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "backend" / "config.json"
DEFAULT_ADDR = "127.0.0.1:18082"
AUTH_SKIP_MARKERS = (
    "auth",
    "credential",
    "login",
    "sign in",
    "api key",
    "credit",
    "not configured",
    "no codex credentials",
    "missing provider",
)


def run(cmd, cwd=None, timeout=120, check=True):
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed:\n{result.stdout}\n{result.stderr}")
    return result


def request(base_url, token, method, path, body=None, timeout=30):
    url = urllib.parse.urlparse(base_url)
    connection_cls = http.client.HTTPSConnection if url.scheme == "https" else http.client.HTTPConnection
    conn = connection_cls(url.hostname, url.port, timeout=timeout)
    headers = {"Authorization": f"Bearer {token}"}
    payload = None
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    try:
        conn.request(method, path, body=payload, headers=headers)
        response = conn.getresponse()
        data = response.read().decode("utf-8", errors="replace")
    finally:
        conn.close()
    if response.status >= 400:
        raise RuntimeError(f"HTTP {response.status} {path}: {data}")
    if not data:
        return {}
    return json.loads(data)


def request_text(base_url, method, path, timeout=5):
    url = urllib.parse.urlparse(base_url)
    connection_cls = http.client.HTTPSConnection if url.scheme == "https" else http.client.HTTPConnection
    conn = connection_cls(url.hostname, url.port, timeout=timeout)
    try:
        conn.request(method, path)
        response = conn.getresponse()
        data = response.read().decode("utf-8", errors="replace")
    finally:
        conn.close()
    if response.status >= 400:
        raise RuntimeError(f"HTTP {response.status} {path}: {data}")
    return data


def wait_for_health(base_url, proc=None):
    for _ in range(60):
        try:
            request_text(base_url, "GET", "/health")
            return
        except Exception:
            if proc is not None and proc.poll() is not None:
                raise RuntimeError(f"aircoded exited early with code {proc.returncode}")
            time.sleep(0.25)
    raise RuntimeError(f"server did not become healthy at {base_url}")


def start_server(config_path, addr):
    base_url = f"http://{addr}"
    try:
        request_text(base_url, "GET", "/health", timeout=1)
        return base_url, None
    except Exception:
        pass
    tmp = ROOT / "tmp"
    tmp.mkdir(exist_ok=True)
    binary = tmp / "aircoded-provider-smoke"
    log = tmp / "provider-smoke-server.log"
    run(["go", "build", "-o", str(binary), "./cmd/aircoded"], cwd=ROOT / "backend", timeout=180)
    logfile = log.open("w")
    proc = subprocess.Popen(
        [str(binary), "serve", "-config", str(config_path), "-addr", addr],
        cwd=ROOT / "backend",
        stdout=logfile,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        wait_for_health(base_url, proc)
    except Exception:
        logfile.close()
        if log.exists():
            sys.stderr.write(log.read_text(errors="replace"))
        raise
    return base_url, (proc, logfile)


def stop_server(handle):
    if handle is None:
        return
    proc, logfile = handle
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    logfile.close()


def version_check(agent_id, command):
    if not command:
        return "skipped: command missing"
    result = run([command, "--version"], timeout=20, check=False)
    output = (result.stdout + result.stderr).strip()
    if result.returncode == 0:
        return output.splitlines()[0] if output else "ok"
    if agent_id == "hermes":
        alt = run([command, "version"], timeout=20, check=False)
        output = (alt.stdout + alt.stderr).strip()
        if alt.returncode == 0:
            return output.splitlines()[0] if output else "ok"
    return f"failed: {output or 'version command failed'}"


def classify_error(error):
    text = str(error).lower()
    if any(marker in text for marker in AUTH_SKIP_MARKERS):
        return "skipped", f"auth/config missing: {error}"
    return "failed", str(error)


def optional_request(base_url, token, method, path, body=None, timeout=30):
    try:
        return {"ok": True, "data": request(base_url, token, method, path, body, timeout=timeout)}
    except Exception as error:
        return {"ok": False, "error": str(error)}


def response_data(result, fallback=None):
    if result.get("ok"):
        return result.get("data") if result.get("data") is not None else fallback
    return fallback


def log_text(log_response):
    if not isinstance(log_response, dict):
        return ""
    content = log_response.get("content")
    if isinstance(content, str):
        return content
    events = log_response.get("events")
    if isinstance(events, list):
        return "\n".join(json.dumps(event, ensure_ascii=False) for event in events)
    return ""


def wait_for_log(base_url, token, run_id, marker="", timeout_seconds=20):
    last = {}
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        result = optional_request(base_url, token, "GET", f"/v1/projects/sample-app/agents/runs/{run_id}/log", timeout=15)
        if result.get("ok"):
            last = result.get("data") or {}
            text = log_text(last)
            if marker and marker in text:
                return last
            if "run.finished" in text or "\"kind\":\"run.finished\"" in text:
                return last
        time.sleep(0.75)
    return last


def try_steer(base_url, token, run_id):
    last = {}
    for _ in range(10):
        result = optional_request(
            base_url,
            token,
            "POST",
            f"/v1/projects/sample-app/agents/runs/{run_id}/steer",
            {"prompt": "Keep the smoke answer short."},
            timeout=15,
        )
        if result.get("ok"):
            return {"attempted": True, "accepted": bool((result.get("data") or {}).get("accepted")), "response": result.get("data")}
        last = result
        message = str(result.get("error", "")).lower()
        if "no active turn" in message:
            return {"attempted": True, "accepted": False, "reason": result.get("error")}
        if "not ready" not in message:
            return {"attempted": True, "accepted": False, "reason": result.get("error")}
        time.sleep(0.5)
    return {"attempted": True, "accepted": False, "reason": last.get("error", "steering did not become ready")}


def live_agent_smoke(base_url, token, agent_id):
    start = request(
        base_url,
        token,
        "POST",
        "/v1/projects/sample-app/agents/runs",
        {
            "agent": agent_id,
            "prompt": "Air Code provider smoke: reply with exactly AIRCODE_PROVIDER_SMOKE_OK and do not edit files.",
            "mode": "agent",
            "provider": "openai-codex" if agent_id == "hermes" else "",
            "model": "",
            "reasoningEffort": "auto",
            "speedMode": "auto",
            "approvalMode": "",
            "sandboxMode": "",
            "resumeSession": False,
            "caveman": False,
            "context": [],
        },
        timeout=45,
    )
    run_id = start["runId"]
    time.sleep(0.25)
    steer = try_steer(base_url, token, run_id)
    log = wait_for_log(base_url, token, run_id, marker="AIRCODE_PROVIDER_SMOKE_OK", timeout_seconds=30)
    changes_result = optional_request(base_url, token, "GET", f"/v1/projects/sample-app/agents/runs/{run_id}/changes", timeout=30)
    changes = response_data(changes_result, {"changes": []})
    revert_result = optional_request(base_url, token, "POST", f"/v1/projects/sample-app/agents/runs/{run_id}/revert", timeout=30)
    revert = response_data(revert_result, {"reverted": []})
    stop = optional_request(base_url, token, "POST", f"/v1/projects/sample-app/agents/runs/{run_id}/stop", timeout=30)
    resume_result = optional_request(
        base_url,
        token,
        "POST",
        "/v1/projects/sample-app/agents/runs",
        {
            "agent": agent_id,
            "prompt": "Air Code provider smoke resume check. Reply with AIRCODE_PROVIDER_RESUME_OK and do not edit files.",
            "mode": "agent",
            "provider": "openai-codex" if agent_id == "hermes" else "",
            "model": "",
            "reasoningEffort": "auto",
            "speedMode": "auto",
            "approvalMode": "",
            "sandboxMode": "",
            "resumeSession": True,
            "caveman": False,
            "context": [],
        },
        timeout=45,
    )
    resume = response_data(resume_result, {})
    resume_run_id = resume.get("runId", "")
    resume_stop = {}
    if resume_run_id:
        time.sleep(1)
        resume_stop = optional_request(base_url, token, "POST", f"/v1/projects/sample-app/agents/runs/{resume_run_id}/stop", timeout=30)
    text = log_text(log)
    return {
        "runId": run_id,
        "answerSeen": "AIRCODE_PROVIDER_SMOKE_OK" in text,
        "steer": steer,
        "logBytes": len(text),
        "changes": len(changes.get("changes") or []),
        "reverted": len(revert.get("reverted") or []),
        "stop": stop,
        "resumeStarted": bool(resume_run_id),
        "resumeRunId": resume_run_id,
        "resumeStop": resume_stop,
        "warnings": [
            label
            for label, result in (
                ("changes", changes_result),
                ("revert", revert_result),
                ("stop", stop),
                ("resume", resume_result),
                ("resumeStop", resume_stop),
            )
            if result and not result.get("ok", False)
        ],
    }


def main():
    parser = argparse.ArgumentParser(description="Smoke test Air Code provider runtimes against the sandbox project.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--addr", default=os.environ.get("AIRCODE_PROVIDER_SMOKE_ADDR", DEFAULT_ADDR))
    parser.add_argument("--live", action="store_true", default=os.environ.get("AIRCODE_LIVE_PROVIDER_SMOKE") == "1")
    args = parser.parse_args()

    config_path = pathlib.Path(args.config).resolve()
    config = json.loads(config_path.read_text())
    token = os.environ.get("AIR_CODE_TOKEN", config.get("authToken", "dev-token-change-me"))
    run([str(ROOT / "scripts" / "setup_sandbox.sh")], timeout=60)
    base_url, handle = start_server(config_path, args.addr)
    results = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "baseUrl": base_url,
        "live": args.live,
        "providers": {},
    }
    try:
        capabilities = request(base_url, token, "GET", "/v1/agents/capabilities")
        by_id = {item["id"]: item for item in capabilities}
        request(base_url, token, "POST", "/v1/workspace/open", {"rootId": "sandbox", "path": "sample-app"})
        for agent_id in ("codex", "hermes", "claude"):
            cap = by_id.get(agent_id, {})
            entry = {
                "capability": cap,
                "version": version_check(agent_id, config.get("agents", {}).get(agent_id, {}).get("command", "")),
            }
            if not cap.get("installed") or not cap.get("configured"):
                entry["status"] = "skipped"
                entry["reason"] = "provider not installed/configured"
            elif not args.live:
                entry["status"] = "skipped"
                entry["reason"] = "live provider run disabled; set AIRCODE_LIVE_PROVIDER_SMOKE=1"
            else:
                try:
                    live = live_agent_smoke(base_url, token, agent_id)
                    entry["live"] = live
                    if live.get("answerSeen"):
                        entry["status"] = "passed"
                    else:
                        entry["status"] = "failed"
                        entry["reason"] = "provider did not produce AIRCODE_PROVIDER_SMOKE_OK before the smoke timeout"
                except Exception as error:
                    status, reason = classify_error(error)
                    entry["status"] = status
                    entry["reason"] = reason
            results["providers"][agent_id] = entry
    finally:
        stop_server(handle)

    out_dir = ROOT / "tmp"
    out_dir.mkdir(exist_ok=True)
    output_path = out_dir / "provider-smoke-latest.json"
    output_path.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(results, indent=2, ensure_ascii=False))
    print(f"provider smoke result: {output_path}")
    failed = [key for key, value in results["providers"].items() if value.get("status") == "failed"]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
