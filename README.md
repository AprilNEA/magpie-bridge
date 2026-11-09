# Magpie for Apple platforms

English · [简体中文](README.zh-CN.md)

The [magpie](https://github.com/badlogic/magpie) gateway's `/me` page as a native app for Apple platforms, iOS today. Anyone holding a gateway key can check their limits, usage, request history, and available models on their phone, and copy the configuration for Claude Code, Codex, or any OpenAI-compatible tool.

The app calls only the endpoints a key can reach on its own: `/v1/magpie/me`, `/v1/magpie/limit`, and `/v1/magpie/usage/requests`. No gateway changes and no admin key needed. The UI is Chinese only for now.

## Usage

1. Open the app, enter the gateway address and your gateway key, then tap Continue (继续). The key is verified against `/v1/magpie/me` first; only then is it stored in this device's keychain. It never syncs to iCloud.
2. **Overview (概览)**: one ring per limit (green / orange / red for under 60% / 85% / more used) with its reset time; tokens, requests, and cost for today / 7 days / 30 days. **Trend** stacks usage by model, agent, or provider, as bars or a smooth stacked area; switch the time range and the metric (Tokens / Requests / Cost). 30 days and All scroll horizontally and start at the newest bucket. Tap a bucket for its breakdown, tap again to dismiss. **Share** is a donut of the same period; tap a slice for its share, tap the center to dismiss. Only the top five are drawn; the rest merge into Other (其他). Pull to refresh.
3. **Requests (请求)**: this key's own calls, filtered by today / 7 days / 30 days / all, with an area chart of request counts above the list (the red line underneath is failures). Scroll down to load more; tap a row for tokens, duration, and the error reason.
4. **Setup (配置)**: pick a tool (Claude Code, Codex, OpenAI-compatible, curl test) and a model, then copy the snippet. The key is left out by default; turn on Include my key (在配置里填入我的密钥) to write it in.
5. **Settings (设置)**: gateway address and version, the key's restrictions, Forget key (忘记密钥).

When a key is revoked, the next refresh gets a 401, and the app forgets the key and returns to the sign-in page, same as the web page.

## Development

Requires Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [SwiftLint](https://github.com/realm/SwiftLint).

```sh
make generate   # generate Magpie.xcodeproj (not tracked) from project.yml
make lint       # swift-format --strict and swiftlint --strict
make build      # build for the simulator
make test       # unit tests (Swift Testing)
make check      # all three
```

Per-developer settings live in `Config/Local.xcconfig`, which Git ignores; `make generate` creates it from `Config/Local.xcconfig.example` when it is missing. `MAGPIE_DEFAULT_GATEWAY_URL` is the gateway address prefilled on the sign-in page (empty for none), and `DEVELOPMENT_TEAM` is the team for device builds. The simulator needs neither. Never put a real gateway address or team ID in a tracked file.

Run the UI test against a gateway and save a screenshot of every page:

```sh
make ui-test MAGPIE_TEST_GATEWAY_URL=http://localhost:3425 \
  MAGPIE_TEST_GATEWAY_KEY=sk-magpie-key-... \
  MAGPIE_SCREENSHOT_DIR=/tmp/magpie-shots
```

Without a gateway that has enough data, `make demo-gateway` starts a demo gateway on `http://localhost:3427` (`scripts/demo_gateway.py`, Python 3 standard library only): 90 days of a few thousand deterministic fake calls across 5 models, two agents, three providers, about 4% failures, and two limits. The key is `sk-magpie-key-demo`. Its endpoints and response shapes match the real gateway's `/v1/magpie/me`, `/limit`, and `/usage/requests`, so UI tests against it produce screenshots with populated charts.

Connecting to a local development gateway (`http://localhost:3425`) is allowed through `NSAllowsLocalNetworking`.

Layout:

- `Magpie/Model`: models for the gateway JSON; every optional field has a default. `UsageSeries.swift` holds the time series and shares from `/usage/requests`.
- `Magpie/Charts`: the Swift Charts views (trend bars / area, share donut, limit rings) and `ChartData`, which shapes a ledger into chart data.
- `Magpie/Networking/MagpieClient.swift`: `/v1/magpie/*` calls and error mapping.
- `Magpie/Storage/CredentialStore.swift`: the key in the keychain.
- `Magpie/Session.swift`: sign-in state and the latest `/me` result.
- `Magpie/SetupSnippet.swift`: the same configuration snippets as the web `/me` page.
- `Magpie/Views`: sign-in, overview, requests, setup, settings.
- `MagpieTests`: unit tests for decoding, chart data, the client, snippets, the keychain, and the sign-in flow; `Fixtures` holds responses from a local development gateway.
- `MagpieUITests`: walks every page against a gateway and switches the chart range, style, and dimension.
- `Config/Local.xcconfig.example`: template for the ignored per-developer settings.
- `scripts/demo_gateway.py`: the demo gateway.
