# Contributing to Titik

Thank you for your interest in contributing to **Titik**! We welcome bug reports, documentation updates, feature contributions, and plugin ecosystem improvements.

---

## 1. Development Environment Setup

### System Requirements

- **Operating System**: macOS 13.0 (Ventura) or later
- **Swift Toolchain**: Swift 6.0+ (bundled with Xcode 16+ or Command Line Tools)
- **Build Tools**: `make`, `clang`, `git`

### Clone & Build

```bash
# Clone the repository
git clone https://github.com/dwlhm/titik.git
cd titik

# Set up configuration directories and build default plugins
make setup
make plugins

# Build Swift debug binary
swift build
```

---

## 2. Running Tests & Verifications

Titik contains a comprehensive suite of unit and integration tests covering parser mechanics, fuzzy matching, dynamic plugin loading, and path resolution.

```bash
# Run the test suite via Makefile
make test

# Or run tests using SwiftPM directly
swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

Ensure all tests pass cleanly before submitting any changes.

---

## 3. Packaging Application Bundle

To package Titik as a native `.app` bundle:

```bash
make bundle
```

This runs `scripts/build_bundle.sh`, creating `bin/Titik.app` with embedded metadata (`Info.plist`), dynamic plugins, and default configurations.

To test the bundle locally:

```bash
open bin/Titik.app
```

---

## 4. Conventional Commits

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for commit messages:

- `feat: <description>` — New features or capabilities
- `fix: <description>` — Bug fixes
- `docs: <description>` — Documentation updates
- `test: <description>` — Adding or updating test cases
- `refactor: <description>` — Code refactoring with no behavior changes
- `perf: <description>` — Performance optimizations
- `chore: <description>` — Build system or tooling maintenance

Example:
```bash
git commit -m "feat(parser): add support for exponentiation operator in math evaluator"
```

---

## 5. Pull Request Workflow

1. Fork the repository and create a descriptive branch:
   ```bash
   git checkout -b feat/my-new-feature
   ```
2. Implement your changes following project code style and Swift 6 concurrency rules.
3. Write test cases covering new behavior or regressions in `Tests/TitikTests/`.
4. Run `make test` to verify everything passes.
5. Push your branch to GitHub and submit a Pull Request targeting the `main` branch.
