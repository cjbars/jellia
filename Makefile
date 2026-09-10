# Основные параметры приложения
APP_NAME := Jellia
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
INSTALL_DIR ?= /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

SOURCES := $(shell find Sources -name '*.swift' | sort)
INFO_PLIST := Resources/Info.plist
APP_RESOURCES := \
	Resources/Jellia.icns

VERSION ?= 0.1.5
# Номер сборки выводится из версии: 0.1.5 → 10500, 0.2.0 → 20000, 1.0.0 → 1000000.
# Так номер монотонно растёт вместе с версией и совпадает у локальной и релизной сборки.
# Для пересборки той же версии оставлен зазор: BUILD_NUMBER=10501.
BUILD_NUMBER ?= $(shell echo "$(VERSION)" | awk -F. '{printf "%d", ($$1*1000000)+($$2*10000)+($$3*100)}')
ARCH ?= $(shell uname -m)
# Список архитектур приложения: локально — своя, в релизе — «arm64 x86_64».
ARCHS ?= $(ARCH)
MACOSX_DEPLOYMENT_TARGET ?= 26.0
AVAILABLE_CODE_SIGN_IDENTITY := $(shell security find-identity -v -p codesigning | grep -m 1 '"' | cut -d '"' -f 2)
CODE_SIGN_IDENTITY ?= $(if $(AVAILABLE_CODE_SIGN_IDENTITY),$(AVAILABLE_CODE_SIGN_IDENTITY),-)

SWIFT_FLAGS := \
	-module-cache-path "$(BUILD_DIR)/ModuleCache" \
	-swift-version 6 \
	-strict-concurrency=complete \
	-warnings-as-errors \
	-O \
	-whole-module-optimization \
	-framework AppKit \
	-framework SwiftUI \
	-framework UserNotifications \
	-framework AVFoundation \
	-framework MediaPlayer \
	-framework Foundation \
	-framework Security

DMG := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
DMG_STAGING := $(BUILD_DIR)/dmg

.PHONY: build prepare run install install-run clean check test dmg

build: prepare
	for arch in $(ARCHS); do \
		swiftc $(SOURCES) $(SWIFT_FLAGS) \
			-target $$arch-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) \
			-Xlinker -rpath -Xlinker @executable_path/../Frameworks \
			-o "$(BUILD_DIR)/$(APP_NAME)-$$arch" || exit 1; \
	done
	lipo -create $(foreach arch,$(ARCHS),"$(BUILD_DIR)/$(APP_NAME)-$(arch)") \
		-output "$(MACOS_DIR)/$(APP_NAME)"
	rm -f $(foreach arch,$(ARCHS),"$(BUILD_DIR)/$(APP_NAME)-$(arch)")
	rm -rf "$(RESOURCES_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	cp "$(INFO_PLIST)" "$(CONTENTS_DIR)/Info.plist"
	for resource in $(APP_RESOURCES); do cp "$$resource" "$(RESOURCES_DIR)/"; done
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(CONTENTS_DIR)/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(APP_BUNDLE)"
	@echo "✅ Собрано: $(APP_BUNDLE) — v$(VERSION) ($(BUILD_NUMBER))"

prepare:
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"

run: build
	open "$(APP_BUNDLE)"

install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	@echo "✅ Установлено: $(INSTALLED_APP)"

install-run: install
	open "$(INSTALLED_APP)"

dmg: build
	rm -rf "$(DMG_STAGING)" "$(DMG)"
	mkdir -p "$(DMG_STAGING)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGING)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME) $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG)"
	rm -rf "$(DMG_STAGING)"
	@echo "✅ Образ: $(DMG)"

clean:
	rm -rf "$(BUILD_DIR)"

check: prepare
	swiftc $(SOURCES) $(SWIFT_FLAGS) -target $(ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) -typecheck
	$(MAKE) test

test: prepare
	swiftc Sources/AppIcons.swift Sources/JellyfinDTO.swift Sources/Models.swift Sources/PlaybackTime.swift Sources/ServerVersion.swift Sources/Stores/KeychainStore.swift Sources/Stores/SessionStore.swift Tests/CoreTests.swift \
		-module-cache-path "$(BUILD_DIR)/ModuleCache" \
		-target $(ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) \
		-swift-version 6 -warnings-as-errors \
		-o "$(BUILD_DIR)/JelliaCoreTests"
	"$(BUILD_DIR)/JelliaCoreTests"
