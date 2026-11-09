# 鹊桥

[English](README.md) · 简体中文

鹊桥（Queqiao）是 [magpie](https://github.com/yetone/magpie) 网关 `/me` 页面的原生客户端，目前是 iOS 版：拿到一把网关密钥的人，在手机上看自己的额度、用量、调用记录和可用的模型，并把 Claude Code、Codex 或任何 OpenAI 兼容工具的配置复制走。

只调用密钥自己能访问的 `/v1/magpie/me`、`/v1/magpie/limit` 和 `/v1/magpie/usage/requests`，不需要改网关，也不需要管理员密钥。

## 使用

1. 打开 App，填网关地址和网关密钥，点「继续」。密钥先用 `/v1/magpie/me` 验证，通过后才存进这台设备的钥匙串，不会同步到 iCloud。
2. **概览**：每条额度一个环形进度（绿 / 橙 / 红对应用了不到 60% / 85% / 更多）和重置时间；今天 / 7 天 / 30 天的 tokens、请求数和费用，点一个时段看它的 token 构成（输入、输出、缓存读取、缓存写入一条横条）、缓存命中（提示词 tokens 里从缓存读出来的比例）、失败率和平均每次的费用；**趋势**是按模型、Agent 或提供方堆起来的柱状图，也能切成平滑的堆叠面积图，可切时间范围和指标（Tokens / 请求 / 费用），30 天和全部能横向滚动、一开始停在最近的桶，点一个时间段看它的明细，再点取消；**构成**是同一时段的环形占比图，点一块看它的份额，点中间取消。只画前五名，其余并成「其他」。**最近 30 天最常用**列出网关按调用次数排好的模型，每个写着名字和 id、tokens、次数、失败数和费用，再一条相对最常用那个的比例条；点一个看它最近 30 天的请求。下拉刷新。
3. **请求**：这把密钥自己今天 / 7 天 / 30 天 / 全部的调用记录，列表上方是这个时段请求数的面积图（失败数是下面那条红线），往下翻自动加载。筛选菜单可以只看失败的，或只看某个模型、Agent、提供方；搜索框在请求的模型、提供方和上游主机里找。筛选在网关上做，图和合计跟着变，设了的条件变成胶囊，点一下去掉。点一条看 tokens、用时、错误类型和原因、网关试了几次、上游主机和来回的字节数。被网关自己拒绝的请求和失败后转给重试的那一次会标出来，和网关自己的页面一样不算一次请求。
4. **配置**：选工具（Claude Code、Codex、OpenAI 兼容、curl 测试）和模型，复制或分享每段配置。模型那行写着选中模型的 id 和名字，默认选最常用的那个。默认不带密钥，打开「在配置里填入我的密钥」才会写进去。
5. **设置**：网关地址（可复制）、密钥名、网关版本和上次刷新时间；然后是 `/v1/magpie/limit` 告诉这把密钥的一切：受限于什么（额度、模型、账号），每条额度一根进度条，写着已用多少、剩多少、调用次数和重置时间，可用的模型通配，能不能看到账号配额、能看哪些提供方的，能用的 MCP 服务器和工具，过期时间，以及这把密钥是在另一把受限密钥下签发时签发者的额度。下拉刷新。「忘记密钥」从这台设备删掉密钥；最底下是源代码、反馈问题和 magpie 网关的链接。

密钥被停用后，刷新会收到 401，App 会自动忘记它并回到输入页，和网页一致。

## 开发

需要 Xcode 26 以上、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftLint](https://github.com/realm/SwiftLint)。

```sh
make generate   # 从 project.yml 生成 Magpie.xcodeproj（不进 Git）
make lint       # swift-format --strict 和 swiftlint --strict
make build      # 编译模拟器版本
make test       # 单元测试（Swift Testing）
make check      # 以上三步
```

每个开发者自己的设置放在 `Config/Local.xcconfig`，Git 忽略它；文件不存在时 `make generate` 会从 `Config/Local.xcconfig.example` 复制一份。`MAGPIE_DEFAULT_GATEWAY_URL` 是登录页预填的网关地址（留空则不预填），`DEVELOPMENT_TEAM` 是真机构建用的团队 ID；模拟器两者都不需要。不要把真实的网关地址或团队 ID 写进任何被 Git 跟踪的文件。

对着一个网关跑 UI 测试，并把每个页面截图存下来：

```sh
make ui-test MAGPIE_TEST_GATEWAY_URL=http://localhost:3425 \
  MAGPIE_TEST_GATEWAY_KEY=sk-magpie-key-... \
  MAGPIE_SCREENSHOT_DIR=/tmp/magpie-shots
```

手边没有数据够多的网关时，`make demo-gateway` 在 `http://localhost:3427` 起一个演示网关（`scripts/demo_gateway.py`，只依赖 Python 3 标准库）：90 天、几千条确定性的假调用，覆盖 5 个模型、两个 Agent、三个提供方、约 4% 的失败、少量重试和网关拒绝、两条额度、签发者的月额度、一份 MCP 列表和过期时间；密钥是 `sk-magpie-key-demo`。接口和响应形状与真网关的 `/v1/magpie/me`、`/limit`、`/usage/requests` 一致，包括后者的 `failed`、`model`、`agent`、`provider`、`q` 筛选，用它跑 UI 测试就能截到图表有内容的页面。

连本机开发用的网关（`http://localhost:3425`）已通过 `NSAllowsLocalNetworking` 放行。

目录（Xcode target 和 Swift 模块仍叫 `Magpie`，产品名是鹊桥）：

- `Magpie/Model`：网关 JSON 的模型，缺省字段都有默认值；`UsageSeries.swift` 是 `/usage/requests` 里的时间轴和份额，`RequestFilter.swift` 是请求的筛选条件和它加上的查询参数。
- `Magpie/Charts`：Swift Charts 画的趋势图（柱状 / 面积）、构成环形图、token 构成横条，额度的圆环和明细行，以及把账本整理成图表数据的 `ChartData`。
- `Magpie/Networking/MagpieClient.swift`：`/v1/magpie/*` 调用和错误映射。
- `Magpie/Storage/CredentialStore.swift`：钥匙串里的密钥。
- `Magpie/Session.swift`：登录状态和 `/me` 的最新结果。
- `Magpie/SetupSnippet.swift`：和网页 `/me` 一样的配置片段。
- `Magpie/Views`：登录、概览、请求、配置、设置，以及它们共用的复制按钮。
- `Magpie/AppIcon.icon`：Icon Composer 格式的应用图标，`Assets/` 里是平面的 SVG 图层，`icon.json` 里是背景、玻璃效果和各外观的填充色。Xcode 从它渲染所有尺寸和外观（默认、深色、透明、着色）。用 Xcode 26 自带的 Icon Composer 编辑。
- `MagpieTests`：解码、图表数据、客户端、片段、钥匙串和登录流程的单元测试，`Fixtures` 里是本机开发网关的响应。
- `MagpieUITests`：对着一个网关走一遍所有页面，切图表的时间范围、图形和维度，从常用模型进到它的请求，把请求筛成只看失败。
- `Config/Local.xcconfig.example`：被 Git 忽略的个人设置文件的模板。
- `scripts/demo_gateway.py`：演示网关。
