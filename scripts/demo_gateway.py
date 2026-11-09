#!/usr/bin/env python3
"""演示网关：按 magpie 网关 /v1/magpie/* 的格式，返回一把密钥最近 90 天的假用量。

不需要真网关也能把 App 跑起来看图表，UI 测试和截图也用它。数据由固定种子生成，每次一样；
只有时间跟着现在走。用法：

    python3 scripts/demo_gateway.py --port 3427 --key sk-magpie-key-demo

端点：/v1/magpie/me、/v1/magpie/limit、/v1/magpie/usage/requests?period=&offset=&limit=。
请求记录还认 failed=1、model=、agent=、provider=、q= 这几个筛选，和真网关一样在服务器上筛，
合计、时间轴和份额都跟着筛。密钥不对回 401，格式和真网关一样。
"""

import argparse
import json
import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VERSION = "0.1.3314"
KEY_NAME = "demo"
DAYS = 90

# id, 显示名, 提供方, Agent, 每百万 tokens 的价格（输入、输出、缓存读、缓存写）, 被选中的权重
MODELS = [
    ("claude-sonnet-4-5", "Claude Sonnet 4.5", "anthropic", "claude", (3, 15, 0.3, 3.75), 0.42),
    ("claude-opus-4-1", "Claude Opus 4.1", "anthropic", "claude", (15, 75, 1.5, 18.75), 0.13),
    ("gpt-5-codex", "GPT-5 Codex", "openai", "codex", (1.25, 10, 0.125, 0), 0.30),
    ("deepseek-v4-pro", "DeepSeek V4 Pro", "deepseek", "claude", (0.5, 1.5, 0.05, 0), 0.10),
    ("claude-haiku-4-5", "Claude Haiku 4.5", "anthropic", "claude", (1, 5, 0.1, 1.25), 0.05),
]
PRICES = {m[0]: m[4] for m in MODELS}
PROVIDERS = {
    "anthropic": ("Anthropic", "anthropic-color"),
    "openai": ("OpenAI", "openai-color"),
    "deepseek": ("DeepSeek", "deepseek-color"),
}
HOSTS = {"anthropic": "api.anthropic.com", "openai": "api.openai.com", "deepseek": "api.deepseek.com"}
AGENTS = {"claude": ("Claude Code", "claudecode-color"), "codex": ("Codex", "codex-color")}
# 网关自己拒绝的请求要的模型：这把密钥不能用的。
UNKNOWN_MODELS = ["openai/gpt-5", "anthropic/claude-3-opus", "deepseek/deepseek-r1"]
# 一天里每个小时的活跃程度：上午、下午、晚上三个高峰。
HOUR_WEIGHTS = [1, 0.5, 0.3, 0.2, 0.2, 0.4, 1, 2, 4, 6, 7, 6, 4, 5, 7, 8, 7, 6, 4, 4, 5, 6, 4, 2]
ERRORS = [
    (529, "overloaded_error", "Overloaded"),
    (429, "rate_limit_error", "This request would exceed your organization's rate limit"),
    (500, "api_error", "Internal server error"),
]
LIMIT_5H_USD = 2.5
LIMIT_WEEK_USD = 40.0
# 这把密钥是在另一把受限的密钥下签发的：签发者每月的额度，所有签出去的密钥一起算。
LIMIT_ISSUER_MONTH_USD = 300.0
# 签发者签出去的密钥数，签发者额度里的用量按这个倍数算。
ISSUED_KEYS = 3
# 这把密钥能用的 MCP 服务器和工具，格式同 access.Key.MCP。
MCP = ["web-search", "github/search_code", "github/get_file_contents"]
EXPIRES_IN_DAYS = 45
# 今天格外忙，不管是不是周末：打开 App 的那一刻总有东西可看。
TODAY_BOOST = 2.2


def rfc3339(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{t.microsecond // 1000:03d}Z"


def day_start(t):
    return t.replace(hour=0, minute=0, second=0, microsecond=0)


def make_rows(now):
    """最近 DAYS 天的调用，工作日多、周末少，越近越多。"""
    rng = random.Random(7)
    rows = []
    today = day_start(now)
    for back in range(DAYS):
        day = today - timedelta(days=back)
        weekday = day.weekday() < 5
        trend = 0.55 + 0.45 * (1 - back / DAYS)
        count = int((70 if weekday else 22) * trend * rng.uniform(0.7, 1.3))
        if back == 0:
            count = int(70 * TODAY_BOOST)
        hours = list(range(24))
        for _ in range(count):
            hour = rng.choices(hours, HOUR_WEIGHTS)[0]
            t = day + timedelta(hours=hour, minutes=rng.randint(0, 59), seconds=rng.randint(0, 59))
            if t >= now:
                continue
            rows.extend(make_call(rng, t))
    rows.sort(key=lambda r: r["t"], reverse=True)
    return rows


def make_call(rng, t):
    """一次请求留下的行：通常一行；偶尔先失败一次再换一次重试成功（两行），或被网关拒绝。"""
    roll = rng.random()
    if roll < 0.005:
        return [reject(rng, t)]
    row = make_row(rng, t)
    if roll < 0.035 and row["status"] == 200:
        row["tries"] = 2
        return [handed_on_try(rng, row, t - timedelta(seconds=rng.uniform(0.8, 3))), row]
    return [row]


def make_row(rng, t):
    model_id, model_name, provider, agent, _, _ = rng.choices(MODELS, [m[5] for m in MODELS])[0]
    inp = int(rng.lognormvariate(8.6, 0.7))
    cache_read = int(rng.lognormvariate(10.2, 0.9)) if rng.random() < 0.7 else 0
    cache_write = int(rng.lognormvariate(7.5, 0.8)) if rng.random() < 0.5 else 0
    out = int(rng.lognormvariate(6.6, 0.8))
    reasoning = int(out * rng.uniform(0.3, 1.2)) if agent == "codex" else 0
    status, err, err_type, canceled, tries = 200, None, None, False, 0
    roll = rng.random()
    if roll < 0.04:
        status, err_type, message = rng.choice(ERRORS)
        err = f"{PROVIDERS[provider][0]}: {message}"
        cache_read, cache_write, out, reasoning = 0, 0, 0, 0
        # 有的错误是换了一家还不行才回给 Agent 的。
        tries = 2 if rng.random() < 0.4 else 0
    elif roll < 0.055:
        status, err, canceled = 499, "context canceled", True
        out, reasoning = out // 4, 0
    row = {
        "t": rfc3339(t),
        "agent": agent,
        "provider": provider,
        "callerKeyName": KEY_NAME,
        "model": model_id,
        "req": f"{provider}/{model_id}",
        "in": inp,
        "out": out,
        "cache_read": cache_read,
        "cache_write": cache_write,
        "reasoning": reasoning,
        "ms": int(600 + out * rng.uniform(12, 30) + rng.uniform(0, 1500)),
        "status": status,
        "ep": "/v1/responses" if agent == "codex" else "/v1/messages",
        "priced": True,
        "host": HOSTS[provider],
        "up_bytes": int(inp * rng.uniform(3.8, 4.6)) + 700,
        "down_bytes": int(out * rng.uniform(9, 14)) + 300 if out else rng.randint(150, 400),
        "agentName": AGENTS[agent][0],
        "icon": AGENTS[agent][1],
        "providerName": PROVIDERS[provider][0],
        "access": "api",
        "_time": t,
        "_model_name": model_name,
    }
    row["cost"] = cost_of(row)
    if err:
        row["err"] = err
    if err_type:
        row["err_type"] = err_type
    if canceled:
        row["canceled"] = True
    if tries:
        row["tries"] = tries
    return row


def handed_on_try(rng, row, t):
    """row 之前失败、被网关转给下一次尝试的那一行：只有输入，没有输出，不算一次调用。"""
    status, err_type, message = rng.choice(ERRORS)
    first = {k: v for k, v in row.items() if k != "tries"}
    first.update(
        {
            "t": rfc3339(t),
            "_time": t,
            "out": 0,
            "cache_read": 0,
            "cache_write": 0,
            "reasoning": 0,
            "ms": int(rng.uniform(300, 2500)),
            "status": status,
            "err": f"{row['providerName']}: {message}",
            "err_type": err_type,
            "handed_on": True,
            "down_bytes": rng.randint(150, 400),
        }
    )
    first["cost"] = cost_of(first)
    return first


def reject(rng, t):
    """网关自己拒绝的请求：要的模型这把密钥没有，没发给任何提供方，不算一次调用。"""
    agent = rng.choice(list(AGENTS))
    return {
        "t": rfc3339(t),
        "agent": agent,
        "provider": "",
        "callerKeyName": KEY_NAME,
        "model": "",
        "req": rng.choice(UNKNOWN_MODELS),
        "in": 0,
        "out": 0,
        "cache_read": 0,
        "cache_write": 0,
        "reasoning": 0,
        "ms": rng.randint(1, 4),
        "status": 404,
        "err": "unknown model",
        "rejected": True,
        "ep": "/v1/responses" if agent == "codex" else "/v1/messages",
        "cost": 0,
        "priced": False,
        "agentName": AGENTS[agent][0],
        "icon": AGENTS[agent][1],
        "providerName": "",
        "access": "api",
        "_time": t,
        "_model_name": "",
    }


def cost_of(row):
    p = PRICES[row["model"]]
    cost = row["in"] * p[0] + row["out"] * p[1] + row["cache_read"] * p[2] + row["cache_write"] * p[3]
    return round(cost / 1_000_000, 6)


def failed(row):
    """usage.Record.Failed：回了错误或记了错误，且不是 Agent 自己取消。"""
    return (row["status"] >= 400 or bool(row.get("err"))) and not row.get("canceled")


def lost(row):
    """usage.Record.LostRequest：Agent 真的收到了错误的请求，failed=1 筛的就是它。"""
    return failed(row) and not row.get("handed_on")


def counted(rows):
    """算作一次调用的行：被网关拒绝的和转给下一次尝试的不算，tokens 和费用照加。"""
    return [r for r in rows if not r.get("rejected") and not r.get("handed_on")]


def totals(rows):
    calls = counted(rows)
    return {
        "calls": len(calls),
        "errors": sum(1 for r in calls if failed(r)),
        "input": sum(r["in"] for r in rows),
        "output": sum(r["out"] for r in rows),
        "cache_read": sum(r["cache_read"] for r in rows),
        "cache_write": sum(r["cache_write"] for r in rows),
        "reasoning": sum(r["reasoning"] for r in rows),
        "cost": round(sum(r["cost"] for r in rows), 4),
        "unpriced": 0,
        "up_bytes": sum(r.get("up_bytes", 0) for r in rows),
        "down_bytes": sum(r.get("down_bytes", 0) for r in rows),
    }


def part(rows):
    return {
        "calls": len(counted(rows)),
        "tokens": sum(r["in"] + r["out"] + r["cache_read"] + r["cache_write"] for r in rows),
        "cost": round(sum(r["cost"] for r in rows), 4),
    }


def keeps(row, filt):
    """usage.Filter.keepsRecord 里一把密钥用得上的几项；q 在模型、提供方、主机和密钥名里找。"""
    if filt.get("failed") and not lost(row):
        return False
    for field in ("model", "agent", "provider"):
        if filt.get(field) and row[field] != filt[field]:
            return False
    q = filt.get("q", "").lower()
    if q and not any(q in str(row.get(k) or "").lower() for k in ("req", "model", "provider", "host", "callerKeyName")):
        return False
    return True


def apply(rows, filt, skip=None):
    """筛过的行；skip 是不参与的那一项，by[skip] 用，这样选了一个模型，其他模型还在下拉里。"""
    if skip:
        filt = {k: v for k, v in filt.items() if k != skip}
    return [r for r in rows if keeps(r, filt)]


def key_of(row, dimension):
    if dimension == "model":
        return row["model"], row["model"], None
    if dimension == "agent":
        return row["agent"], row["agentName"], row["icon"]
    if dimension == "provider":
        return row["provider"], row["providerName"], PROVIDERS[row["provider"]][1]
    if dimension == "modelAt":
        return row["req"], f"{row['model']} · {row['providerName']}", PROVIDERS[row["provider"]][1]
    return KEY_NAME, KEY_NAME, "generic"


DIMENSIONS = ["agent", "callerKey", "model", "modelAt", "provider"]


def breakdown(rows, dimension):
    """按维度分的份额；被网关拒绝的行没有模型和提供方，不在任何一份里。"""
    groups = {}
    for r in rows:
        if r.get("rejected"):
            continue
        key, name, icon = key_of(r, dimension)
        groups.setdefault(key, (name, icon, []))[2].append(r)
    out = []
    for key, (name, icon, members) in groups.items():
        share = {"id": key, **totals(members), "name": name}
        if icon:
            share["icon"] = icon
        out.append(share)
    out.sort(key=lambda s: (s["input"] + s["output"] + s["cache_read"] + s["cache_write"], s["calls"]), reverse=True)
    return out


def timeline(period, now):
    """时段的起点、桶的大小和每个桶的起点。"""
    today = day_start(now)
    if period == "today":
        return today, "hour", [today + timedelta(hours=h) for h in range(24)]
    if period == "7d":
        since = today - timedelta(days=6)
        return since, "day", [since + timedelta(days=d) for d in range(7)]
    if period == "all":
        since = today - timedelta(days=DAYS - 1)
        since -= timedelta(days=since.weekday())
        weeks = math.ceil(((today - since).days + 1) / 7)
        return since, "week", [since + timedelta(weeks=w) for w in range(weeks)]
    since = today - timedelta(days=29)
    return since, "day", [since + timedelta(days=d) for d in range(30)]


def label(bucket, t):
    if bucket == "hour":
        return f"{t.hour:02d}"
    return f"{t.strftime('%b')} {t.day}"


def series(rows, bucket, starts):
    step = {"hour": timedelta(hours=1), "day": timedelta(days=1), "week": timedelta(weeks=1)}[bucket]
    points = []
    for start in starts:
        members = [r for r in rows if start <= r["_time"] < start + step]
        point = {"label": label(bucket, start), "time": rfc3339(start), **totals(members)}
        point["by"] = {
            d: {key: part(group) for key, group in group_by(members, d).items()} for d in DIMENSIONS
        }
        points.append(point)
    return points


def group_by(rows, dimension):
    groups = {}
    for r in rows:
        if r.get("rejected"):
            continue
        groups.setdefault(key_of(r, dimension)[0], []).append(r)
    return groups


def named(table, ids):
    """筛选菜单用的 Agent 或提供方列表，只有这个时间窗口里出现过的。"""
    return [{"id": k, "name": v[0], "icon": v[1]} for k, v in table.items() if k in ids]


def public(row):
    return {k: v for k, v in row.items() if not k.startswith("_")}


class Demo:
    def __init__(self, key):
        self.key = key

    def rows(self, now):
        return make_rows(now)

    def ledger(self, query, now):
        period = query.get("period", ["30d"])[0]
        if period not in ("today", "7d", "30d", "all"):
            period = "30d"
        offset = max(0, int(query.get("offset", ["0"])[0] or 0))
        limit = int(query.get("limit", ["100"])[0] or 100)
        limit = 100 if limit <= 0 else min(limit, 500)
        filt = {k: query[k][0] for k in ("model", "agent", "provider", "q") if query.get(k, [""])[0]}
        if query.get("failed", [""])[0] in ("1", "true"):
            filt["failed"] = True
        since, bucket, starts = timeline(period, now)
        window = [r for r in self.rows(now) if r["_time"] >= since]
        rows = apply(window, filt)
        page = rows[offset : offset + limit]
        return {
            "callerKeys": [{"id": KEY_NAME, **totals(rows), "name": KEY_NAME, "icon": "generic"}],
            "period": period,
            "rows": [public(r) for r in page],
            "offset": offset,
            "total": len(rows),
            "bucket": bucket,
            "series": series(rows, bucket, starts),
            "by": {d: breakdown(apply(window, filt, skip=d), d) for d in DIMENSIONS},
            **totals(rows),
            "through": totals(rows),
            "direct": totals([]),
            "reported": totals([]),
            "agents": named(AGENTS, {r["agent"] for r in window}),
            "providers": named(PROVIDERS, {r["provider"] for r in window}),
            "purposes": [],
            "accounts": [],
        }

    def limits(self, rows, now):
        start_5h = now - timedelta(hours=3, minutes=12)
        week_start = day_start(now) - timedelta(days=day_start(now).weekday())
        out = []
        for period, extra, start, reset, cap in (
            ("hours", {"hours": 5}, start_5h, start_5h + timedelta(hours=5), LIMIT_5H_USD),
            ("week", {}, week_start, week_start + timedelta(weeks=1), LIMIT_WEEK_USD),
        ):
            out.append(status(period, extra, rows, start, reset, cap))
        return out

    def issuer_limits(self, rows, now):
        month_start = day_start(now).replace(day=1)
        reset = (month_start + timedelta(days=32)).replace(day=1)
        return [status("month", {}, rows, month_start, reset, LIMIT_ISSUER_MONTH_USD, ISSUED_KEYS)]

    def me(self, now):
        rows = self.rows(now)
        today = day_start(now)
        windows = {
            "today": [r for r in rows if r["_time"] >= today],
            "7d": [r for r in rows if r["_time"] >= today - timedelta(days=6)],
            "30d": [r for r in rows if r["_time"] >= today - timedelta(days=29)],
        }
        top = breakdown(windows["30d"], "model")
        top.sort(key=lambda s: s["calls"], reverse=True)
        return {
            "name": KEY_NAME,
            "readOnly": False,
            "limits": self.limits(rows, now),
            "usage": {k: totals(v) for k, v in windows.items()},
            "topModels": [{k: v for k, v in s.items() if k not in ("name", "icon")} for s in top[:8]],
            "models": [
                {"id": f"{m[2]}/{m[0]}", "label": f"{m[1]} · {PROVIDERS[m[2]][0]}"} for m in MODELS
            ],
            "version": VERSION,
        }

    def limit(self, now):
        rows = self.rows(now)
        limits = self.limits(rows, now)
        return {
            "expires": rfc3339(day_start(now) + timedelta(days=EXPIRES_IN_DAYS)),
            "heldTo": ["budget", "models"],
            "issuerLimits": self.issuer_limits(rows, now),
            "key": KEY_NAME,
            "limit": limits[0],
            "limited": True,
            "limits": limits,
            "mcp": MCP,
            "models": sorted({f"{m[2]}/*" for m in MODELS}),
            "quotas": False,
        }


def status(period, extra, rows, start, reset, cap, keys=1):
    """一条额度现在的窗口（budget.Status）：窗口内调用的合计对着上限；keys 把用量算成几把密钥的。"""
    t = totals([r for r in rows if r["_time"] >= start])
    cost = round(t["cost"] * keys, 4)
    return {
        "period": period,
        **extra,
        "start": rfc3339(start),
        "reset": rfc3339(reset),
        "calls": t["calls"] * keys,
        "tokens": (t["input"] + t["output"] + t["cache_read"] + t["cache_write"]) * keys,
        "cost": cost,
        "costLimit": cap,
        "tokensLeft": 0,
        "costLeft": round(max(cap - cost, 0), 4),
        "spent": cost >= cap,
    }


class Handler(BaseHTTPRequestHandler):
    demo = None

    def do_GET(self):  # noqa: N802
        url = urlparse(self.path)
        if not self.authorized():
            return self.send_json(
                401,
                {
                    "error": {
                        "code": None,
                        "message": "send an enabled gateway key as Authorization: Bearer <key> or x-api-key",
                        "param": None,
                        "type": "authentication_error",
                    }
                },
            )
        now = datetime.now(timezone.utc)
        if url.path == "/v1/magpie/me":
            return self.send_json(200, self.demo.me(now))
        if url.path == "/v1/magpie/limit":
            return self.send_json(200, self.demo.limit(now))
        if url.path == "/v1/magpie/usage/requests":
            return self.send_json(200, self.demo.ledger(parse_qs(url.query), now))
        self.send_json(404, {"error": {"message": "not found", "type": "invalid_request_error"}})

    def authorized(self):
        auth = self.headers.get("Authorization", "")
        key = auth[7:] if auth.startswith("Bearer ") else self.headers.get("x-api-key", "")
        return key == self.demo.key

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "3427")))
    parser.add_argument("--key", default="sk-magpie-key-demo")
    args = parser.parse_args()
    Handler.demo = Demo(args.key)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"demo gateway on http://127.0.0.1:{args.port} · key {args.key}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
