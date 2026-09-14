SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx13.0
SOURCES := $(wildcard BatteryBar/Model/*.swift BatteryBar/View/*.swift BatteryBar/App/*.swift BatteryBar/Utility/*.swift)
TEST_SOURCES := $(wildcard BatteryBar/Model/*.swift BatteryBar/Utility/*.swift BatteryBar/Tests/*.swift)
FRAMEWORKS := -framework SwiftUI -framework Charts -framework IOKit -framework Combine -framework AppKit
BINARY := .build/BatteryBar
APP_BUNDLE := BatteryBar.app
PLIST := BatteryBar/Resources/Info.plist
ICON := .build/BatteryBar.icns

export SIGNING_IDENTITY NOTARY_PROFILE NOTARY_KEYCHAIN RELEASE_TAG REQUIRE_LAYERED_ICON

.PHONY: build run clean install release test verify

build: $(BINARY) $(PLIST) $(ICON)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp $(PLIST) $(APP_BUNDLE)/Contents/Info.plist
	@cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/BatteryBar
	@cp $(ICON) $(APP_BUNDLE)/Contents/Resources/BatteryBar.icns
	@bash scripts/add-layered-icon.sh $(APP_BUNDLE)
	codesign --force --sign - $(APP_BUNDLE)
	@bash scripts/verify-app.sh $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) for local use"

$(ICON): artwork/AppIcon.png scripts/build-icon.sh
	@bash scripts/build-icon.sh $@

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
	@bash scripts/install.sh $(APP_BUNDLE)

release:
	@bash scripts/release.sh
