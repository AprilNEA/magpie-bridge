# Magpie for iOS

[magpie](https://github.com/badlogic/magpie) 网关 `/me` 页面的 iOS 版：拿到一把网关密钥的人，在手机上看自己的额度、用量、调用记录和可用的模型，并把 Claude Code、Codex 或任何 OpenAI 兼容工具的配置复制走。

只调用密钥自己能访问的 `/v1/magpie/me`、`/v1/magpie/limit` 和 `/v1/magpie/usage/requests`，不需要改网关，也不需要管理员密钥。

## 使用

1. 打开 App，填网关地址（默认是 `https://magpie.example.com`，可改）和网关密钥，点「继续」。密钥先用 `/v1/magpie/me` 验证，通过后才存进这台设备的钥匙串，不会同步到 iCloud。
2. **概览**：每条额度一个环形进度（绿 / 橙 / 红对应用了不到 60% / 85% / 更多）和重置时间；今天 / 7 天 / 30 天的 tokens、请求数和费用；**趋势**是按模型、Agent 或提供方堆起来的柱状图，可切时间范围和指标（Tokens / 请求 / 费用），点一根柱子看那个时间段的明细，再点取消；**构成**是同一时段的环形占比图，点一块看它的份额，点中间取消。只画前五名，其余并成「其他」。下拉刷新。
3. **请求**：这把密钥自己的调用记录，可按今天 / 7 天 / 30 天 / 全部筛选，列表上方有这个时段成功 / 失败的请求数走势，往下翻自动加载；点一条看 tokens、用时、错误原因。
4. **配置**：选工具（Claude Code、Codex、OpenAI 兼容、curl 测试）和模型，复制配置片段。默认不带密钥，打开「在配置里填入我的密钥」才会写进去。
5. **设置**：网关地址和版本、密钥受到的限制、忘记密钥。

密钥被停用后，刷新会收到 401，App 会自动忘记它并回到输入页，和网页一致。

## 开发

需要 Xcode 26 以上、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftLint](https://github.com/realm/SwiftLint)。

```sh
make generate   # 从 project.yml 生成 Magpie.xcodeproj
make lint       # swift-format --strict 和 swiftlint --strict
make build      # 编译模拟器版本
make test       # 单元测试（Swift Testing）
make check      # 以上三步
```

对着一个网关跑 UI 测试，并把每个页面截图存下来：

```sh
make ui-test MAGPIE_TEST_GATEWAY_URL=http://localhost:3425 \
  MAGPIE_TEST_GATEWAY_KEY=sk-magpie-key-... \
  MAGPIE_SCREENSHOT_DIR=/tmp/magpie-shots
```

手边没有数据够多的网关时，`make demo-gateway` 在 `http://localhost:3427` 起一个演示网关（`scripts/demo_gateway.py`，只依赖 Python 3 标准库）：90 天、几千条确定性的假调用，覆盖 5 个模型、两个 Agent、三个提供方、约 4% 的失败和两条额度；密钥是 `sk-magpie-key-demo`。接口和响应形状与真网关的 `/v1/magpie/me`、`/limit`、`/usage/requests` 一致，用它跑 UI 测试就能截到图表有内容的页面。

登录页预填的网关地址由 `project.yml` 里的 `MAGPIE_DEFAULT_GATEWAY_URL` 决定；连本机开发用的网关（`http://localhost:3425`）已通过 `NSAllowsLocalNetworking` 放行。

目录：

- `Magpie/Model`：网关 JSON 的模型，缺省字段都有默认值；`UsageSeries.swift` 是 `/usage/requests` 里的时间轴和份额。
- `Magpie/Charts`：Swift Charts 画的趋势柱状图、构成环形图、额度环，以及把账本整理成图表数据的 `ChartData`。
- `Magpie/Networking/MagpieClient.swift`：`/v1/magpie/*` 调用和错误映射。
- `Magpie/Storage/CredentialStore.swift`：钥匙串里的密钥。
- `Magpie/Session.swift`：登录状态和 `/me` 的最新结果。
- `Magpie/SetupSnippet.swift`：和网页 `/me` 一样的配置片段。
- `Magpie/Views`：登录、概览、请求、配置、设置。
- `MagpieTests`：解码、图表数据、客户端、片段、钥匙串和登录流程的单元测试，`Fixtures` 里是本地网关的真实响应。
- `MagpieUITests`：对着一个网关走一遍所有页面，切图表的时间范围和维度。
- `scripts/demo_gateway.py`：演示网关。
