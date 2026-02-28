SDK := $(shell xcrun --show-sdk-path)
TARGET := arm64-apple-macosx13.0
SOURCES := $(wildcard BatteryBar/Model/*.swift BatteryBar/View/*.swift BatteryBar/App/*.swift BatteryBar/Utility/*.swift)
APP_BUNDLE := BatteryBar.app
BINARY := $(APP_BUNDLE)/Contents/MacOS/BatteryBar

.PHONY: build run clean install release

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@cp $(APP_BUNDLE)/Contents/Info.plist $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || true
	swiftc -parse-as-library \
		-framework SwiftUI -framework Charts -framework IOKit -framework Combine -framework AppKit \
		-target $(TARGET) -sdk $(SDK) \
		-O \
		$(SOURCES) \
		-o $(BINARY)
	@echo "Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE)/Contents/MacOS/BatteryBar BatteryBar.app.zip

install: build
	cp -R $(APP_BUNDLE) /Applications/BatteryBar.app
	@echo "Installed to /Applications/BatteryBar.app"

release: build
	@strip $(BINARY)
	cd . && zip -r BatteryBar.app.zip $(APP_BUNDLE)
	@echo "Created BatteryBar.app.zip"
