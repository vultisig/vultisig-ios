# Makefile for vultisig-ios.
#
# Run from the repo root. The Xcode project lives in VultisigApp/ and is
# generated from VultisigApp/project.yml via XcodeGen — never edit
# project.pbxproj directly.
#
# Common commands:
#   make bootstrap   # first-time setup (install tools + generate project)
#   make generate    # regenerate xcodeproj after project.yml / source changes
#   make test        # run unit tests
#   make ui_test     # run UI tests
#   make help        # list all targets

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

.PHONY: help bootstrap generate open build-check test ui_test

# Paths
VULTISIG_APP_DIR := VultisigApp
PROJECT          := VultisigApp.xcodeproj

# Overridable via environment: `make test DESTINATION='...'`
# DESTINATION: used by `test` / `ui_test` — must name a specific simulator the
# runner has available. Override for older Xcode installs that don't ship the
# iPhone 17 runtime.
DESTINATION       ?= platform=iOS Simulator,name=iPhone 17 Pro Max
# BUILD_DESTINATION: used by `build-check` (compile-only — no device needed).
# Generic target works on any Xcode; avoids CI failures when the named
# simulator isn't installed.
BUILD_DESTINATION ?= generic/platform=iOS Simulator
APP_SCHEME        ?= VultisigApp
UI_SCHEME         ?= VultisigAppUITests

# Tool detection (evaluated at invocation)
BREW      := $(shell command -v brew 2>/dev/null)
XCODEGEN  := $(shell command -v xcodegen 2>/dev/null)
SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)

help: ## List all targets
	@echo "Available targets:"
	@echo "  make bootstrap   — install XcodeGen + SwiftLint (via Homebrew) and generate the Xcode project"
	@echo "  make generate    — regenerate VultisigApp.xcodeproj from VultisigApp/project.yml"
	@echo "  make open        — regenerate the project and open it in Xcode"
	@echo "  make build-check — compile-only build check (for automation; tails 20 lines of output)"
	@echo "  make test        — run unit tests on iOS simulator ($(APP_SCHEME) scheme)"
	@echo "  make ui_test     — run UI tests on iOS simulator ($(UI_SCHEME) scheme)"
	@echo ""
	@echo "Overrides:"
	@echo "  DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'     # test / ui_test"
	@echo "  BUILD_DESTINATION='generic/platform=iOS Simulator'          # build-check"
	@echo "  APP_SCHEME=VultisigApp  UI_SCHEME=VultisigAppUITests"

bootstrap: ## Install tooling and generate the Xcode project
	@if [ -z "$(BREW)" ]; then \
		echo "error: Homebrew is required. Install from https://brew.sh"; \
		exit 1; \
	fi
	@if [ -z "$(XCODEGEN)" ]; then \
		echo "Installing XcodeGen..."; \
		brew install xcodegen; \
	fi
	@if [ -z "$(SWIFTLINT)" ]; then \
		echo "Installing SwiftLint..."; \
		brew install swiftlint; \
	fi
	@$(MAKE) --no-print-directory generate

generate: ## Regenerate the Xcode project from project.yml
	@if [ -z "$(XCODEGEN)" ]; then \
		echo "error: xcodegen not installed. Run: make bootstrap"; \
		exit 1; \
	fi
	@cd $(VULTISIG_APP_DIR) && xcodegen generate --spec project.yml

open: generate ## Regenerate the project and open it in Xcode
	@cd $(VULTISIG_APP_DIR) && open $(PROJECT)

build-check: generate ## Compile-only build check (no tests). Used by automation skills.
	@cd $(VULTISIG_APP_DIR) && xcodebuild build \
		-project $(PROJECT) \
		-scheme $(APP_SCHEME) \
		-destination '$(BUILD_DESTINATION)' \
		-skipMacroValidation \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		2>&1 | tail -20

test: ## Run unit tests
	@cd $(VULTISIG_APP_DIR) && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(APP_SCHEME) \
		-destination '$(DESTINATION)' \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO

ui_test: ## Run UI tests
	@cd $(VULTISIG_APP_DIR) && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(UI_SCHEME) \
		-destination '$(DESTINATION)' \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO
