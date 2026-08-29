SWIFT_TEST_FLAGS = -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
SWIFT_ENV = DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

all: setup plugins build

setup:
	@bash scripts/setup_config.sh

plugins:
	@$(MAKE) -C plugins/math_plugin

build: plugins
	@echo "==> Building Titik Swift release binary..."
	@swift build -c release
	@mkdir -p bin
	@cp .build/release/titik bin/titik
	@echo "==> Binary built at bin/titik"

bundle: build
	@bash scripts/build_bundle.sh

install: bundle
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/Titik.app
	@cp -R bin/Titik.app $(HOME)/Applications/
	@echo "==> Installed Titik.app to $(HOME)/Applications/"

run: build
	@./bin/titik

test: plugins
	@echo "==> Running Swift test suite..."
	@$(SWIFT_ENV) swift test $(SWIFT_TEST_FLAGS)

clean:
	@rm -rf bin .build
	@$(MAKE) -C plugins/math_plugin clean
	@echo "==> Clean complete."

.PHONY: all setup plugins build bundle install run clean test
