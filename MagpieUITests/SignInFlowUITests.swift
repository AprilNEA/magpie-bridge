import XCTest

/// Walks through the app against a gateway (a real one, or scripts/demo_gateway.py): a wrong key
/// shows an error, the right key enters the four panes, a day of the year heatmap is selected,
/// the chart switches time range and dimension, requests are filtered to failed only, and
/// forgetting the key returns to the input page. Needs MAGPIE_TEST_GATEWAY_URL and MAGPIE_TEST_GATEWAY_KEY; when MAGPIE_SCREENSHOT_DIR is
/// given, a screenshot of every pane is saved there.
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
        // A wrong entry must be editable; the field's content (secure entry shows dots) must not be
        // cleared.
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

        // The three usage periods are tappable: tapping 7 days switches the section below to its
        // four-kind token bar plus cache hits, failure rate, and average per call.
        let weekCell = element(app, "overview.usage.7d")
        XCTAssertTrue(weekCell.waitForExistence(timeout: 5), app.debugDescription)
        weekCell.tap()
        XCTAssertTrue(
            element(app, "overview.usage.mix").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(weekCell.isSelected, app.debugDescription)
        XCTAssertFalse(element(app, "overview.usage.today").isSelected)
        XCTAssertTrue(app.staticTexts["缓存命中"].exists, app.debugDescription)
        shot(app, "overview-usage-7d")

        // Below usage is the year heatmap, resting on the newest weeks. The line under it tells
        // the year's figures; tapping a day switches it to that day's, tapping again switches back.
        bring(app, app.staticTexts["过去一年"], toTop: 0.2)
        let heatmap = element(app, "overview.heatmap")
        XCTAssertTrue(heatmap.waitForExistence(timeout: 20), app.debugDescription)
        let yearFigures = element(app, "overview.heatmap.year")
        XCTAssertTrue(yearFigures.waitForExistence(timeout: 5), app.debugDescription)
        shot(app, "overview-heatmap")
        if heatmap.exists {
            let day = heatmap.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            day.tap()
            XCTAssertTrue(
                element(app, "overview.heatmap.selected").waitForExistence(timeout: 5),
                app.debugDescription)
            shot(app, "overview-heatmap-selected")
            day.tap()
            XCTAssertTrue(yearFigures.waitForExistence(timeout: 5), app.debugDescription)
        }

        // The heatmap's own menu switches what it shades; switch back to tokens when done, since
        // the charts below share the metric.
        let heatmapMetric = element(app, "overview.heatmap.metric")
        XCTAssertTrue(heatmapMetric.waitForExistence(timeout: 5), app.debugDescription)
        if heatmapMetric.exists {
            heatmapMetric.tap()
            app.buttons["费用"].firstMatch.tap()
            sleep(1)
            shot(app, "overview-heatmap-cost")
            heatmapMetric.tap()
            app.buttons["Tokens"].firstMatch.tap()
        }

        // The trend chart comes next; put its header a little above the middle so the whole chart
        // is on screen. Then tap a bar and the detail for that period floats up above it.
        bring(app, app.staticTexts["趋势"], toTop: 0.43)
        let trend = element(app, "overview.trend")
        let trendShown = trend.waitForExistence(timeout: 20)
        XCTAssertTrue(trendShown, app.debugDescription)
        if trendShown {
            let bar = trend.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.45))
            bar.tap()
            let selection = element(app, "overview.selection")
            XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.frame.contains(selection.frame), "明细卡片跑到屏幕外了：\(selection.frame)")
            shot(app, "overview-selected")
            // Tap again to deselect (hitting the bar or the card both work) so later screenshots
            // do not carry a dimmed bar.
            bar.tap()
            XCTAssertTrue(waitUntilGone(selection), app.debugDescription)
        }

        // Changing the time range must update the trend chart and the summary below it.
        app.buttons["30 天"].firstMatch.tap()
        let summary = app.staticTexts["overview.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), app.debugDescription)
        if summary.exists {
            XCTAssertTrue(summary.label.hasPrefix("30 天："), summary.label)
        }
        shot(app, "overview-30d")

        // The 30-day chart scrolls horizontally and rests on the latest bucket; tapping a bar on
        // the scrolled chart must also select it, and the detail card must match.
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

        // Switch the same data to an area chart; a tap must select there too. Switch back to bars
        // when done.
        let area = app.buttons["面积图"].firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5), app.debugDescription)
        if area.exists, trendShown {
            area.tap()
            sleep(1)
            shot(app, "overview-area")
            let point = trend.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45))
            point.tap()
            let selection = element(app, "overview.selection")
            XCTAssertTrue(selection.waitForExistence(timeout: 5), app.debugDescription)
            shot(app, "overview-area-selected")
            point.tap()
            XCTAssertTrue(waitUntilGone(selection), app.debugDescription)
            app.buttons["柱状图"].firstMatch.tap()
        }

        // Switch the metric to cost.
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
            // Tap a segment of the ring; the center switches to its name and share.
            share.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(
                element(app, "overview.share.selected").waitForExistence(timeout: 5),
                app.debugDescription)
        }
        shot(app, "overview-agents")

        // At the very bottom is the web /me "most used in the last 30 days", independent of the
        // period chosen above; the listed models must be visible.
        scroll(app, by: 0.5)
        let top = element(app, "overview.top")
        XCTAssertTrue(top.waitForExistence(timeout: 10), app.debugDescription)
        shot(app, "overview-top")

        // Tap a frequently used model to enter the 30-day requests filtered by it: a model chip at
        // the top, and every row in the list is that model.
        tapRow(top)
        let modelChip = app.buttons["requests.chip.model"]
        XCTAssertTrue(modelChip.waitForExistence(timeout: 20), app.debugDescription)
        let pickedSummary = app.staticTexts["requests.summary"]
        XCTAssertTrue(pickedSummary.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(pickedSummary.label.hasPrefix("筛选后："), pickedSummary.label)
        let pickedRow = app.staticTexts["requests.row.model"].firstMatch
        XCTAssertTrue(pickedRow.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(
            modelChip.label.contains(pickedRow.label), "\(modelChip.label) / \(pickedRow.label)")
        shot(app, "overview-top-requests")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(top.waitForExistence(timeout: 10), app.debugDescription)

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

        // Failed only: check it in the filter menu, the summary gains a "filtered" prefix, and a
        // chip appears at the top; the failed row's detail shows an error type (a row rejected by
        // the gateway has none, and its status reads "rejected by the gateway"). Tapping the chip
        // clears the filter.
        let requestsSummary = app.staticTexts["requests.summary"]
        let unfiltered = requestsSummary.label
        app.buttons["requests.filter"].tap()
        let failedOnly = app.buttons["只看失败"].firstMatch
        XCTAssertTrue(failedOnly.waitForExistence(timeout: 5), app.debugDescription)
        failedOnly.tap()
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH '筛选后：'"), object: requestsSummary)
        XCTAssertEqual(
            XCTWaiter().wait(for: [filtered], timeout: 20), .completed, app.debugDescription)
        XCTAssertNotEqual(requestsSummary.label, unfiltered)
        let chip = app.buttons["requests.chip.failed"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription)
        let failedRow = app.staticTexts["requests.row.model"].firstMatch
        XCTAssertTrue(failedRow.waitForExistence(timeout: 10))
        shot(app, "requests-failed")
        tapRow(failedRow)
        XCTAssertTrue(app.navigationBars["请求详情"].waitForExistence(timeout: 10))
        // The latest failure is either an error returned by the provider (with an error type) or a
        // request the gateway itself rejected; the status row reads as "status, rejected by the
        // gateway 404", so match by containment.
        let rejected = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "网关拒绝")
        ).firstMatch
        XCTAssertTrue(app.staticTexts["错误类型"].exists || rejected.exists, app.debugDescription)
        shot(app, "request-detail-failed")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(waitUntilGone(chip), app.debugDescription)

        app.tabBars.buttons["配置"].tap()
        XCTAssertTrue(app.staticTexts["~/.claude/settings.json"].waitForExistence(timeout: 10))
        // The model row shows the selected model's id, which defaults to the most used one.
        let chosen = app.staticTexts["setup.model"]
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(chosen.label, "未选择")
        shot(app, "setup-claude")
        app.buttons["Codex"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["~/.codex/config.toml"].waitForExistence(timeout: 5))
        shot(app, "setup-codex")
        tapRow(app.staticTexts["模型"].firstMatch)
        XCTAssertTrue(app.navigationBars["这个密钥可用的模型"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        shot(app, "models")
        app.navigationBars.buttons.firstMatch.tap()

        // Settings pane: one progress bar row per limit from /limit, then further down the issuer's
        // limits, forget key, and about.
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["受限于"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "settings.limit").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["MCP 服务器"].exists, app.debugDescription)
        shot(app, "settings")
        let forget = app.buttons["settings.forget"]
        reveal(app, forget)
        XCTAssertTrue(element(app, "settings.issuerLimit").exists, app.debugDescription)
        shot(app, "settings-bottom")
        forget.tap()
        app.buttons["确定忘记"].tap()
        XCTAssertTrue(app.secureTextFields["signin.key"].waitForExistence(timeout: 10))
    }

    /// Scrolls up until the element is hittable. List creates elements only for rows scrolled on
    /// screen, so when the page is longer than the screen, even exists is false for the button at
    /// the bottom until it scrolls into view; waiting for it to exist first does not work.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<4 where !element.isHittable {
            scroll(app, by: 0.5)
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    /// Finds things like charts that are neither buttons nor text by accessibilityIdentifier.
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

    /// Scrolls the list until the element's top is at the given fraction of the screen height,
    /// to within a few points. A row far below the screen does not exist yet, so the list is
    /// scrolled up first until it does.
    @MainActor
    private func bring(_ app: XCUIApplication, _ element: XCUIElement, toTop fraction: CGFloat) {
        for _ in 0..<4 where !element.exists {
            scroll(app, by: 0.4)
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        let height = app.frame.height
        for _ in 0..<4 where element.exists {
            let distance = element.frame.minY / height - fraction
            if abs(distance) * height < 24 { break }
            scroll(app, by: min(0.6, max(-0.6, distance)))
        }
    }

    /// Drags along the left margin, up for a positive fraction of the screen height and down for
    /// a negative one, scrolling as far as the drag; the drag does not start on the chart, so its
    /// selection gesture cannot take the touch over.
    @MainActor
    private func scroll(_ app: XCUIApplication, by fraction: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5 + fraction / 2))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5 - fraction / 2))
        start.press(
            forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// On iOS 26 the content of a NavigationLink in a List yields no hit point ({-1, -1}), so a
    /// plain tap() is swallowed; tapping the coordinate at the element's geometric center bypasses
    /// the hit check.
    @MainActor
    private func tapRow(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// When a key left by the previous run is still in the Keychain, forgets it from the settings
    /// pane first.
    @MainActor
    private func forgetKeyIfSignedIn(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["设置"]
        guard settings.waitForExistence(timeout: 5) else { return }
        settings.tap()
        let forget = app.buttons["settings.forget"]
        reveal(app, forget)
        forget.tap()
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
