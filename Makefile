DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)
NCPU ?= $(shell sysctl -n hw.ncpu 2>/dev/null || echo 4)
SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-cache TMPDIR=$(CURDIR)/.build/tmp DYLD_LIBRARY_PATH=$(DEVELOPER_DIR)/Library/Developer/usr/lib DYLD_FRAMEWORK_PATH=$(DEVELOPER_DIR)/Library/Developer/Frameworks
SWIFT_TEST_FLAGS = -Xswiftc -F$(DEVELOPER_DIR)/Library/Developer/Frameworks -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/Frameworks -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/usr/lib
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
SWIFT_FORMAT := $(shell command -v swift-format 2>/dev/null)
SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)

all: setup build

setup: install-hooks
	@bash scripts/setup_config.sh

build:
	@echo "==> Building Titik Swift release binary..."
	@mkdir -p .build/clang-cache .build/tmp bin
	@$(SWIFT_ENV) swift build -c release -j $(NCPU) --disable-sandbox
	@cp .build/release/titik bin/titik
	@cp .build/release/titik-worker bin/titik-worker
	@codesign -s - -f bin/titik-worker 2>/dev/null || true
	@echo "==> Binaries built at bin/titik and bin/titik-worker"

bundle: build plugins
	@bash scripts/build_bundle.sh

verify: test bundle

install-hooks:
	@git config core.hooksPath .githooks 2>/dev/null || [ "$$(git config core.hooksPath 2>/dev/null)" = ".githooks" ] || git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "==> Git hooks configured to .githooks/"

format:
ifdef SWIFT_FORMAT
	@echo "==> Formatting Swift sources..."
	@swift-format format --in-place --recursive Sources Tests
else
	@echo "warning: swift-format not found. Run 'brew install swift-format' to enable formatting."
endif

format-check:
ifdef SWIFT_FORMAT
	@echo "==> Checking format with swift-format..."
	@swift-format lint --recursive Sources Tests
else
	@echo "warning: swift-format not found. Skipping format check."
endif

lint:
ifdef SWIFTLINT
	@echo "==> Running SwiftLint..."
	@DYLD_FRAMEWORK_PATH=$(DEVELOPER_DIR)/usr/lib swiftlint lint
else
	@echo "warning: swiftlint not found. Skipping linting."
endif

lint-fix:
ifdef SWIFTLINT
	@echo "==> Running SwiftLint fix..."
	@DYLD_FRAMEWORK_PATH=$(DEVELOPER_DIR)/usr/lib swiftlint --fix
else
	@echo "warning: swiftlint not found. Run 'brew install swiftlint' to enable lint-fix."
endif

install: bundle
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/Titik.app
	@cp -R bin/Titik.app $(HOME)/Applications/
	@echo "==> Installed Titik.app to $(HOME)/Applications/"

run: build
	@./bin/titik

test:
	@killall -9 swiftpm-testing-helper 2>/dev/null || true
	@echo "==> Running Swift test suite..."
	@mkdir -p .build/clang-cache .build/tmp
	@$(SWIFT_ENV) swift test -j 1 --disable-sandbox $(SWIFT_TEST_FLAGS)
	@killall -9 swiftpm-testing-helper 2>/dev/null || true

test-unit:
	@killall -9 swiftpm-testing-helper 2>/dev/null || true
	@echo "==> Running Swift unit tests..."
	@mkdir -p .build/clang-cache .build/tmp
	@$(SWIFT_ENV) swift test --parallel -j $(NCPU) --disable-sandbox $(SWIFT_TEST_FLAGS) --filter "TitikParserTests|TitikCoreTests|TitikKeymapTests"
	@killall -9 swiftpm-testing-helper 2>/dev/null || true

test-fast: test-unit

test-e2e:
	@killall -9 swiftpm-testing-helper 2>/dev/null || true
	@echo "==> Running Swift E2E tests..."
	@mkdir -p .build/clang-cache .build/tmp
	@$(SWIFT_ENV) swift test --parallel -j $(NCPU) --disable-sandbox $(SWIFT_TEST_FLAGS) --filter TitikE2ETests
	@killall -9 swiftpm-testing-helper 2>/dev/null || true

test-plugins:
	@killall -9 swiftpm-testing-helper 2>/dev/null || true
	@echo "==> Running Swift plugin tests..."
	@mkdir -p .build/clang-cache .build/tmp
	@$(SWIFT_ENV) swift test --parallel -j $(NCPU) --disable-sandbox $(SWIFT_TEST_FLAGS) --filter TitikPluginsTests
	@killall -9 swiftpm-testing-helper 2>/dev/null || true

plugins:
	@bash scripts/build_zen_plugin.sh
	@bash scripts/build_activity_monitor_plugin.sh
	@bash scripts/build_notes_plugin.sh

clean:
	@rm -rf bin .build
	@echo "==> Clean complete."

.PHONY: all setup build bundle install run clean test plugins verify install-hooks format format-check lint lint-fix test-unit test-fast test-e2e test-plugins
