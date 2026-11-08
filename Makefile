.PHONY: generate format lint build test ui-test check

DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
XCODEBUILD = xcodebuild -project Magpie.xcodeproj -scheme Magpie -derivedDataPath .build/DerivedData
XCODEBUILD_UNSIGNED = $(XCODEBUILD) CODE_SIGNING_ALLOWED=NO

generate:
	xcodegen generate

format:
	xcrun swift-format format --in-place --recursive Magpie MagpieTests MagpieUITests

lint:
	xcrun swift-format lint --strict --recursive Magpie MagpieTests MagpieUITests
	swiftlint lint --strict

build:
	$(XCODEBUILD_UNSIGNED) -destination 'generic/platform=iOS Simulator' build

test:
	$(XCODEBUILD_UNSIGNED) -destination '$(DESTINATION)' -skip-testing:MagpieUITests test

# 需要一个能连上的网关：MAGPIE_TEST_GATEWAY_URL 和 MAGPIE_TEST_GATEWAY_KEY，
# 可选 MAGPIE_SCREENSHOT_DIR 保存每个页面的截图。
# 保留模拟器的 ad-hoc 签名：没有 entitlements 时钥匙串会报 errSecMissingEntitlement。
ui-test:
	TEST_RUNNER_MAGPIE_TEST_GATEWAY_URL='$(MAGPIE_TEST_GATEWAY_URL)' \
	TEST_RUNNER_MAGPIE_TEST_GATEWAY_KEY='$(MAGPIE_TEST_GATEWAY_KEY)' \
	TEST_RUNNER_MAGPIE_SCREENSHOT_DIR='$(MAGPIE_SCREENSHOT_DIR)' \
	$(XCODEBUILD) -destination '$(DESTINATION)' -only-testing:MagpieUITests test

check: lint build test
