SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx13.0
SOURCES := $(wildcard BatteryBar/Model/*.swift BatteryBar/View/*.swift BatteryBar/App/*.swift BatteryBar/Utility/*.swift)
TEST_SOURCES := $(wildcard BatteryBar/Model/*.swift BatteryBar/Utility/*.swift BatteryBar/Tests/*.swift)
FRAMEWORKS := -framework SwiftUI -framework Charts -framework IOKit -framework Combine -framework AppKit
BINARY := .build/BatteryBar
APP_BUNDLE := BatteryBar.app
PLIST := BatteryBar/Resources/Info.plist

export SIGNING_IDENTITY NOTARY_PROFILE NOTARY_KEYCHAIN RELEASE_TAG

.PHONY: build run clean install release test verify

build: $(BINARY) $(PLIST)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@cp $(PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/BatteryBar
	codesign --force --sign - $(APP_BUNDLE)
	@bash scripts/verify-app.sh $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) for local use"

$(BINARY): $(SOURCES) Makefile
	@mkdir -p .build
	xcrun swiftc -parse-as-library $(FRAMEWORKS) \
		-target $(TARGET) -sdk $(SDK) -O $(SOURCES) -o $(BINARY)

run: build
	open $(APP_BUNDLE)

test:
	@mkdir -p .build
	xcrun swiftc -parse-as-library $(FRAMEWORKS) \
		-target $(TARGET) -sdk $(SDK) $(TEST_SOURCES) -o .build/batterybar-tests
	@.build/batterybar-tests

verify:
	@bash scripts/verify-app.sh $(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE) dist BatteryBar.app.zip

install: build
	ditto $(APP_BUNDLE) /Applications/BatteryBar.app
	@echo "Installed to /Applications/BatteryBar.app"

release:
	@bash scripts/release.sh
