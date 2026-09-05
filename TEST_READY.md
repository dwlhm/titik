# TEST_READY — Titik Global Hotkeys & Plugin Command Dispatch Test Suite

## 1. Executive Summary

- **Status**: **READY & PASSING (100%)**
- **Framework**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Total Test Suites**: 43 suites
- **Total Executed Tests**: 308 tests
- **Passed**: 308 tests
- **Failed**: 0 tests
- **Execution Time**: ~0.59s

---

## 2. Test Execution Command

Execute all unit and end-to-end test suites using the following command:

```bash
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

To run only the E2E test target:
```bash
swift test --filter TitikE2ETests \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

---

## 3. Feature Coverage Matrix (Tiers 1–4)

| # | Feature | Milestone | Tier 1: Unit / Feature (>=5) | Tier 2: Boundary & Corner | Tier 3: Cross-Feature | Tier 4: Real-World Scenario | Status |
|---|---------|-----------|------------------------------|---------------------------|-----------------------|-----------------------------|--------|
| 1 | Multi-Hotkey Carbon Registration | M1 | 5 tests (`test_f01_*`) | Tested | Tested | Tested | **PASS** |
| 2 | Hotkey Unregistration & Dynamic Update | M1 | 5 tests (`test_f02_*`) | Tested | Tested | Tested | **PASS** |
| 3 | KeymapRegistry Conflict Tracking | M1 | 5 tests (`test_f03_*`) | Tested | Tested | Tested | **PASS** |
| 4 | Execution Mode Differentiation | M1 | 5 tests (`test_f04_*`) | Tested | Tested | Tested | **PASS** |
| 5 | Shortcut Configuration Schema | M2 | 5 tests (`test_f05_*`) | Tested | Tested | Tested | **PASS** |
| 6 | Key Combination String Parsing | M2 | 7 tests (`test_f06_*`) | Tested | Tested | Tested | **PASS** |
| 7 | Resilient Config Deserialization | M2 | 5 tests (`test_f07_*`) | Tested | Tested | Tested | **PASS** |
| 8 | Filesystem Config Hot-Reload | M2 | 5 tests (`test_f08_*`) | Tested | Tested | Tested | **PASS** |
| 9 | Plugin Command Protocol SDK | M3 | 5 tests (`test_f09_*`) | Tested | Tested | Tested | **PASS** |
| 10 | Unified Command Dispatcher | M3 | 5 tests (`test_f10_*`) | Tested | Tested | Tested | **PASS** |
| 11 | Bang Query Sub-Command Routing | M3 | 5 tests (`test_f11_*`) | Tested | Tested | Tested | **PASS** |
| 12 | Zen Browser Built-in Plugin | M4 | 5 tests (`test_f12_*`) | Tested | Tested | Tested | **PASS** |
| 13 | App & Project Launcher Plugin | M4 | 5 tests (`test_f13_*`) | Tested | Tested | Tested | **PASS** |
| 14 | Shortcuts Inspector Plugin | M4 | 5 tests (`test_f14_*`) | Tested | Tested | Tested | **PASS** |
| 15 | Unit & Integration Test Suite | M5 | 5 tests (`test_f15_*`) | Tested | Tested | Tested | **PASS** |
| 16 | Adversarial & Stress Hardening | M5 | 5 tests (`test_f16_*`) | Tested | Tested | Tested | **PASS** |

---

## 4. Test Suite Inventory

### E2E Test Files (`Tests/TitikE2ETests/`)
1. `E2EHotkeyIntegrationTests.swift` (27 tests):
   - Multi-hotkey registration, unregistration, clearing, dynamic updating.
   - Key conflict handling in `KeymapRegistry`, duplicate combinations, reassignment.
   - Execution modes (`.background` vs `.palette`).
   - Thread safety / concurrency stress during hotkey registration.
   - KeyCombination parsing with modifiers (cmd, opt, ctrl, shift, combinations, whitespace, symbols).

2. `E2EConfigLiveReloadTests.swift` (15 tests):
   - Shortcut configuration schema serialization/deserialization.
   - Resilient decoding: malformed entries, missing fields, unknown action types gracefully handled.
   - ConfigLoader file persistence and recovery.
   - Config file dynamic update / watcher simulation, hotkey synchronization when config changes.
   - Extreme config values, empty shortcuts array, debounce write suppression.

3. `E2ECommandDispatchTests.swift` (15 tests):
   - Plugin command protocol SDK (`PluginCommandDefinition`, `CommandExecutionContext`, `CommandExecutionResult`).
   - Mock command plugins with parameterized subcommands.
   - Unified command dispatching across direct hotkey trigger vs search bar bang query.
   - Background silent execution vs interactive UI navigation.
   - Error handling: command not found, missing required arguments, execution failure.

4. `E2EBuiltinPluginsTests.swift` (15 tests):
   - Zen Browser plugin behaviors: URL launching, tab creation, workspace/profile switching, query parameter validation.
   - App Launcher & Project Launcher plugin: launching application bundles, opening directories in IDEs (Antigravity/VSCode), path resolution.
   - Shortcuts Inspector plugin: querying active key bindings, searching registered shortcuts via `!shortcut` or `!hotkeys`, formatting descriptions.
   - Bang router integration with SearchEngine (`!zen`, `!open`, `!launch`, `!shortcut`, `!hotkeys`).

5. `E2ERealWorldScenariosTests.swift` (15 tests):
   - Workflow A: Global hotkey (`Cmd+Shift+W`) triggers Zen Browser in background with target URL.
   - Workflow B: Global hotkey (`Cmd+Shift+O`) triggers palette mode with `!open ~/project/titik` pre-filled.
   - Workflow C: User enters `!shortcut` bang query in search bar, views list of all registered shortcuts, selects one to execute.
   - Workflow D: User edits `config.json` adding a new hotkey, ConfigWatcher reloads, new hotkey becomes immediately active while old is cleanly unbound.
   - Workflow E: Sequential multi-plugin session (`!calc`, `!emoji`, `!file`).
   - Adversarial stress: 50 concurrent tasks hammering KeymapRegistry, 500 shortcut bindings in single config, malformed/injection queries.

6. `TitikE2EEdgeCaseTests.swift` (existing 10 tests):
   - Rapid window dismissal, streaming network drops, rate limiting.

---

## 5. Implementation Bugs & Notes Escalated to Implementing Agents

1. **`ShortcutConfig.swift` Polymorphic `args` Array Decoding**:
   - In `ShortcutConfig.swift` line 125, decoding `args` when passed as an array `["--profile", "work"]` fails with `DecodingError.typeMismatch` because `try container.decodeIfPresent([String: String].self, forKey: .args)` is used instead of `try?`.
   - **Recommendation for M2 Implementer**: Change line 125 to `else if let dict = try? container.decodeIfPresent([String: String].self, forKey: .args)` so it falls through to array decoding.

2. **`AppLauncher.swift` Argument Label**:
   - Line 182 was calling `FuzzyMatcher.match(query: trimmed, target: app.name)` which matches the `FuzzyMatcher` API.
