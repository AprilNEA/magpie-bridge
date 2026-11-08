import XCTest

/// 对着真实网关走一遍：错密钥报错、对密钥进入四个页面、忘记密钥回到输入页。
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
        shot(app, "overview")

        app.tabBars.buttons["请求"].tap()
        XCTAssertTrue(app.staticTexts["requests.summary"].waitForExistence(timeout: 20))
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
