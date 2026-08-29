#ifndef TITIK_PLUGIN_API_H
#define TITIK_PLUGIN_API_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TITIK_PLUGIN_API_VERSION 1
#define TITIK_PLUGIN_MAX_RESULTS 16
#define TITIK_ITEM_ID_MAX 64
#define TITIK_ITEM_TITLE_MAX 128
#define TITIK_ITEM_SUBTITLE_MAX 256
#define TITIK_ITEM_CATEGORY_MAX 64
#define TITIK_ITEM_PAYLOAD_MAX 256

/**
 * TitikPluginItem represents a single searchable or executable result
 * returned by a plugin in response to a user query.
 */
typedef struct TitikPluginItem {
    char id[TITIK_ITEM_ID_MAX];                 /* Unique item identifier within plugin */
    char title[TITIK_ITEM_TITLE_MAX];           /* Primary display title */
    char subtitle[TITIK_ITEM_SUBTITLE_MAX];     /* Secondary description/details */
    char category[TITIK_ITEM_CATEGORY_MAX];     /* Category name (e.g. "Calculator", "Plugin") */
    char action_payload[TITIK_ITEM_PAYLOAD_MAX]; /* Data passed to plugin execute() proc */
    int32_t score_boost;                        /* Ranking priority boost (0-1000) */
} TitikPluginItem;

/**
 * Function pointer signatures for Titik plugin lifecycle and operations.
 */

/* Initializes the plugin. Returns 0 on success, non-zero on failure. */
typedef int (*TitikPluginInitFn)(void);

/*
 * Queries the plugin with user input.
 * - query_str: The current search query string from Titik.
 * - out_items: Array of TitikPluginItem buffers provided by host.
 * - max_items: Maximum number of items out_items can hold.
 * Returns: Number of valid items written into out_items (0 to max_items).
 */
typedef int (*TitikPluginQueryFn)(const char *query_str, TitikPluginItem *out_items, int max_items);

/*
 * Executes the primary action for a selected item.
 * - item_id: The id of the item being executed.
 * - action_payload: The action payload associated with the item.
 * Returns: 0 on success, non-zero on failure.
 */
typedef int (*TitikPluginExecuteFn)(const char *item_id, const char *action_payload);

/* Called when the plugin is being unloaded or host is shutting down. */
typedef void (*TitikPluginShutdownFn)(void);

/**
 * TitikPlugin defines the plugin metadata and lifecycle interface.
 */
typedef struct TitikPlugin {
    const char *id;             /* Unique plugin reverse-DNS ID (e.g. "titik.plugin.math") */
    const char *name;           /* Human-readable plugin name */
    const char *version;        /* Semantic version string (e.g. "1.0.0") */
    const char *description;    /* Short description of plugin capabilities */
    const char *short_bang;     /* Short-bang trigger defined by plugin (e.g. "!calc" or "!m") */

    TitikPluginInitFn init;         /* Plugin initialization proc */
    TitikPluginQueryFn query;       /* Query handler proc */
    TitikPluginExecuteFn execute;   /* Action execution proc */
    TitikPluginShutdownFn shutdown; /* Cleanup proc */
} TitikPlugin;

/**
 * Standard exported entrypoint function symbol expected by Titik plugin host.
 * Plugins must export a function named "titik_plugin_entry" returning a pointer
 * to a statically allocated or persistent TitikPlugin struct.
 */
typedef const TitikPlugin *(*TitikPluginEntryFn)(void);

#define TITIK_PLUGIN_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
}
#endif

#endif /* TITIK_PLUGIN_API_H */
