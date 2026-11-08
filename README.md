# Magpie for iOS

[magpie](https://github.com/badlogic/magpie) 网关 `/me` 页面的 iOS 版：拿到一把网关密钥的人，在手机上看自己的额度、用量、调用记录和可用的模型，并把 Claude Code、Codex 或任何 OpenAI 兼容工具的配置复制走。

只调用密钥自己能访问的 `/v1/magpie/me`、`/v1/magpie/limit` 和 `/v1/magpie/usage/requests`，不需要改网关，也不需要管理员密钥。

## 使用

1. 打开 App，填网关地址（默认是 `https://magpie.example.com`，可改）和网关密钥，点「继续」。密钥先用 `/v1/magpie/me` 验证，通过后才存进这台设备的钥匙串，不会同步到 iCloud。
2. **概览**：每条额度的进度和重置时间，今天 / 7 天 / 30 天的 tokens、请求数和费用，最近 30 天最常用的模型。下拉刷新。
3. **请求**：这把密钥自己的调用记录，可按今天 / 7 天 / 30 天 / 全部筛选，往下翻自动加载；点一条看 tokens、用时、错误原因。
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

对着一个真实网关跑 UI 测试，并把每个页面截图存下来：

```sh
make ui-test MAGPIE_TEST_GATEWAY_URL=http://localhost:3425 \
  MAGPIE_TEST_GATEWAY_KEY=sk-magpie-key-... \
  MAGPIE_SCREENSHOT_DIR=/tmp/magpie-shots
```

登录页预填的网关地址由 `project.yml` 里的 `MAGPIE_DEFAULT_GATEWAY_URL` 决定；连本机开发用的网关（`http://localhost:3425`）已通过 `NSAllowsLocalNetworking` 放行。

目录：

- `Magpie/Model`：网关 JSON 的模型，缺省字段都有默认值。
- `Magpie/Networking/MagpieClient.swift`：`/v1/magpie/*` 调用和错误映射。
- `Magpie/Storage/CredentialStore.swift`：钥匙串里的密钥。
- `Magpie/Session.swift`：登录状态和 `/me` 的最新结果。
- `Magpie/SetupSnippet.swift`：和网页 `/me` 一样的配置片段。
- `Magpie/Views`：登录、概览、请求、配置、设置。
- `MagpieTests`：解码、客户端、片段、钥匙串和登录流程的单元测试，`Fixtures` 里是本地网关的真实响应。
- `MagpieUITests`：对着真实网关走一遍所有页面。
