import XCTest

/// 对着一个网关（真的，或 scripts/demo_gateway.py）走一遍：错密钥报错、对密钥进入四个页面、
/// 切图表的时间范围和维度、忘记密钥回到输入页。
/// 需要 MAGPIE_TEST_GATEWAY_URL 和 MAGPIE_TEST_GATEWAY_KEY；
/// 给了 MAGPIE_SCREENSHOT_DIR 就把每个页面的截图存进去。
final class SignInFlowUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    @MainActor
    func testSignInAndBrowseEveryPane() throws {
        guard let address = env["MAGPIE_TEST_GATEWAY_URL"], let key = env["MAGPIE_TEST_GATEWAY_KEY"]
        else {
            throw XCTSkip("需要 MAGPIE_TEST_GATEWAY_URL 和 MAGPIE_TEST_GATEWAY_KEY")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-gatewayAddress", address]
        app.launch()
        forgetKeyIfSignedIn(app)

        let addressField = app.textFields["signin.address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 10))
        XCTAssertEqual(addressField.value as? String, address)
        shot(app, "signin")

        let keyField = app.secureTextFields["signin.key"]
        keyField.tap()
        keyField.typeText("sk-magpie-key-wrong")
        app.buttons["signin.continue"].tap()
        XCTAssertTrue(app.staticTexts["signin.error"].waitForExistence(timeout: 20))
        // 输错了要能改，输入框里的内容（安全输入显示为圆点）不能被清掉。
        let kept = keyField.value as? String
        XCTAssertTrue(kept?.hasPrefix("•") == true, "输入框里剩下的是 \(kept ?? "nil")")
        shot(app, "signin-error")

        keyField.tap()
        keyField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        keyField.typeText(key)
        app.buttons["signin.continue"].tap()

        XCTAssertTrue(app.staticTexts["额度"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["用量"].exists)
        XCTAssertTrue(app.staticTexts["趋势"].exists)
        let trend = element(app, "overview.trend")
        let trendShown = trend.waitForExistence(timeout: 20)
        XCTAssertTrue(trendShown, app.debugDescription)
        shot(app, "overview")

        // 趋势图的下半截压在标签栏底下，先滚上来；然后点一根柱子，上面浮出那个时间段的明细。
        scroll(app, by: 0.4)
        if trendShown {
            let bar = trend.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.45))
            bar.tap()
            let selection = element(app, "overview.selection")
            XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.frame.contains(selection.frame), "明细卡片跑到屏幕外了：\(selection.frame)")
            shot(app, "overview-selected")
            // 再点一下取消（点到柱子或点到卡片都行），后面的截图不要带着压暗的柱子。
            bar.tap()
            XCTAssertTrue(waitUntilGone(selection), app.debugDescription)
        }

        // 换时间范围，趋势图和下面的汇总要跟着换。
        app.buttons["30 天"].firstMatch.tap()
        let summary = app.staticTexts["overview.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), app.debugDescription)
        if summary.exists {
            XCTAssertTrue(summary.label.hasPrefix("30 天："), summary.label)
        }
        shot(app, "overview-30d")

        // 30 天的图能横向滚动，停在最近的桶；滚动的图上点一根也要能选中、明细卡片要对得上。
        if trendShown {
            let bar = trend.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            bar.tap()
            let selection = element(app, "overview.selection")
            XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.frame.contains(selection.frame), "明细卡片跑到屏幕外了：\(selection.frame)")
            shot(app, "overview-30d-selected")
            bar.tap()
            XCTAssertTrue(waitUntilGone(selection), app.debugDescription)
        }

        // 换指标：费用。
        let metric = element(app, "overview.metric")
        XCTAssertTrue(metric.waitForExistence(timeout: 5), app.debugDescription)
        if metric.exists {
            metric.tap()
            let cost = app.buttons["费用"].firstMatch
            if cost.waitForExistence(timeout: 5) {
                cost.tap()
            }
            sleep(1)
            shot(app, "overview-cost")
        }

        scroll(app, by: 0.5)
        let share = element(app, "overview.share")
        XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "overview-breakdown")
        app.buttons["Agent"].firstMatch.tap()
        sleep(1)
        if share.exists {
            // 点环上的一块，中间换成它的名字和占比。
            share.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(
                element(app, "overview.share.selected").waitForExistence(timeout: 5),
                app.debugDescription)
        }
        shot(app, "overview-agents")

        app.tabBars.buttons["请求"].tap()
        XCTAssertTrue(app.staticTexts["requests.summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "requests.trend").waitForExistence(timeout: 10))
        let firstRow = app.staticTexts["requests.row.model"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        shot(app, "requests")
        tapRow(firstRow)
        XCTAssertTrue(app.navigationBars["请求详情"].waitForExistence(timeout: 10))
        shot(app, "request-detail")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["配置"].tap()
        XCTAssertTrue(app.staticTexts["~/.claude/settings.json"].waitForExistence(timeout: 10))
        shot(app, "setup-claude")
        app.buttons["Codex"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["~/.codex/config.toml"].waitForExistence(timeout: 5))
        shot(app, "setup-codex")
        tapRow(app.staticTexts["模型"].firstMatch)
        XCTAssertTrue(app.navigationBars["这个密钥可用的模型"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        shot(app, "models")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.forget"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["受限于"].waitForExistence(timeout: 10))
        shot(app, "settings")
        app.buttons["settings.forget"].tap()
        app.buttons["确定忘记"].tap()
        XCTAssertTrue(app.secureTextFields["signin.key"].waitForExistence(timeout: 10))
    }

    /// 图表这类不是按钮也不是文字的东西，按 accessibilityIdentifier 找。
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// 沿着左边的留白往上拖，拖多少滚多少；不从图表上起手，免得被它的选择手势接走。
    @MainActor
    private func scroll(_ app: XCUIApplication, by fraction: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85 - fraction))
        start.press(
            forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// List 里 NavigationLink 的内容在 iOS 26 上算不出命中点（{-1, -1}），直接 tap() 会被吞掉；
    /// 按元素的几何中心坐标点能绕过命中检查。
    @MainActor
    private func tapRow(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// 上一次运行留下的密钥还在钥匙串里时，先从设置页忘记它。
    @MainActor
    private func forgetKeyIfSignedIn(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["设置"]
        guard settings.waitForExistence(timeout: 5) else { return }
        settings.tap()
        app.buttons["settings.forget"].tap()
        app.buttons["确定忘记"].tap()
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["MAGPIE_SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }
}
