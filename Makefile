# CleanCut developer commands. `make help` lists them.
SHELL := /bin/bash -o pipefail
DERIVED := .build/dd
PROJECT := CleanCut.xcodeproj
SIM ?= iPhone 17 Pro
FILTER := Tools/scripts/xcfilter.sh

.PHONY: help generate test test-ios build bench icon clean screenshots

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

generate: ## Generate CleanCut.xcodeproj from project.yml
	xcodegen generate --quiet

test: generate ## Run the CleanCutKit test suite natively on macOS
	xcodebuild test -project $(PROJECT) -scheme CleanCutKit -destination 'platform=macOS' -derivedDataPath $(DERIVED) | $(FILTER)

test-ios: generate ## Run the CleanCutKit test suite on the iOS Simulator
	xcodebuild test -project $(PROJECT) -scheme CleanCutKit -destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(DERIVED) | $(FILTER)

build: generate ## Build the iOS app for the Simulator
	xcodebuild build -project $(PROJECT) -scheme CleanCut -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED) | $(FILTER)

bench: generate ## Build the macOS benchmark CLI (see docs/BENCHMARKS.md)
	xcodebuild build -project $(PROJECT) -scheme cleancut-bench -configuration Release -destination 'platform=macOS' -derivedDataPath $(DERIVED) | $(FILTER)
	@echo "Binary: $(DERIVED)/Build/Products/Release/cleancut-bench"

icon: ## Re-render the app icon
	swift Tools/scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

clean: ## Remove build products
	rm -rf .build

screenshots: generate ## Run the UI flow test in the Simulator and export its screenshots to .build/screenshots
	rm -rf .build/ui.xcresult .build/screenshots
	xcodebuild test -project $(PROJECT) -scheme CleanCut -destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(DERIVED) -only-testing:CleanCutUITests -resultBundlePath .build/ui.xcresult | $(FILTER) || true
	xcrun xcresulttool export attachments --path .build/ui.xcresult --output-path .build/screenshots > /dev/null
	@Tools/scripts/export-screenshots.py .build/screenshots
