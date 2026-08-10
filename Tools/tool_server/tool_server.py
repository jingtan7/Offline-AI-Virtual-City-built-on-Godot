#!/usr/bin/env python3
"""本地工具服务（纯标准库，零第三方依赖）—— Godot 离线工具调用实验服务。

用法:
    python tool_server.py --port 8770

仅监听 127.0.0.1 本机回环地址，完全离线。
端点:
    GET  /health       健康检查
    POST /tools/call   {"name": "工具名", "arguments": {...}}
"""
import argparse
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_OUTPUT = 8000


def run_code_execute(payload):
    code = str(payload.get("code", "")).strip()
    if not code:
        return {"success": False, "error": "缺少 code 参数"}
    timeout = float(payload.get("timeout_ms", 3000)) / 1000.0
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True, text=True, timeout=timeout,
        )
        return {
            "success": proc.returncode == 0,
            "exit_code": proc.returncode,
            "output": proc.stdout[:MAX_OUTPUT],
            "stderr": proc.stderr[:2000],
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "代码执行超时"}


def run_optimize(payload):
    obj = str(payload.get("objective", "")).strip()
    if not obj:
        return {"success": False, "error": "缺少 objective 表达式"}
    mode = str(payload.get("mode", "min"))
    lo = float(payload.get("range_lo", -10.0))
    hi = float(payload.get("range_hi", 10.0))
    steps = max(1, int(payload.get("steps", 200)))
    best_x, best_v = lo, (float("inf") if mode == "min" else float("-inf"))
    for i in range(steps + 1):
        x = lo + (hi - lo) * i / steps
        try:
            v = eval(obj, {"__builtins__": {}}, {"x": x})
        except Exception as exc:  # noqa: BLE001
            return {"success": False, "error": f"表达式错误: {exc}"}
        if (mode == "min" and v < best_v) or (mode == "max" and v > best_v):
            best_v, best_x = v, x
    return {"success": True, "best_x": best_x, "best_value": best_v}


def run_market_query(payload):
    key = str(payload.get("commodity", "")).strip()
    market = {
        "粮食": {"price": 12.5, "supply": 3200, "demand": 3050, "trend": "横盘"},
        "木材": {"price": 8.2, "supply": 2100, "demand": 2400, "trend": "上涨"},
        "矿石": {"price": 15.0, "supply": 900, "demand": 1300, "trend": "上涨"},
        "药剂": {"price": 32.0, "supply": 400, "demand": 380, "trend": "横盘"},
        "工具": {"price": 25.5, "supply": 300, "demand": 350, "trend": "下跌"},
    }
    if key in market:
        data = dict(market[key])
        data["commodity"] = key
        data["success"] = True
        return data
    return {"success": False, "error": f"未知物资: {key}"}


class Handler(BaseHTTPRequestHandler):
    def _send(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send({"status": "ok", "service": "godot-local-tool-server"})
        else:
            self._send({"success": False, "error": "not found"}, 404)

    def do_POST(self):
        if self.path != "/tools/call":
            self._send({"success": False, "error": "not found"}, 404)
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8")
        try:
            req = json.loads(raw)
        except json.JSONDecodeError:
            self._send({"success": False, "error": "JSON 解析失败"}, 400)
            return
        name = str(req.get("name", ""))
        args = req.get("arguments", {}) or {}
        if name == "code_execute":
            result = run_code_execute(args)
        elif name == "optimize_params":
            result = run_optimize(args)
        elif name == "market_query":
            result = run_market_query(args)
        else:
            result = {"success": False, "error": f"未知工具: {name}"}
        self._send(result)

    def log_message(self, fmt, *args):
        sys.stderr.write("[tool-server] %s\n" % (fmt % args))


def main():
    ap = argparse.ArgumentParser(description="Godot 本地工具服务")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8770)
    args = ap.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"[tool-server] listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
