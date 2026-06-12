#!/usr/bin/env python3
"""
hermes-bridge — a tiny, dependency-free HTTP bridge that exposes the local
Hermes Agent's data (sessions, cron, insights, skills, memory, profiles) to the
iOS app. Self-hosted on the same VPS as the agent; sits behind Caddy at /agent/*.

Auth: every request must carry the same Bearer access token the iOS app got from
the relay. We validate it by calling the relay's GET /v1/session (cached briefly).
"""
import json
import os
import re
import sqlite3
import subprocess
import time
import urllib.request
from datetime import datetime, timezone


def epoch_iso(value):
    """Convert a float epoch (seconds) to an ISO8601 UTC string."""
    if value in (None, "", 0):
        return None
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat()
    except Exception:
        return None
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERMES_HOME = os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes"))
HERMES_BIN = os.environ.get("HERMES_COMMAND", "/usr/local/bin/hermes")
RELAY_BASE = os.environ.get("RELAY_BASE_URL", "http://127.0.0.1:8000/v1")
BIND_HOST = os.environ.get("BRIDGE_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("BRIDGE_PORT", "8077"))

STATE_DB = os.path.join(HERMES_HOME, "state.db")
CRON_JOBS = os.path.join(HERMES_HOME, "cron", "jobs.json")

_token_cache: dict[str, float] = {}
_TOKEN_TTL = 60.0


# ───────────────────────── auth ─────────────────────────

def validate_token(token: str) -> bool:
    now = time.time()
    exp = _token_cache.get(token)
    if exp and exp > now:
        return True
    try:
        req = urllib.request.Request(
            RELAY_BASE.rstrip("/") + "/session",
            headers={"authorization": f"Bearer {token}", "accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            ok = resp.status == 200
    except Exception:
        ok = False
    if ok:
        _token_cache[token] = now + _TOKEN_TTL
    return ok


# ───────────────────────── helpers ─────────────────────────

def open_db(path: str) -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
    con.row_factory = sqlite3.Row
    return con


def table_columns(con: sqlite3.Connection, table: str) -> set[str]:
    return {r[1] for r in con.execute(f"PRAGMA table_info({table})")}


def run_hermes(args: list[str], timeout: int = 40) -> tuple[int, str]:
    env = dict(os.environ)
    env["HERMES_HOME"] = HERMES_HOME
    env.setdefault("NO_COLOR", "1")
    env.setdefault("TERM", "dumb")
    try:
        proc = subprocess.run(
            [HERMES_BIN, *args],
            capture_output=True, text=True, timeout=timeout, env=env,
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "command timed out"
    except Exception as exc:  # noqa: BLE001
        return 1, str(exc)


ANSI = re.compile(r"\x1b\[[0-9;]*m")

def strip_ansi(text: str) -> str:
    return ANSI.sub("", text)


def unwrap_connector_prompt(text: str) -> str:
    """The Hermes Mobile connector wraps each turn with a template; extract the
    real user message ('Latest user message:\\nUser: ...') for display."""
    if not text:
        return text
    marker = "Latest user message:"
    idx = text.rfind(marker)
    if idx >= 0:
        tail = text[idx + len(marker):].lstrip("\n ")
        if tail.startswith("User:"):
            tail = tail[len("User:"):].lstrip()
        return tail.strip() or text
    return text


# ───────────────────────── data: sessions ─────────────────────────

def list_sessions(limit: int = 100) -> list[dict]:
    if not os.path.exists(STATE_DB):
        return []
    con = open_db(STATE_DB)
    try:
        cols = table_columns(con, "sessions")
        order = "started_at" if "started_at" in cols else "rowid"
        rows = con.execute(
            f"SELECT * FROM sessions "
            f"{'WHERE COALESCE(archived,0)=0' if 'archived' in cols else ''} "
            f"ORDER BY {order} DESC LIMIT ?",
            (limit,),
        ).fetchall()
        msg_cols = table_columns(con, "messages")
        out = []
        for r in rows:
            d = dict(r)
            preview = first_user_preview(con, d.get("id"), msg_cols)
            out.append({
                "id": d.get("id"),
                "title": (d.get("title") or "").strip() or None,
                "preview": preview,
                "source": d.get("source"),
                "model": d.get("model"),
                "messageCount": d.get("message_count"),
                "toolCallCount": d.get("tool_call_count"),
                "inputTokens": d.get("input_tokens"),
                "outputTokens": d.get("output_tokens"),
                "costUsd": d.get("actual_cost_usd") or d.get("estimated_cost_usd"),
                "startedAt": epoch_iso(d.get("started_at")),
                "endedAt": epoch_iso(d.get("ended_at")),
            })
        return out
    finally:
        con.close()


def first_user_preview(con, session_id, msg_cols) -> str | None:
    if not session_id or "session_id" not in msg_cols:
        return None
    text_col = "content" if "content" in msg_cols else ("text" if "text" in msg_cols else None)
    role_col = "role" if "role" in msg_cols else None
    if not text_col:
        return None
    q = f"SELECT {text_col} FROM messages WHERE session_id=?"
    params = [session_id]
    if role_col:
        q += f" AND {role_col}='user'"
    order = "id" if "id" in msg_cols else "rowid"
    q += f" ORDER BY {order} ASC LIMIT 1"
    row = con.execute(q, params).fetchone()
    if not row or row[0] is None:
        return None
    val = row[0]
    if isinstance(val, (bytes, bytearray)):
        val = val.decode("utf-8", "ignore")
    val = str(val)
    # content may be JSON blocks; extract text best-effort.
    if val.startswith("[") or val.startswith("{"):
        try:
            parsed = json.loads(val)
            val = extract_text(parsed)
        except Exception:
            pass
    val = unwrap_connector_prompt(val)
    val = " ".join(val.split())
    return val[:140] if val else None


def extract_text(node) -> str:
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        return " ".join(extract_text(n) for n in node)
    if isinstance(node, dict):
        if isinstance(node.get("text"), str):
            return node["text"]
        if isinstance(node.get("content"), (str, list, dict)):
            return extract_text(node["content"])
    return ""


def session_messages(session_id: str, limit: int = 500) -> list[dict]:
    if not os.path.exists(STATE_DB):
        return []
    con = open_db(STATE_DB)
    try:
        cols = table_columns(con, "messages")
        if "session_id" not in cols:
            return []
        text_col = "content" if "content" in cols else ("text" if "text" in cols else None)
        role_col = "role" if "role" in cols else None
        ts_col = "timestamp" if "timestamp" in cols else ("created_at" if "created_at" in cols else None)
        order = "id" if "id" in cols else "rowid"
        rows = con.execute(
            f"SELECT * FROM messages WHERE session_id=? ORDER BY {order} ASC LIMIT ?",
            (session_id, limit),
        ).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            raw = d.get(text_col) if text_col else ""
            if isinstance(raw, (bytes, bytearray)):
                raw = raw.decode("utf-8", "ignore")
            text = raw or ""
            if isinstance(text, str) and (text.startswith("[") or text.startswith("{")):
                try:
                    text = extract_text(json.loads(text))
                except Exception:
                    pass
            role = d.get(role_col) if role_col else "assistant"
            if role in (None, ""):
                role = "assistant"
            if role in ("user", "voice_user"):
                text = unwrap_connector_prompt(text)
            out.append({"role": role, "text": text})
        return [m for m in out if m["text"].strip()]
    finally:
        con.close()


# ───────────────────────── data: cron (Tasks) ─────────────────────────

def list_cron() -> list[dict]:
    if not os.path.exists(CRON_JOBS):
        return []
    try:
        data = json.load(open(CRON_JOBS))
    except Exception:
        return []
    jobs = data.get("jobs", []) if isinstance(data, dict) else []
    out = []
    for j in jobs:
        sched = j.get("schedule") or {}
        skills = j.get("skills") or ([] if not j.get("skill") else [j.get("skill")])
        out.append({
            "id": j.get("id"),
            "name": j.get("name"),
            "prompt": j.get("prompt"),
            "script": j.get("script"),
            "schedule": j.get("schedule_display") or sched.get("display") or sched.get("expr"),
            "enabled": j.get("enabled", True),
            "paused": bool(j.get("paused_at")),
            "state": j.get("state"),
            "noAgent": j.get("no_agent", False),
            "deliver": j.get("deliver"),
            "model": j.get("model"),
            "skills": [s for s in skills if s],
            "lastStatus": j.get("last_status"),
            "lastRunAt": j.get("last_run_at"),
            "nextRunAt": j.get("next_run_at"),
        })
    return out


def cron_action(job_id: str, action: str) -> tuple[int, str]:
    mapping = {"run": "run", "pause": "pause", "resume": "resume", "delete": "remove"}
    sub = mapping.get(action)
    if not sub:
        return 400, "bad action"
    return run_hermes(["cron", sub, job_id], timeout=60)


# ───────────────────────── data: insights ─────────────────────────

def insights() -> dict:
    if not os.path.exists(STATE_DB):
        return {}
    con = open_db(STATE_DB)
    try:
        cols = table_columns(con, "sessions")
        cutoff = time.time() - 30 * 86400
        where = "WHERE started_at>=?" if "started_at" in cols else ""
        params = (cutoff,) if where else ()
        agg = con.execute(
            f"SELECT COUNT(*) sessions, "
            f"COALESCE(SUM(message_count),0) messages, "
            f"COALESCE(SUM(tool_call_count),0) tools, "
            f"COALESCE(SUM(input_tokens),0) input_tokens, "
            f"COALESCE(SUM(output_tokens),0) output_tokens, "
            f"COALESCE(SUM(COALESCE(actual_cost_usd,estimated_cost_usd,0)),0) cost "
            f"FROM sessions {where}",
            params,
        ).fetchone()
        return {
            "periodDays": 30,
            "sessions": agg["sessions"],
            "messages": agg["messages"],
            "toolCalls": agg["tools"],
            "inputTokens": agg["input_tokens"],
            "outputTokens": agg["output_tokens"],
            "totalTokens": (agg["input_tokens"] or 0) + (agg["output_tokens"] or 0),
            "costUsd": round(agg["cost"] or 0, 4),
        }
    finally:
        con.close()


# ───────────────────────── data: skills / memory / profiles ─────────────────────────

SKILLS_DIR = os.path.join(HERMES_HOME, "skills")


def parse_frontmatter(path: str) -> dict:
    """Extract name/description from a SKILL.md YAML frontmatter block."""
    out = {}
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            head = f.read(4000)
    except Exception:
        return out
    if not head.startswith("---"):
        return out
    end = head.find("\n---", 3)
    block = head[3:end] if end > 0 else head[3:]
    for line in block.splitlines():
        m = re.match(r"^(name|description)\s*:\s*(.+)$", line.strip())
        if m:
            val = m.group(2).strip().strip('"').strip("'")
            out[m.group(1)] = val
    return out


def list_skills() -> list[dict]:
    """Walk ~/.hermes/skills: top dirs are either a category (of skills) or a
    standalone skill. Returns items with category/name/description."""
    items = []
    if not os.path.isdir(SKILLS_DIR):
        return items
    for entry in sorted(os.listdir(SKILLS_DIR)):
        top = os.path.join(SKILLS_DIR, entry)
        if not os.path.isdir(top):
            continue
        own = os.path.join(top, "SKILL.md")
        if os.path.isfile(own):
            fm = parse_frontmatter(own)
            items.append({"category": "general", "name": fm.get("name") or entry, "description": fm.get("description")})
            continue
        for sub in sorted(os.listdir(top)):
            skill_md = os.path.join(top, sub, "SKILL.md")
            if os.path.isfile(skill_md):
                fm = parse_frontmatter(skill_md)
                items.append({"category": entry, "name": fm.get("name") or sub, "description": fm.get("description")})
    return items


# ───────────────────────── data: files ─────────────────────────

FILES_ROOT = os.path.realpath(os.environ.get("FILES_ROOT", os.path.expanduser("~")))


def _safe_path(rel: str) -> str | None:
    """Resolve a request path under FILES_ROOT, refusing escapes."""
    rel = (rel or "").lstrip("/")
    target = os.path.realpath(os.path.join(FILES_ROOT, rel))
    if target == FILES_ROOT or target.startswith(FILES_ROOT + os.sep):
        return target
    return None


def list_files(rel: str) -> dict:
    target = _safe_path(rel)
    if target is None or not os.path.isdir(target):
        return {"path": rel, "entries": []}
    entries = []
    try:
        names = sorted(os.listdir(target))
    except Exception:
        names = []
    for name in names:
        full = os.path.join(target, name)
        try:
            is_dir = os.path.isdir(full)
            size = os.path.getsize(full) if not is_dir else None
        except Exception:
            is_dir, size = False, None
        entries.append({"name": name, "isDirectory": is_dir, "size": size})
    entries.sort(key=lambda e: (not e["isDirectory"], e["name"].lower()))
    return {"path": os.path.relpath(target, FILES_ROOT) if target != FILES_ROOT else "", "entries": entries}


def read_file(rel: str) -> dict:
    target = _safe_path(rel)
    if target is None or not os.path.isfile(target):
        return {"path": rel, "content": None, "error": "not found"}
    try:
        size = os.path.getsize(target)
        if size > 400_000:
            return {"path": rel, "content": None, "error": "file too large", "size": size}
        with open(target, encoding="utf-8", errors="replace") as f:
            content = f.read()
        return {"path": rel, "content": content, "size": size}
    except Exception as exc:  # noqa: BLE001
        return {"path": rel, "content": None, "error": str(exc)}


MEMORY_FILES = {
    "memory": "MEMORY.md",
    "user": "USER.md",
    "agents": "AGENTS.md",
    "identity": "IDENTITY.md",
}


def read_memory() -> dict:
    out = {}
    for key, fname in MEMORY_FILES.items():
        p = os.path.join(HERMES_HOME, fname)
        if os.path.exists(p):
            try:
                out[key] = open(p, encoding="utf-8", errors="ignore").read()[:100000]
            except Exception:
                out[key] = None
        else:
            out[key] = None
    code, status = run_hermes(["memory", "status"], timeout=20)
    out["status"] = strip_ansi(status).strip()[:2000]
    return out


def save_memory(key: str, content: str) -> tuple[int, str]:
    fname = MEMORY_FILES.get(key)
    if not fname:
        return 400, "unknown memory file"
    p = os.path.join(HERMES_HOME, fname)
    try:
        with open(p, "w", encoding="utf-8") as f:
            f.write(content)
        return 0, "saved"
    except Exception as exc:  # noqa: BLE001
        return 500, str(exc)


def save_file(rel: str, content: str) -> tuple[int, str]:
    target = _safe_path(rel)
    if target is None:
        return 400, "invalid path"
    if os.path.isdir(target):
        return 400, "is a directory"
    try:
        with open(target, "w", encoding="utf-8") as f:
            f.write(content)
        return 0, "saved"
    except Exception as exc:  # noqa: BLE001
        return 500, str(exc)


def profile_use(name: str) -> tuple[int, str]:
    if not re.match(r"^[A-Za-z0-9_.\-]{1,64}$", name or ""):
        return 400, "invalid profile name"
    return run_hermes(["profile", "use", name], timeout=40)


def cron_create(name: str, prompt: str, schedule: str) -> tuple[int, str]:
    if not (name and prompt and schedule):
        return 400, "name, prompt and schedule are required"
    return run_hermes(["cron", "add", "--name", name, "--prompt", prompt, "--schedule", schedule], timeout=60)


def list_profiles() -> list[dict]:
    code, out = run_hermes(["profile", "list"], timeout=30)
    text = strip_ansi(out)
    items = []
    for line in text.splitlines():
        s = line.strip()
        if not s or set(s) <= set("─-=│|┌┐└┘ "):
            continue
        active = s.startswith("*") or "(active)" in s or "←" in s
        name = re.sub(r"^[\*\->•←\s]+", "", s).split()[0] if s else ""
        if re.match(r"^[A-Za-z0-9_.\-]+$", name) and name.lower() not in {
            "profile", "profiles", "name", "active", "available", "usage",
        }:
            items.append({"name": name, "active": active})
    return items


def host_status() -> dict:
    code, out = run_hermes(["--version"], timeout=15)
    return {"hermesVersion": strip_ansi(out).strip().splitlines()[0] if out else None}


# ───────────────────────── HTTP ─────────────────────────

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):  # quiet
        pass

    def _send(self, code: int, payload):
        body = json.dumps({"data": payload}).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code: int, message: str):
        body = json.dumps({"error": {"code": str(code), "message": message}}).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        h = self.headers.get("authorization", "")
        if not h.lower().startswith("bearer "):
            self._error(401, "auth required")
            return False
        token = h[7:].strip()
        if not validate_token(token):
            self._error(401, "invalid token")
            return False
        return True

    def _read_json(self):
        length = int(self.headers.get("content-length", "0") or "0")
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/agent/health":
            return self._send(200, {"status": "ok"})
        if not self._auth():
            return
        try:
            if path == "/agent/sessions":
                return self._send(200, {"sessions": list_sessions()})
            m = re.match(r"^/agent/sessions/([^/]+)/messages$", path)
            if m:
                return self._send(200, {"messages": session_messages(m.group(1))})
            if path == "/agent/cron":
                return self._send(200, {"jobs": list_cron()})
            if path == "/agent/insights":
                return self._send(200, insights())
            if path == "/agent/skills":
                return self._send(200, {"skills": list_skills()})
            if path == "/agent/memory":
                return self._send(200, read_memory())
            if path == "/agent/profiles":
                return self._send(200, {"profiles": list_profiles()})
            if path == "/agent/status":
                return self._send(200, host_status())
            if path == "/agent/files":
                rel = parse_qs(urlparse(self.path).query).get("path", [""])[0]
                return self._send(200, list_files(rel))
            if path == "/agent/file":
                rel = parse_qs(urlparse(self.path).query).get("path", [""])[0]
                return self._send(200, read_file(rel))
        except Exception as exc:  # noqa: BLE001
            return self._error(500, str(exc))
        self._error(404, "not found")

    def do_POST(self):
        path = urlparse(self.path).path
        if not self._auth():
            return
        m = re.match(r"^/agent/cron/([^/]+)/(run|pause|resume|delete)$", path)
        if m:
            code, out = cron_action(m.group(1), m.group(2))
            if code == 0:
                return self._send(200, {"ok": True, "output": strip_ansi(out).strip()[:2000]})
            return self._error(500, strip_ansi(out).strip()[:500] or "command failed")
        self._error(404, "not found")


def main():
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    print(f"hermes-bridge on {BIND_HOST}:{BIND_PORT} (home={HERMES_HOME})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
