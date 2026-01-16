SHELL := /bin/sh

# Project configuration
SCHEME ?= XboxControllerMapper
CONFIG ?= Release
TEAM_ID ?= 542GXYT5Z2
PROJECT := XboxControllerMapper/XboxControllerMapper.xcodeproj

# Load version from version.env
include version.env
export MARKETING_VERSION
export BUILD_NUMBER

# Derive build paths from xcodebuild settings
BUILD_SETTINGS = xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) 2>/dev/null
TARGET_BUILD_DIR := $(shell $(BUILD_SETTINGS) | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $$2; exit}')
WRAPPER_NAME := $(shell $(BUILD_SETTINGS) | awk -F ' = ' '/WRAPPER_NAME/ {print $$2; exit}')
APP_PATH := $(TARGET_BUILD_DIR)/$(WRAPPER_NAME)
PROCESS_NAME := $(basename $(WRAPPER_NAME))

.PHONY: build install clean release sign-and-notarize app-path help

help:
	@echo "Xbox Controller Mapper - Build Commands"
	@echo ""
	@echo "  make build     - Build the app (Release configuration)"
	@echo "  make install   - Build and install to /Applications"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make release   - Full release workflow (sign, notarize, create GitHub release)"
	@echo "  make app-path  - Show the built app path"
	@echo ""
	@echo "Configuration:"
	@echo "  CONFIG=$(CONFIG) SCHEME=$(SCHEME)"
	@echo "  Version: $(MARKETING_VERSION) ($(BUILD_NUMBER))"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		MARKETING_VERSION=$(MARKETING_VERSION) \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		-allowProvisioningUpdates \
		build

install: build
	-pkill -x "$(PROCESS_NAME)" || true
	@sleep 1
	/usr/bin/ditto "$(APP_PATH)" "/Applications/$(WRAPPER_NAME)"
	@echo "Installed to /Applications/$(WRAPPER_NAME)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf "$(TARGET_BUILD_DIR)"

release:
	@./Scripts/release.sh

sign-and-notarize:
	@./Scripts/sign-and-notarize.sh

app-path:
	@echo "$(APP_PATH)"
