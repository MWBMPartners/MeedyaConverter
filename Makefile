# ============================================================================
# MeedyaConverter — Local Development Build & Package
# Copyright © 2026 MWBM Partners Ltd. All rights reserved.
# ============================================================================

# Configuration
APP_NAME := MeedyaConverter
CLI_NAME := meedya-convert
BUNDLE_ID := Ltd.MWBMpartners.MeedyaConverter
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.1.0")
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo "1")
CONFIGURATION := release
SIGNING_IDENTITY ?= -

# Paths
BUILD_DIR := .build/$(CONFIGURATION)
APP_BUNDLE := $(APP_NAME).app
DMG_NAME := $(APP_NAME)-$(VERSION)-macOS.dmg
ENTITLEMENTS := Sources/$(APP_NAME)/Resources/$(APP_NAME).entitlements
INFO_PLIST := Sources/$(APP_NAME)/Resources/Info.plist

.PHONY: all clean build build-debug test sign bundle package dmg dmg-signed install uninstall cli version lint validate help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: clean build test package dmg ## Full build pipeline

clean: ## Clean build artifacts
	swift package clean
	rm -rf $(APP_BUNDLE) $(DMG_NAME) release-staging

build: ## Build in release configuration
	swift build -c $(CONFIGURATION)

build-debug: ## Build in debug configuration
	swift build

test: ## Run all tests
	swift test --parallel

sign: build bundle ## Sign the app bundle with Developer ID (set SIGNING_IDENTITY)
	chmod +x scripts/codesign.sh
	APPLE_SIGNING_IDENTITY="$(SIGNING_IDENTITY)" ./scripts/codesign.sh "$(APP_BUNDLE)" "$(ENTITLEMENTS)"

bundle: build ## Create .app bundle structure
	@echo "Creating app bundle: $(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	# Substitute version and build number in Info.plist
	sed -e 's|<string>0.1.0</string>|<string>$(VERSION)</string>|' \
	    -e 's|<string>1</string><!-- build -->|<string>$(BUILD_NUMBER)</string>|' \
	    "$(INFO_PLIST)" > "$(APP_BUNDLE)/Contents/Info.plist"
	# Copy entitlements for reference
	cp "$(ENTITLEMENTS)" "$(APP_BUNDLE)/Contents/Resources/"
	chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@echo "App bundle created: $(APP_BUNDLE)"
	@echo "  Version: $(VERSION) (build $(BUILD_NUMBER))"

package: bundle ## Create .app bundle (alias for bundle)
	@echo "Package ready: $(APP_BUNDLE)"

dmg: bundle ## Create DMG disk image
	chmod +x scripts/create-dmg.sh
	./scripts/create-dmg.sh "$(APP_BUNDLE)" "$(VERSION)"
	@echo "DMG created: $(DMG_NAME)"

dmg-signed: sign ## Create signed DMG
	chmod +x scripts/create-dmg.sh
	./scripts/create-dmg.sh "$(APP_BUNDLE)" "$(VERSION)"
	codesign --force --sign "$(SIGNING_IDENTITY)" --timestamp "$(DMG_NAME)"
	@echo "Signed DMG created: $(DMG_NAME)"

install: bundle ## Install to /Applications (requires sudo)
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_BUNDLE)"

uninstall: ## Remove from /Applications
	rm -rf "/Applications/$(APP_BUNDLE)"
	@echo "Uninstalled $(APP_BUNDLE)"

cli: build ## Build CLI tool only
	@echo "CLI binary: $(BUILD_DIR)/$(CLI_NAME)"

version: ## Show version info
	@echo "App: $(APP_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Build: $(BUILD_NUMBER)"
	@echo "Bundle ID: $(BUNDLE_ID)"

lint: ## Run SwiftLint
	swiftlint lint --config .swiftlint.yml

validate: bundle ## Validate app bundle structure
	@echo "Validating $(APP_BUNDLE)..."
	@test -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" || (echo "ERROR: Missing executable" && exit 1)
	@test -f "$(APP_BUNDLE)/Contents/Info.plist" || (echo "ERROR: Missing Info.plist" && exit 1)
	@codesign --verify --deep --strict "$(APP_BUNDLE)" 2>/dev/null && echo "Signature: Valid" || echo "Signature: Not signed (use 'make sign')"
	@echo "Validation passed."
