DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)
NCPU ?= $(shell sysctl -n hw.ncpu 2>/dev/null || echo 4)
SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-cache TMPDIR=$(CURDIR)/.build/tmp DYLD_LIBRARY_PATH=$(DEVELOPER_DIR)/Library/Developer/usr/lib DYLD_FRAMEWORK_PATH=$(DEVELOPER_DIR)/Library/Developer/Frameworks
SWIFT_TEST_FLAGS = -Xswiftc -F$(DEVELOPER_DIR)/Library/Developer/Frameworks -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/Frameworks -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/usr/lib

all: setup build

setup:
	@bash scripts/setup_config.sh

build:
	@echo "==> Building Titik Swift release binary..."
	@mkdir -p .build/clang-cache .build/tmp bin
	@$(SWIFT_ENV) swift build -c release -j $(NCPU) --disable-sandbox
	@cp .build/release/titik bin/titik
	@cp .build/release/titik-worker bin/titik-worker
	@echo "==> Binaries built at bin/titik and bin/titik-worker"

bundle: build
	@bash scripts/build_bundle.sh

verify: test bundle

install-hooks:
	@git config core.hooksPath .githooks && chmod +x .githooks/* 2>/dev/null || true

install: bundle
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/Titik.app
	@cp -R bin/Titik.app $(HOME)/Applications/
	@echo "==> Installed Titik.app to $(HOME)/Applications/"

run: build
	@./bin/titik

test:
	@echo "==> Running Swift test suite..."
	@mkdir -p .build/clang-cache .build/tmp
	@$(SWIFT_ENV) swift test --parallel -j $(NCPU) --disable-sandbox $(SWIFT_TEST_FLAGS)

plugins:
	@echo "==> Native Swift plugins are built with 'make build'"

clean:
	@rm -rf bin .build
	@echo "==> Clean complete."

.PHONY: all setup build bundle install run clean test plugins verify install-hooks

