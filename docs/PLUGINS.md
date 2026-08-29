# Titik Plugin Development Guide

Titik features a high-performance, zero-overhead dynamic plugin architecture built around a standard C ABI (`plugin_api.h`). Plugins can be written in any language that compiles to a native C ABI dynamic library (`.dylib`), including **C**, **C++**, **Rust**, and **Swift**.

---

## 1. Plugin API Overview

The C interface is declared in `Sources/TitikPlugins/include/plugin_api.h`.

### Key Data Structures

```c
typedef struct TitikPluginItem {
    char id[64];                 /* Unique item identifier within plugin */
    char title[128];             /* Primary title */
    char subtitle[256];          /* Secondary description */
    char category[64];           /* Category tag */
    char action_payload[256];    /* Payload forwarded to execute() */
    int32_t score_boost;         /* Ranking score boost (0-1000) */
} TitikPluginItem;

typedef struct TitikPlugin {
    const char *id;              /* Reverse-DNS identifier (e.g. "titik.plugin.custom") */
    const char *name;            /* Display name */
    const char *version;         /* SemVer string (e.g. "1.0.0") */
    const char *description;     /* Plugin description */
    const char *short_bang;      /* Bang trigger prefix (e.g. "!calc") */

    int (*init)(void);
    int (*query)(const char *query_str, TitikPluginItem *out_items, int max_items);
    int (*execute)(const char *item_id, const char *action_payload);
    void (*shutdown)(void);
} TitikPlugin;
```

---

## 2. Lifecycle Functions

1. **`init()`**:
   - Called immediately when Titik loads the `.dylib`.
   - Used for allocating state, caches, or network clients.
   - Return `0` on success, or non-zero on initialization error.

2. **`query(const char *query_str, TitikPluginItem *out_items, int max_items)`**:
   - Called on keystrokes when the query matches the plugin's `short_bang` or general search.
   - Host provides pre-allocated buffer `out_items` holding up to `max_items` elements.
   - Populate `out_items` and return the number of items written (0 to `max_items`).

3. **`execute(const char *item_id, const char *action_payload)`**:
   - Called when user selects an item from the plugin and presses `Return`.
   - Perform desired actions (open URL, run shell command, copy payload to clipboard).
   - Return `0` on success.

4. **`shutdown()`**:
   - Called prior to `dlclose()` when Titik unloads the plugin or shuts down.
   - Free memory, close file descriptors, and cleanup threads.

---

## 3. Example Plugin in C

Create `hello_plugin.c`:

```c
#include <stdio.h>
#include <string.h>
#include "plugin_api.h"

static int hello_init(void) {
    return 0;
}

static int hello_query(const char *query_str, TitikPluginItem *out_items, int max_items) {
    if (max_items <= 0) return 0;

    strncpy(out_items[0].id, "hello_item", sizeof(out_items[0].id) - 1);
    snprintf(out_items[0].title, sizeof(out_items[0].title), "Hello, %s!", query_str[0] ? query_str : "World");
    strncpy(out_items[0].subtitle, "Custom Titik C Plugin Example", sizeof(out_items[0].subtitle) - 1);
    strncpy(out_items[0].category, "Plugin", sizeof(out_items[0].category) - 1);
    strncpy(out_items[0].action_payload, query_str, sizeof(out_items[0].action_payload) - 1);
    out_items[0].score_boost = 100;

    return 1;
}

static int hello_execute(const char *item_id, const char *action_payload) {
    printf("Executed plugin action: %s -> %s\n", item_id, action_payload);
    return 0;
}

static void hello_shutdown(void) {
    // Cleanup resources
}

static TitikPlugin g_plugin = {
    .id = "titik.plugin.hello",
    .name = "Hello World Plugin",
    .version = "1.0.0",
    .description = "A sample Titik C dynamic plugin",
    .short_bang = "!hello",
    .init = hello_init,
    .query = hello_query,
    .execute = hello_execute,
    .shutdown = hello_shutdown
};

TITIK_PLUGIN_EXPORT const TitikPlugin *titik_plugin_entry(void) {
    return &g_plugin;
}
```

### Compiling with Clang

```bash
clang -dynamiclib -O3 -Wall -Wextra \
  -I/path/to/titik/Sources/TitikPlugins/include \
  -o hello.dylib hello_plugin.c
```

---

## 4. Example Plugin in Rust

In `Cargo.toml`:

```toml
[package]
name = "titik_rust_plugin"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
```

In `src/lib.rs`:

```rust
use std::os::raw::{c_char, c_int};
use std::ffi::{CStr, CString};

#[repr(C)]
pub struct TitikPluginItem {
    pub id: [c_char; 64],
    pub title: [c_char; 128],
    pub subtitle: [c_char; 256],
    pub category: [c_char; 64],
    pub action_payload: [c_char; 256],
    pub score_boost: i32,
}

#[repr(C)]
pub struct TitikPlugin {
    pub id: *const c_char,
    pub name: *const c_char,
    pub version: *const c_char,
    pub description: *const c_char,
    pub short_bang: *const c_char,
    pub init: unsafe extern "C" fn() -> c_int,
    pub query: unsafe extern "C" fn(*const c_char, *mut TitikPluginItem, c_int) -> c_int,
    pub execute: unsafe extern "C" fn(*const c_char, *const c_char) -> c_int,
    pub shutdown: unsafe extern "C" fn(),
}

unsafe extern "C" fn plugin_init() -> c_int { 0 }
unsafe extern "C" fn plugin_shutdown() {}

unsafe extern "C" fn plugin_query(
    _query_str: *const c_char,
    _out_items: *mut TitikPluginItem,
    _max_items: c_int,
) -> c_int {
    0
}

unsafe extern "C" fn plugin_execute(_item_id: *const c_char, _action_payload: *const c_char) -> c_int {
    0
}

static PLUGIN_DEF: TitikPlugin = TitikPlugin {
    id: b"titik.plugin.rust\0".as_ptr() as *const c_char,
    name: b"Rust Plugin\0".as_ptr() as *const c_char,
    version: b"1.0.0\0".as_ptr() as *const c_char,
    description: b"High performance Rust plugin\0".as_ptr() as *const c_char,
    short_bang: b"!rs\0".as_ptr() as *const c_char,
    init: plugin_init,
    query: plugin_query,
    execute: plugin_execute,
    shutdown: plugin_shutdown,
};

#[no_mangle]
pub extern "C" fn titik_plugin_entry() -> *const TitikPlugin {
    &PLUGIN_DEF
}
```

### Compiling with Cargo

```bash
cargo build --release
cp target/release/libtitik_rust_plugin.dylib ~/.config/titik/plugins/rust_plugin.dylib
```

---

## 5. Deployment and Installation

To install a plugin:

1. Copy the compiled `.dylib` into the user plugin directory:
   ```bash
   cp my_plugin.dylib ~/.config/titik/plugins/
   ```
2. Restart or summon Titik. The plugin will be automatically discovered and loaded.
3. Test query triggers using the defined short bang (e.g. `!hello` or `!rs`).
