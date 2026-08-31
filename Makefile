SWIFT_TEST_FLAGS = -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-cache TMPDIR=$(CURDIR)/.build/tmp DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

all: setup build

setup:
	@bash scripts/setup_config.sh

build:
	@echo "==> Building Titik Swift release binary..."
	@mkdir -p .build/clang-cache .build/tmp bin
	@$(SWIFT_ENV) swift build -c release --disable-sandbox
	@cp .build/release/titik bin/titik
	@cp .build/release/titik-worker bin/titik-worker
	@echo "==> Binaries built at bin/titik and bin/titik-worker"

bundle: build
	@bash scripts/build_bundle.sh

install: bundle
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/Titik.app
	@cp -R bin/Titik.app $(HOME)/Applications/
	@echo "==> Installed Titik.app to $(HOME)/Applications/"

run: build
	@./bin/titik

test:
	@echo "==> Running Swift test suite..."
	@$(SWIFT_ENV) swift test --disable-sandbox $(SWIFT_TEST_FLAGS)

clean:
	@rm -rf bin .build
	@echo "==> Clean complete."

.PHONY: all setup build bundle install run clean test
