# Titik E2E Test Infrastructure & 4-Tier Test Specification

## 1. Overview & Architecture

This document defines the comprehensive end-to-end testing infrastructure and test suite specification for **Titik: Global Keyboard Shortcuts and Plugin Command Dispatching System**.

The test infrastructure is designed following a **4-Tier Verification Methodology**, providing exhaustive coverage from granular feature validation up to complete, real-world user workflows and adversarial stress testing.

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Tier 4: Real-World Scenarios                      │
│   (Zen Browser Launch, IDE Project Opening, Shortcuts Inspector UX)   │
├────────────────────────────────────────────────────────────────────────┤
│                   Tier 3: Cross-Feature Combinations                   │
│ (Hotkey + Background Exec, Hotkey + Palette Pre-fill, Hot-Reload Sync) │
├────────────────────────────────────────────────────────────────────────┤
│                   Tier 2: Boundary & Corner Cases                      │
│    (Malformed JSON, Duplicate Combos, Unregistered Keys, Race Conds)   │
├────────────────────────────────────────────────────────────────────────┤
│                       Tier 1: Feature Coverage                         │
│       (>= 5 isolated test cases per feature across all 16 features)     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Test Execution Environment & Runner

### Test Framework
All tests are implemented using **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), providing native Swift concurrency safety, structured test hierarchies, parameterized execution, and clear diagnostic failure reporting.

### Deterministic Test Execution Invariant
Every test case in the suite is:
1. **Self-Contained**: Creates isolated in-memory or ephemeral temporary directory state (`UUID().uuidString`).
2. **Order-Independent**: No shared mutable global state leaks between test runs (`defer { cleanup() }`).
3. **Deterministic**: No arbitrary sleeps without deterministic synchronization barriers (`AsyncStream`, `DispatchSemaphore`, or `Actor` state polling).

### Test Runner Command
```bash
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

---

## 3. Tier 1: Feature Coverage (>= 5 Tests Per Feature)

The Feature Inventory from `PROJECT.md` defines 16 core features. Each feature is tested with at least 5 distinct test cases:

### Feature 1: Multi-Hotkey Carbon Registration
- `test_f01_singleHotkeyRegistrationSuccess`: Register single hotkey with signature and verify active state.
- `test_f01_multipleDistinctHotkeysRegistration`: Register 5 distinct hotkey combinations (`Cmd+K`, `Opt+Space`, `Ctrl+Shift+T`, `Cmd+Alt+P`, `Cmd+.`) and verify distinct identity.
- `test_f01_hotkeyHandlerInvocationOnEvent`: Verify callback invocation when simulated Carbon event arrives.
- `test_f01_hotkeyRegistrationQuery`: Verify `isRegistered(identifier:)` returns true for registered keys and false for unregistered.
- `test_f01_activeRegistrationsListMatchesCount`: Verify `activeRegistrations` reflects exact count and combinations of active keys.

### Feature 2: Hotkey Unregistration & Dynamic Update
- `test_f02_unregistrationByIdentifier`: Unregister specific hotkey by identifier and verify it no longer triggers.
- `test_f02_unregisterAllClearsEntireState`: Unregister all hotkeys and verify active count reaches zero.
- `test_f02_dynamicUpdateKeyRebinding`: Update existing hotkey modifier/key and verify new combo triggers handler while old does not.
- `test_f02_unregisteredKeyIgnoredGracefully`: Triggering unregistration for non-existent key ID completes without error or crash.
- `test_f02_reRegistrationAfterUnregistration`: Unregister a key and re-register it with a new handler; verify new handler executes.

### Feature 3: KeymapRegistry Conflict Tracking
- `test_f03_duplicateCombinationThrowsConflict`: Registering same combination for different identifier throws `duplicateBinding`.
- `test_f03_reRegisterSameIdentifierUpdatesCombo`: Re-registering existing identifier with new combination updates registry cleanly without conflict error.
- `test_f03_conflictErrorDescriptionFormatting`: Verify `KeymapError.duplicateBinding` produces actionable description text.
- `test_f03_threadSafeConcurrentRegistrations`: Concurrent registrations across 20 background tasks maintain registry consistency.
- `test_f03_registryFindAndLookup`: Lookup binding by combination returns correct identifier and action closure.

### Feature 4: Execution Mode Differentiation
- `test_f04_backgroundModeDoesNotActivateUI`: Triggering `.background` shortcut dispatches silently without touching window visibility.
- `test_f04_paletteModeActivatesWindowAndQuery`: Triggering `.palette` shortcut calls `showWindow()` and sets `UIOrchestrator.query`.
- `test_f04_modeCodableRoundTrip`: Verify `ShortcutExecutionMode` serializes to `"background"` and `"palette"`.
- `test_f04_defaultModeFallbackInPluginSDK`: Verify command plugins inherit `.background` or `.palette` as configured in definition.
- `test_f04_modePreservationAcrossDispatcher`: Dispatcher preserves requested execution mode in `CommandExecutionContext`.

### Feature 5: Shortcut Configuration Schema
- `test_f05_shortcutConfigJSONSerialization`: Serialize `ShortcutConfig` to JSON and deserialize back to identical struct.
- `test_f05_shortcutActionTypeEnumeration`: Verify all action types (`pluginCommand`, `appLaunch`, `quickLink`, `rawQuery`, `toggleWindow`) decode cleanly.
- `test_f05_shortcutActionArgumentsMap`: Verify key-value string arguments dictionary decodes with parameters.
- `test_f05_optionalFieldsDefaulting`: Config with missing optional `name` or `arguments` decodes with `nil` defaults.
- `test_f05_shortcutsArrayInRootConfig`: Full `Config` struct contains `shortcuts: [ShortcutConfig]` and integrates with root JSON schema.

### Feature 6: Key Combination String Parsing
- `test_f06_standardModifierPlusKey`: Parse `"cmd+shift+k"` into modifiers `[.command, .shift]` and key `.k`.
- `test_f06_whitespaceSeparatedKeys`: Parse `"cmd space"` and `"opt return"` into valid `KeyCombination`.
- `test_f06_aliasModifierNames`: Parse `"alt"`, `"ctrl"`, `"option"`, `"control"` into corresponding canonical modifiers.
- `test_f06_specialSymbolKeys`: Parse punctuation keys like `"cmd+."`, `"ctrl+,"`, `"cmd+/"`, `"opt+["`.
- `test_f06_displayGlyphGeneration`: Verify `KeyCombination.description` produces correct macOS glyphs (`⌘⇧K`, `⌥␣`).

### Feature 7: Resilient Config Deserialization
- `test_f07_emptyConfigDefaultsGracefully`: Decoding empty JSON `{}` yields all default values without throwing.
- `test_f07_partialMalformedShortcutSkipped`: List of shortcuts containing one invalid entry decodes valid entries and discards corrupted one.
- `test_f07_unknownActionTypeFallback`: Unknown action type string (e.g. `"futureAction"`) does not crash decoder.
- `test_f07_typeMismatchInWindowBounds`: String supplied where number expected falls back to default window width/height.
- `test_f07_corruptedConfigLoadsDefaultFallback`: `ConfigLoader.load` on non-JSON file returns valid default `Config`.

### Feature 8: Filesystem Config Hot-Reload
- `test_f08_configWatcherDetectsFileModification`: Modifying watched file invokes `onChange` callback with updated struct.
- `test_f08_configWatcherDebouncesRapidWrites`: 10 rapid file writes within 50ms trigger debounced single reload.
- `test_f08_configWatcherStopWatching`: Calling `stopWatching()` closes file descriptor and prevents further callbacks.
- `test_f08_hotReloadUpdatesKeymapRegistry`: Changing hotkey in config triggers unregistration of old key and registration of new key.
- `test_f08_invalidJSONOnDiskPreservesLastKnownGood`: Saving syntax error JSON to disk logs warning and retains active configuration.

### Feature 9: Plugin Command Protocol SDK
- `test_f09_commandDefinitionStructure`: Create `PluginCommandDefinition` with triggers, arguments, and default mode.
- `test_f09_argumentRequiredAndDefaultFlags`: Verify `PluginCommandArgument` validation for required vs optional parameters.
- `test_f09_executionContextPayload`: Construct `CommandExecutionContext` with trigger, mode, and rawInput string.
- `test_f09_commandExecutionResultOutput`: Return `CommandExecutionResult` with `isSuccess`, message, and key-value payload.
- `test_f09_commandPluginProtocolConformance`: Mock plugin conforming to `TitikCommandPlugin` lists executable commands.

### Feature 10: Unified Command Dispatcher
- `test_f10_directDispatchFromHotkeyPayload`: Dispatching action from hotkey payload executes target plugin command with arguments.
- `test_f10_dispatchAppLaunchTarget`: Dispatching `appLaunch` action calls application launcher with bundle identifier.
- `test_f10_dispatchQuickLinkTarget`: Dispatching `quickLink` action formats and opens URL in browser.
- `test_f10_dispatchNonExistentCommandFailsGracefully`: Dispatching unknown command returns failure result with descriptive error.
- `test_f10_dispatchExecutionTimeoutProtection`: Long-running command exceeding timeout aborts safely without locking dispatcher.

### Feature 11: Bang Query Sub-Command Routing
- `test_f11_bangQueryIdentifiesPlugin`: Search query `"!zen https://apple.com"` resolves to Zen plugin with URL argument.
- `test_f11_bangQueryWithSubcommand`: Search query `"!open project ~/dev/titik"` routes to `open` command with project path.
- `test_f11_bangPrefixSuggestionGeneration`: Typing `"!z"` suggests `"!zen "` and shows command description.
- `test_f11_bangWithoutArgumentsListsSubcommands`: Typing `"!zen"` displays all available Zen subcommands (new tab, new window, profiles).
- `test_f11_escapedOrMalformedBangHandling`: Queries with multiple bangs (`"!!test"`) or invalid characters do not crash router.

### Feature 12: Zen Browser Built-in Plugin
- `test_f12_openURLCommandBuildsArguments`: Executing `open-url` with URL argument formats correct browser launch parameters.
- `test_f12_newTabCommandExecution`: Executing `new-tab` command generates new tab trigger.
- `test_f12_profileWorkspaceSelection`: Executing `open-profile` with `-profile Work` passes profile flag to Zen binary.
- `test_f12_zenPluginManifestMetadata`: Verify plugin ID (`titik.builtin.zen`), bang trigger (`!zen`), and version.
- `test_f12_invalidURLHandlingInZenPlugin`: Passing empty or malformed URL string returns validation error message.

### Feature 13: App & Project Launcher Plugin
- `test_f13_launchApplicationByName`: Executing `launch-app` with `"Safari"` resolves application URL.
- `test_f13_openProjectDirectoryInIDE`: Executing `open-project` with path and IDE `"Antigravity"` resolves project directory.
- `test_f13_tildePathExpansionInLauncher`: Paths starting with `~/` expand to user home directory correctly.
- `test_f13_nonExistentAppReturnsActionableError`: Launching non-existent app bundle name returns failure result.
- `test_f13_launcherPluginManifestMetadata`: Verify plugin ID (`titik.builtin.launcher`) and triggers (`!open`, `!launch`).

### Feature 14: Shortcuts Inspector Plugin
- `test_f14_listAllActiveKeyBindings`: Executing `!shortcut` queries `KeymapRegistry` and returns items for all active hotkeys.
- `test_f14_searchShortcutsByKeyword`: Subquery `"!shortcut zen"` filters list to only hotkeys bound to Zen browser.
- `test_f14_displayFormattedGlyphAndAction`: Items contain formatted hotkey glyphs (e.g. `⌘⇧Z`) and destination action description.
- `test_f14_triggerSelectedShortcutFromUI`: Selecting a shortcut search item triggers its bound action directly.
- `test_f14_shortcutsPluginManifestMetadata`: Verify plugin ID (`titik.builtin.shortcuts`) and triggers (`!shortcut`, `!hotkeys`).

### Feature 15: Unit & Integration Test Suite
- `test_f15_allModuleSuitesPassSynchronously`: All modular test targets execute and pass without flakiness.
- `test_f15_mockEnvironmentIsolation`: Mock filesystem and mock event dispatchers run without accessing production files.
- `test_f15_asyncTaskCancellationHygiene`: Asynchronous test tasks cancel cleanly upon suite teardown.
- `test_f15_memoryLeakFreeTestExecution`: Instantiating and releasing managers leaves zero lingering references.
- `test_f15_testRunnerExitCodes`: Test suite exits with return code 0 on complete pass.

### Feature 16: Adversarial & Stress Hardening
- `test_f16_rapidConcurrentHotkeyRegistrations`: 50 concurrent tasks registering and unregistering hotkeys maintain data integrity.
- `test_f16_extremeConfigPayloadSizes`: Config file with 1,000 shortcut entries decodes and indexes in under 100ms.
- `test_f16_specialCharacterAndEmojiHotkeyStrings`: Key combo parser handles unicode, control characters, and malformed delimiters.
- `test_f16_unclosedQuotesAndEscapeSequencesInBangQuery`: Bang parser withstands injection attempts (`!zen "unclosed string`, `!open \x00\n`).
- `test_f16_reentrantEventDispatching`: Firing hotkey while previous hotkey handler is still executing does not deadlock.

---

## 4. Tier 2: Boundary & Corner Cases

| Scenario | Boundary Condition | Expected Behavior |
|----------|-------------------|-------------------|
| **Empty Strings** | Key combo `""`, command `""`, query `""` | Return `nil` / `.empty` AST, zero crash |
| **Duplicate Modifiers** | `"cmd+cmd+k"`, `"shift+shift+space"` | Deduplicate modifiers into single flag |
| **Unknown Modifiers** | `"hyper+super+k"` | Discard unknown tokens, parse known elements |
| **Malformed Keycodes** | `"cmd+UNKNOWN_KEY_123"` | Return `nil` gracefully, log warning |
| **Duplicate Hotkeys** | Registering same key for 2 IDs | First registration holds; second throws `duplicateBinding` |
| **Unregistered Key Lookup** | Querying non-existent key | Returns `nil` / `false` without exception |
| **Malformed Config JSON** | `{ "shortcuts": "not_an_array" }` | Resilient decoder falls back to empty array |
| **Corrupted Config File** | Truncated byte stream on disk | Loader logs warning and provides default `Config` |
| **Unregistered Bang Command** | `"!unknown_plugin_xyz foo"` | Fallback to universal application/system search |
| **Concurrent Hotkey Fires** | 100 simultaneous simulated events | Main thread serialized execution, zero data race |

---

## 5. Tier 3: Cross-Feature Combinations

1. **Hotkey + Background Silent Dispatch**:
   - User presses `Cmd+Shift+Z` mapped to Zen Browser `open-url https://news.ycombinator.com`.
   - `HotkeyManager` receives event, looks up `RegisteredHotkey`.
   - Detects `mode == .background`.
   - `PluginCommandDispatcher` executes `ZenBrowserPlugin.executeCommand`.
   - Main Titik HUD window remains completely hidden throughout execution.

2. **Hotkey + Palette Pre-fill Dispatch**:
   - User presses `Cmd+Shift+O` mapped to `!open ~/project/titik`.
   - `HotkeyManager` receives event, detects `mode == .palette`.
   - Invokes `WindowController.showWindow()`.
   - Sets `UIOrchestrator.query = "!open ~/project/titik"`.
   - `SearchEngine` immediately executes bang routing and renders project options.

3. **Config Hot-Reload + Dynamic Re-registration**:
   - Initial config has `Cmd+K` bound to `toggleWindow`.
   - User edits `config.json` changing key to `Cmd+Shift+K` and adding `Opt+Space` for `!zen`.
   - `ConfigWatcher` detects file modification event on background queue.
   - Debounced reload parses new `Config`.
   - `KeymapRegistry` automatically unregisters `Cmd+K` and registers `Cmd+Shift+K` and `Opt+Space`.
   - Pressing `Cmd+Shift+K` now toggles window; pressing old `Cmd+K` is inert.

4. **Search Bar Bang Query + Contextual Subcommand Execution**:
   - User types `!shortcut` in search bar.
   - `SearchEngine` routes to `ShortcutsPlugin`.
   - Search result list populates with all active hotkeys.
   - User presses Enter on `⌘⇧Z (Zen Browser: Open URL)`.
   - Contextual action executes the selected shortcut command directly.

---

## 6. Tier 4: Real-World Application Scenarios

### Scenario A: Zen Browser Workspaces & URL Navigation
```
User Action: Press Global Hotkey (Cmd+Shift+W)
  ├── HotkeyManager resolves ID -> Action: PluginCommand(titik.builtin.zen, open-profile, args: [profile: "Work", url: "https://github.com"])
  ├── Mode: background
  ├── PluginCommandDispatcher dispatches to ZenBrowserPlugin
  ├── ZenBrowserPlugin builds arguments: ["-P", "Work", "-new-tab", "https://github.com"]
  └── Execution succeeds with CommandExecutionResult(isSuccess: true, message: "Opened URL in Zen Browser (Profile: Work)")
```

### Scenario B: Antigravity IDE & Project Launcher
```
User Action: Bang Query in Palette Search Bar "!open titik"
  ├── SearchEngine parses AST -> Command(name: "open", args: ["titik"])
  ├── LauncherPlugin searches local project directories matching "titik"
  ├── Resolves absolute path: /Users/dwlhm/project/titik
  ├── User selects item with secondary action: "Open in Antigravity"
  ├── LauncherPlugin initiates application launch: Antigravity.app with target path
  └── Palette window dismisses automatically on launch
```

### Scenario C: Interactive Shortcuts Inspector & Conflict Remediation
```
User Action: Bang Query "!hotkeys"
  ├── SearchEngine resolves ShortcutsPlugin
  ├── Queries KeymapRegistry.shared.allBindings()
  ├── Renders rich list displaying glyphs, triggers, target commands, and execution modes
  ├── User filters by "!hotkeys cmd" -> instantly filters to ⌘-prefixed hotkeys
  └── User verifies zero conflicting registrations exist across system
```

---

## 7. Test Suite File Structure

The test suite is organized into modular files inside `Tests/TitikE2ETests/`:

```
Tests/TitikE2ETests/
├── E2EHotkeyIntegrationTests.swift     # Tiers 1 & 2: Multi-hotkey, registry, conflict, mode tests
├── E2EConfigLiveReloadTests.swift      # Tiers 1, 2, 3: Schema, resilient decoding, live watcher sync
├── E2ECommandDispatchTests.swift       # Tiers 1, 2, 3: Command protocol, execution context, dispatcher
├── E2EBuiltinPluginsTests.swift        # Tiers 1, 2, 4: Zen browser, launcher, shortcuts inspector
├── E2ERealWorldScenariosTests.swift    # Tier 4: End-to-end user lifecycles & Tier 5 adversarial stress
└── TitikE2EEdgeCaseTests.swift         # Existing edge case suite
```

---

## 8. Verification & Gate Criteria

The test infrastructure is considered **READY** and fully validated when:
1. All test files compile with zero compiler errors under Swift 6 strict concurrency.
2. `swift test` executes all test suites across all 4 tiers with 100% pass rate.
3. Every feature in the 16-feature inventory has >= 5 passing test cases.
4. Edge cases, boundary violations, cross-feature integrations, and real-world workflows are fully exercised.
