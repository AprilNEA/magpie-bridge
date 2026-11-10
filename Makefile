.PHONY: generate format lint build test ui-test check demo-gateway

DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
XCODEBUILD = xcodebuild -project Magpie.xcodeproj -scheme Magpie -derivedDataPath .build/DerivedData
XCODEBUILD_UNSIGNED = $(XCODEBUILD) CODE_SIGNING_ALLOWED=NO

generate: Config/Local.xcconfig
	xcodegen generate

Config/Local.xcconfig:
	cp Config/Local.xcconfig.example $@

format:
	xcrun swift-format format --in-place --recursive Magpie MagpieTests MagpieUITests

lint:
	xcrun swift-format lint --strict --recursive Magpie MagpieTests MagpieUITests
	swiftlint lint --strict

build:
	$(XCODEBUILD_UNSIGNED) -destination 'generic/platform=iOS Simulator' build

test:
	$(XCODEBUILD_UNSIGNED) -destination '$(DESTINATION)' -skip-testing:MagpieUITests test

# Needs a reachable gateway: MAGPIE_TEST_GATEWAY_URL and MAGPIE_TEST_GATEWAY_KEY,
# and optionally MAGPIE_SCREENSHOT_DIR to save a screenshot of every pane.
# Keeps the simulator's ad-hoc signing: without entitlements the Keychain reports errSecMissingEntitlement.
ui-test:
	TEST_RUNNER_MAGPIE_TEST_GATEWAY_URL='$(MAGPIE_TEST_GATEWAY_URL)' \
	TEST_RUNNER_MAGPIE_TEST_GATEWAY_KEY='$(MAGPIE_TEST_GATEWAY_KEY)' \
	TEST_RUNNER_MAGPIE_SCREENSHOT_DIR='$(MAGPIE_SCREENSHOT_DIR)' \
	$(XCODEBUILD) -destination '$(DESTINATION)' -only-testing:MagpieUITests test

check: lint build test

# View the panes without a real gateway: starts a local demo gateway with 53 weeks of fake data, key sk-magpie-key-demo.
demo-gateway:
	python3 scripts/demo_gateway.py --port 3427
