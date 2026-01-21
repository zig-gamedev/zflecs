const std = @import("std");
const builtin = @import("builtin");

pub const debug_mode = enum { sanitize, debug, depends_on_build, none };
pub const float_point_precision = enum {
    fp32,
    fp64,
    // NOTE: check if supported
    // fp128,
};

pub const FlecsAddons = enum(u5) {
    /// FLECS_ALERTS - Monitor conditions for errors
    alerts,
    /// FLECS_APP - Application addon
    app,

    // NOTE: on by default FLECS_C - C API convenience macros, always enabled
    // NOTE: no FLECS_CPP - C++ API
    // cpp,

    /// FLECS_DOC - Document entities & components
    doc,
    /// FLECS_JOURNAL - Journaling addon (Off by default)
    // journal,
    /// FLECS_JSON - Parsing JSON to/from component values
    json,
    /// FLECS_HTTP - Tiny HTTP server for connecting to remote UI
    http,
    /// FLECS_LOG - When enabled ECS provides more detailed logs
    log,
    /// FLECS_META - Reflection support
    meta,
    /// FLECS_METRICS - Expose component data as statistics
    metrics,
    /// FLECS_MODULE - Module support
    module,
    /// FLECS_OS_API_IMPL - Default implementation for OS API
    os_api_impl,
    /// FLECS_PERF_TRACE - Enable performance tracing (Off by default)
    // perf_trace,
    /// FLECS_PIPELINE - Pipeline support
    pipeline,
    /// FLECS_REST - REST API for querying application data
    rest,
    /// FLECS_PARSER - Utilities for script and query DSL parsers
    parser,
    /// FLECS_QUERY_DSL - Flecs query DSL parser
    query_dsl,
    /// FLECS_SCRIPT - Flecs entity notation language
    script,
    /// FLECS_SCRIPT_MATH - Math functions for flecs script (may require linking with libm)
    /// (Off by default)
    // script_math,
    /// FLECS_SYSTEM - System support
    system,
    /// FLECS_STATS - Track runtime statistics
    stats,
    /// FLECS_TIMER -  Timer support
    timer,
    /// FLECS_UNITS - Builtin standard units
    units,
};

pub const CustomBuildMode = enum { blacklist, whitelist };

pub const CustomBuildSet = std.EnumSet(FlecsAddons);

fn convertFloatPrecisionFlag(alloc: std.mem.Allocator, name: []const u8, value: float_point_precision) []const u8 {
    const val = switch (value) {
        .fp32 => "float",
        .fp64 => "double",
        // NOTE: check if supported
        // .fp128 => "long double",
    };
    return std.fmt.allocPrint(alloc, "-D{s}={s}", .{ name, val }) catch "";
}

fn convertSizeFlag(alloc: std.mem.Allocator, name: []const u8, value: usize) []const u8 {
    return std.fmt.allocPrint(alloc, "-D{s}={d}", .{ name, value }) catch "";
}

const Addons = struct {
    const black_list = CustomBuildSet.init(.{
        .alerts = true,
        .app = true,
        .doc = true,
        .json = true,
        .http = true,
        .log = true,
        .meta = true,
        .metrics = true,
        .module = true,
        .os_api_impl = true,
        .pipeline = true,
        .rest = true,
        .parser = true,
        .query_dsl = true,
        .script = true,
        .system = true,
        .stats = true,
        .timer = true,
        .units = true,
    });

    const white_list = CustomBuildSet.init(.{
        .os_api_impl = true,
    });

    mode: CustomBuildMode,
    addon_set: CustomBuildSet,

    pub fn init(mode: CustomBuildMode) Addons {
        return Addons{
            .mode = mode,
            .addon_set = if (mode == .whitelist) white_list else black_list,
        };
    }

    pub fn toggleAddon(self: *Addons, addon: FlecsAddons, toggle: bool) void {
        if (toggle) {
            switch (self.mode) {
                .blacklist => self.addon_set.remove(addon),
                .whitelist => self.addon_set.insert(addon),
            }
        }
    }
    pub fn includeAddon(self: *Addons, addon: FlecsAddons) bool {
        return self.addon_set.contains(addon);
    }
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = b.addOptions();

    const opt_use_shared = b.option(bool, "shared", "Make shared (default: false)") orelse false;

    const opt_debug_mode = b.option(debug_mode, "debug_mode",
        \\
        \\    - debug: Used for input parameter checking and cheap sanity checks. There are lots of
        \\      asserts in every part of the code, so this will slow down applications.
        \\    - sanitize: Enables expensive checks that can detect issues early. Recommended for
        \\      running tests or when debugging issues. This will severely slow down code.
        \\    - depends_on_build: Enables sanitize on debug mode and none on release.
        \\    - none: No debug checks available.
        \\
        \\    (default: depends_on_build)
    ) orelse .depends_on_build;
    options.addOption(debug_mode, "debug_mode", opt_debug_mode);

    const opt_debug_info = b.option(bool, "debug_info",
        \\
        \\    Adds additional debug information to internal data structures. Necessary when
        \\    using natvis.
    ) orelse false;
    options.addOption(bool, "debug_info", opt_debug_info);

    const opt_float_precision = b.option(float_point_precision, "float_t",
        \\
        \\    Customizable precision for floating point operations (default: fp32)
    ) orelse .fp32;
    options.addOption(float_point_precision, "float_precision", opt_float_precision);

    const opt_scalar_time_precision = b.option(float_point_precision, "ftime_t",
        \\
        \\    Customizable precision for scalar time values. Change to double precision for
        \\    processes that can run for a long time (e.g. longer than a day).
    ) orelse .fp32;
    options.addOption(float_point_precision, "scalar_time_precision", opt_scalar_time_precision);

    const opt_accurate_counters = b.option(bool, "accurate_counters",
        \\
        \\    Define to ensure that global counters used for statistics (such as the
        \\    allocation counters in the OS API) are accurate in multithreaded
        \\    applications, at the cost of increased overhead.
        \\    (default: false)
    ) orelse false;
    options.addOption(bool, "accurate_counters", opt_accurate_counters);

    const opt_disable_counters = b.option(bool, "disable_counters",
        \\
        \\    Disables counters used for statistics. Improves performance, but
        \\    will prevent some features that rely on statistics from working,
        \\    like the statistics pages in the explorer.
    ) orelse false;
    options.addOption(bool, "disable_counters", opt_disable_counters);

    const opt_soft_assert = b.option(bool, "soft_assert",
        \\
        \\    Define to not abort for recoverable errors, like invalid parameters. An error
        \\    is still thrown to the console. This is recommended for when running inside a
        \\    third party runtime, such as the Unreal editor.
        \\
        \\    Note that internal sanity checks (ECS_INTERNAL_ERROR) will still abort a
        \\    process, as this gives more information than a (likely) subsequent crash.
        \\
        \\    When a soft assert occurs, the code will attempt to minimize the number of
        \\    side effects of the failed operation, but this may not always be possible.
        \\    Even though an application may still be able to continue running after a soft
        \\    assert, it should be treated as if in an undefined state.
    ) orelse false;
    options.addOption(bool, "soft_assert", opt_soft_assert);

    const opt_keep_assert = b.option(bool, "keep_assert",
        \\
        \\    By default asserts are disabled in release mode, when either FLECS_NDEBUG or
        \\    NDEBUG is defined. Defining FLECS_KEEP_ASSERT ensures that asserts are not
        \\    disabled. This define can be combined with FLECS_SOFT_ASSERT.
    ) orelse false;
    options.addOption(bool, "keep_assert", opt_keep_assert);

    var opt_default_to_uncached_queries = b.option(bool, "default_to_uncached_queries",
        \\
        \\    When set, this will cause queries with the EcsQueryCacheDefault policy
        \\    to default to EcsQueryCacheNone. This can reduce the memory footprint of
        \\    applications at the cost of performance. Queries that use features which 
        \\    require caching such as group_by and order_by will still use caching.
    ) orelse false;
    options.addOption(bool, "default_to_uncached_queries", opt_default_to_uncached_queries);

    // NOTE: removed unnecessary CPP_NO_AUTO_REGISTRATION.
    // NOTE: removed unnecessary CPP_NO_ENUM_REFLECTION.

    const opt_no_always_inline = b.option(bool, "no_always_inline",
        \\
        \\    When set, this will prevent functions from being annotated with always_inline
        \\    which can improve performance at the cost of increased binary footprint.
    ) orelse false;
    options.addOption(bool, "no_always_inline", opt_no_always_inline);

    const opt_custom_build = b.option(CustomBuildMode, "custom_build",
        \\
        \\    This macro lets you customize which addons to build flecs with.
        \\    Without any addons Flecs is just a minimal ECS storage, but addons add
        \\    features such as systems, scheduling and reflection. If an addon is disabled,
        \\    it is excluded from the build, so that it consumes no resources. By default
        \\    all addons are enabled.
        \\
        \\    You can customize a build by either whitelisting or blacklisting addons. To
        \\    whitelist addons, first define the FLECS_CUSTOM_BUILD macro, which disables
        \\    all addons. You can then manually select the addons you need by defining
        \\    their macro, like "FLECS_SYSTEM".
        \\
        \\    To blacklist an addon, make sure to *not* define FLECS_CUSTOM_BUILD, and
        \\    instead define the addons you don't need by defining FLECS_NO_<addon>, for
        \\    example "FLECS_NO_SYSTEM". If there are any addons that depend on the
        \\    blacklisted addon, an error will be thrown during the build.
        \\
        \\    Note that addons can have dependencies on each other. Addons will
        \\    automatically enable their dependencies. To see the list of addons that was
        \\    compiled in a build, enable tracing before creating the world by doing:
        \\
        \\     @code
        \\     ecs_log_set_level(0);
        \\     @endcode
        \\
        \\    which outputs the full list of addons Flecs was compiled with.
    ) orelse .blacklist;

    var addons = Addons.init(opt_custom_build);

    const opt_alerts_addon = b.option(bool, "toggle_alerts_addon",
        \\
        \\    addon for monitor conditions for errors
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.alerts, opt_alerts_addon);
    options.addOption(bool, "alerts_addon", addons.includeAddon(.alerts));

    const opt_app_addon = b.option(bool, "toggle_app_addon",
        \\
        \\    Application addons
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.app, opt_app_addon);
    options.addOption(bool, "app_addon", addons.includeAddon(.app));

    const opt_doc_addon = b.option(bool, "toggle_doc_addon",
        \\
        \\    Document entities & components
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.doc, opt_doc_addon);
    options.addOption(bool, "doc_addon", addons.includeAddon(.doc));

    const opt_json_addon = b.option(bool, "toggle_json_addon",
        \\
        \\    Parsing JSON to/from component values
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.json, opt_json_addon);
    options.addOption(bool, "json_addon", addons.includeAddon(.json));

    const opt_http_addon = b.option(bool, "toggle_http_addon",
        \\
        \\    Tiny HTTP server for connecting to remote UI
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.http, opt_http_addon);
    options.addOption(bool, "http_addon", addons.includeAddon(.http));

    const opt_log_addon = b.option(bool, "toggle_log_addon",
        \\
        \\    When enabled ECS provides more detailed logs
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.log, opt_log_addon);
    options.addOption(bool, "log_addon", addons.includeAddon(.log));

    const opt_meta_addon = b.option(bool, "toggle_meta_addon",
        \\
        \\    Reflection support
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.meta, opt_meta_addon);
    options.addOption(bool, "meta_addon", addons.includeAddon(.meta));

    const opt_metrics_addon = b.option(bool, "toggle_metrics_addon",
        \\
        \\    Expose component data as statistics
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.metrics, opt_metrics_addon);
    options.addOption(bool, "metrics_addon", addons.includeAddon(.metrics));

    const opt_module_addon = b.option(bool, "toggle_module_addon",
        \\
        \\    Module support
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.module, opt_module_addon);
    options.addOption(bool, "module_addon", addons.includeAddon(.module));

    const opt_os_api_impl = b.option(bool, "toggle_os_api_impl_addon",
        \\
        \\    Default implementation for OS API
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.os_api_impl, opt_os_api_impl);
    options.addOption(bool, "os_api_impl_addon", addons.includeAddon(.os_api_impl));

    const opt_pipeline_addon = b.option(bool, "toggle_pipeline_addon",
        \\
        \\    Pipeline support
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.pipeline, opt_pipeline_addon);
    options.addOption(bool, "pipeline_addon", addons.includeAddon(.pipeline));

    const opt_rest_addon = b.option(bool, "toggle_rest_addon",
        \\
        \\    REST API for querying application data
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.rest, opt_rest_addon);
    options.addOption(bool, "rest_addon", addons.includeAddon(.rest));

    const opt_parser_addon = b.option(bool, "toggle_parser_addon",
        \\
        \\    Utilities for script and query DSL parsers
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.parser, opt_parser_addon);
    options.addOption(bool, "parser_addon", addons.includeAddon(.parser));

    const opt_query_dsl_addon = b.option(bool, "toggle_query_dsl_addon",
        \\
        \\    Flecs query DSL parser
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.query_dsl, opt_query_dsl_addon);
    options.addOption(bool, "query_dsl_addon", addons.includeAddon(.query_dsl));

    const opt_script_addon = b.option(bool, "toggle_script_addon",
        \\
        \\    Flecs entity notation language
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.script, opt_script_addon);
    options.addOption(bool, "script_addon", addons.includeAddon(.script));

    const opt_system_addon = b.option(bool, "toggle_system_addon",
        \\
        \\    System support
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.system, opt_system_addon);
    options.addOption(bool, "system_addon", addons.includeAddon(.system));

    const opt_stats_addon = b.option(bool, "toggle_stats_addon",
        \\
        \\    Track runtime statistics
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.stats, opt_stats_addon);
    options.addOption(bool, "stats_addon", addons.includeAddon(.stats));

    const opt_timer_addon = b.option(bool, "toggle_timer_addon",
        \\
        \\    Timer support
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.timer, opt_timer_addon);
    options.addOption(bool, "timer_addon", addons.includeAddon(.timer));

    const opt_units_addon = b.option(bool, "toggle_units_addon",
        \\
        \\    Builtin standard units
        \\    (Enables addon on whitelist mode, disables it on blacklist mode) 
    ) orelse false;
    addons.toggleAddon(.units, opt_units_addon);
    options.addOption(bool, "units_addon", addons.includeAddon(.units));

    const opt_low_footprint = b.option(bool, "low_footprint",
        \\
        \\    Set a number of constants to values that decrease memory footprint, at the
        \\    cost of decreased performance. 
    ) orelse false;

    var hi_component_id_value: ?usize = null;
    var hi_id_record_id_value: ?usize = null;
    var sparse_page_bits_value: ?usize = null;
    var entity_page_bits_value: ?usize = null;
    var id_desc_max_value: ?usize = null;
    var event_desc_max_value: ?usize = null;
    var variable_count_max_value: ?usize = null;
    var term_count_max_value: ?usize = null;
    var term_arg_count_max_value: ?usize = null;
    var query_variable_count_max_value: ?usize = null;
    var query_scope_nesting_max_value: ?usize = null;
    var dag_depth_max_value: ?usize = null;

    if (opt_low_footprint) {
        hi_component_id_value = 16;
        hi_id_record_id_value = 16;
        entity_page_bits_value = 6;
        opt_default_to_uncached_queries = true;
    }

    const opt_hi_component_id = b.option(usize, "hi_component_id",
        \\
        \\     This constant can be used to balance between performance and memory
        \\    utilization. The constant is used in two ways:
        \\     - Entity ids 0..FLECS_HI_COMPONENT_ID are reserved for component ids.
        \\     - Used as lookup array size in table edges.
        \\
        \\    Increasing this value increases the size of the lookup array, which allows
        \\    fast table traversal, which improves performance of ECS add/remove
        \\    operations. Component ids that fall outside of this range use a regular map
        \\    lookup, which is slower but more memory efficient.
        \\
        \\ This value must be set to a value that is a power of 2. Setting it to a value
        \\ that is not a power of two will degrade performance.
    );
    if (!opt_low_footprint) {
        if (opt_hi_component_id) |value| hi_component_id_value = value;
    }

    const opt_hi_id_record_id = b.option(usize, "hi_id_record_id",
        \\
        \\    This constant can be used to balance between performance and memory
        \\    utilization. The constant is used to determine the size of the component record
        \\    lookup array. Id values that fall outside of this range use a regular map
        \\    lookup, which is slower but more memory efficient.
    );
    if (!opt_low_footprint) {
        if (opt_hi_id_record_id) |value| hi_id_record_id_value = value;
    }

    const opt_sparse_page_bits = b.option(usize, "sparse_page_bits",
        \\
        \\    This constant is used to determine the number of bits of an id that is used
        \\    to determine the page index when used with a sparse set. The number of bits
        \\    determines the page size, which is (1 << bits).
        \\    Lower values decrease memory utilization, at the cost of more allocations. */
    );
    if (!opt_low_footprint) {
        if (opt_sparse_page_bits) |value| sparse_page_bits_value = value;
    }

    const opt_entity_page_bits = b.option(usize, "entity_page_bits",
        \\
        \\    Same as FLECS_SPARSE_PAGE_BITS, but for the entity index.
    );
    if (!opt_low_footprint) {
        if (opt_entity_page_bits) |value| entity_page_bits_value = value;
    }

    const opt_use_os_alloc = b.option(bool, "use_os_alloc",
        \\
        \\    When enabled, Flecs will use the OS allocator provided in the OS API directly
        \\    instead of the builtin block allocator. This can decrease memory utilization
        \\    as memory will be freed more often, at the cost of decreased performance. */
    ) orelse false;

    options.addOption(bool, "use_os_alloc", opt_use_os_alloc);

    const opt_id_desc_max = b.option(usize, "id_desc_max",
        \\
        \\    Maximum number of ids to add ecs_entity_desc_t / ecs_bulk_desc_t
    );
    if (opt_id_desc_max) |value| id_desc_max_value = value;

    const opt_event_desc_max = b.option(usize, "event_desc_max",
        \\
        \\    Maximum number of events in ecs_observer_desc_t
    );
    if (opt_event_desc_max) |value| event_desc_max_value = value;

    const opt_variable_count_max = b.option(usize, "variable_count_max",
        \\
        \\    Maximum number of query variables per query
    );
    if (opt_variable_count_max) |value| variable_count_max_value = value;

    const opt_term_count_max = b.option(usize, "term_count_max",
        \\
        \\    Maximum number of terms in queries. Should not exceed 64.
    );
    if (opt_term_count_max) |value| term_count_max_value = value;

    const opt_term_arg_count_max = b.option(usize, "term_arg_count_max",
        \\
        \\    Maximum number of arguments for a term.
    );
    if (opt_term_arg_count_max) |value| term_arg_count_max_value = value;

    const opt_query_variable_count_max = b.option(usize, "query_variable_count_max",
        \\
        \\    Maximum number of query variables per query. Should not exceed 128.
    );
    if (opt_query_variable_count_max) |value| query_variable_count_max_value = value;

    const opt_query_scope_nesting_max = b.option(usize, "query_scope_nesting_max",
        \\
        \\    Maximum nesting depth of query scopes
    );
    if (opt_query_scope_nesting_max) |value| query_scope_nesting_max_value = value;

    const opt_dag_depth_max = b.option(usize, "dag_depth_max",
        \\
        \\    Maximum of levels in a DAG (acyclic relationship graph). If a graph with a
        \\    depth larger than this is encountered, a CYCLE_DETECTED panic is thrown.
    );
    if (opt_dag_depth_max) |value| dag_depth_max_value = value;

    options.addOption(?usize, "hi_component_id", hi_component_id_value);
    options.addOption(?usize, "hi_id_record_id", hi_id_record_id_value);
    options.addOption(?usize, "sparse_page_bits", sparse_page_bits_value);
    options.addOption(?usize, "entity_page_bits", entity_page_bits_value);
    options.addOption(?usize, "id_desc_max", id_desc_max_value);
    options.addOption(?usize, "event_desc_max", event_desc_max_value);
    options.addOption(?usize, "variable_count_max", variable_count_max_value);
    options.addOption(?usize, "term_count_max", term_count_max_value);
    options.addOption(?usize, "term_arg_count_max", term_arg_count_max_value);
    options.addOption(?usize, "query_variable_count_max", query_variable_count_max_value);
    options.addOption(?usize, "query_scope_nesting_max", query_scope_nesting_max_value);
    options.addOption(?usize, "dag_depth_max", dag_depth_max_value);

    const module = b.addModule("root", .{
        .root_source_file = b.path("src/zflecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    module.addOptions("build-options", options);

    module.addIncludePath(b.path("libs/flecs"));
    module.addCSourceFile(.{
        .file = b.path("libs/flecs/flecs.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
            // NOTE: Forced use os alloc to mirror zflecs expected behavior
            if (opt_use_os_alloc) "-DFLECS_USE_OS_ALLOC" else "-DFLECS_USE_OS_ALLOC",
            if (opt_use_shared) "-DFLECS_SHARED" else "",

            if (opt_accurate_counters) "-DFLECS_ACCURATE_COUNTERS" else "",
            if (opt_disable_counters) "-DFLECS_DISABLE_COUNTERS" else "",
            if (opt_debug_info) "-DFLECS_DEBUG_INFO" else "",
            if (opt_soft_assert) "-DFLECS_SOFT_ASSERT" else "",
            if (opt_keep_assert) "-DFLECS_KEEP_ASSERT" else "",
            if (opt_default_to_uncached_queries) "-DFLECS_DEFAULT_TO_UNCACHED_QUERIES" else "",
            if (opt_no_always_inline) "-DFLECS_NO_ALWAYS_INLINE" else "",
            switch (opt_debug_mode) {
                .debug => "-DFLECS_DEBUG",
                .sanitize => "-DFLECS_SANITIZE",
                .none => "",
                .depends_on_build => if (builtin.mode == .Debug) "-DFLECS_SANITIZE" else "",
            },
            "-DFLECS_CUSTOM_BUILD",
            if (addons.includeAddon(.alerts)) "-DFLECS_ALERTS" else "",
            if (addons.includeAddon(.app)) "-DFLECS_APP" else "",
            if (addons.includeAddon(.doc)) "-DFLECS_DOC" else "",
            if (addons.includeAddon(.json)) "-DFLECS_JSON" else "",
            if (addons.includeAddon(.http)) "-DFLECS_HTTP" else "",
            if (addons.includeAddon(.log)) "-DFLECS_LOG" else "",
            if (addons.includeAddon(.meta)) "-DFLECS_META" else "",
            if (addons.includeAddon(.metrics)) "-DFLECS_METRICS" else "",
            if (addons.includeAddon(.module)) "-DFLECS_MODULE" else "",
            if (addons.includeAddon(.os_api_impl)) "-DFLECS_OS_API_IMPL" else "",
            if (addons.includeAddon(.pipeline)) "-DFLECS_PIPELINE" else "",
            if (addons.includeAddon(.rest)) "-DFLECS_REST" else "",
            if (addons.includeAddon(.parser)) "-DFLECS_PARSER" else "",
            if (addons.includeAddon(.query_dsl)) "-DFLECS_QUERY_DSL" else "",
            if (addons.includeAddon(.script)) "-DFLECS_SCRIPT" else "",
            if (addons.includeAddon(.system)) "-DFLECS_SYSTEM" else "",
            if (addons.includeAddon(.stats)) "-DFLECS_STATS" else "",
            if (addons.includeAddon(.timer)) "-DFLECS_TIMER" else "",
            if (addons.includeAddon(.units)) "-DFLECS_UNITS" else "",
            convertFloatPrecisionFlag(b.allocator, "ecs_float_t", opt_float_precision),
            convertFloatPrecisionFlag(b.allocator, "ecs_ftime_t", opt_scalar_time_precision),
            if (opt_low_footprint) "-DFLECS_LOW_FOOTPRINT" else "",
            if (opt_hi_component_id) |value|
                convertSizeFlag(b.allocator, "FLECS_HI_COMPONENT_ID", value)
            else
                "",
            if (opt_hi_id_record_id) |value|
                convertSizeFlag(b.allocator, "FLECS_HI_ID_RECORD_ID", value)
            else
                "",
            if (opt_sparse_page_bits) |value|
                convertSizeFlag(b.allocator, "FLECS_SPARSE_PAGE_BITS", value)
            else
                "",
            if (opt_entity_page_bits) |value|
                convertSizeFlag(b.allocator, "FLECS_ENTITY_PAGE_BITS", value)
            else
                "",
            if (opt_id_desc_max) |value| convertSizeFlag(b.allocator, "FLECS_ID_DESC_MAX", value) else "",
            if (opt_event_desc_max) |value| convertSizeFlag(b.allocator, "FLECS_EVENT_DESC_MAX", value) else "",
            if (opt_variable_count_max) |value|
                convertSizeFlag(b.allocator, "FLECS_VARIABLE_COUNT_MAX", value)
            else
                "",
            if (opt_term_count_max) |value| convertSizeFlag(b.allocator, "FLECS_TERM_COUNT_MAX", value) else "",
            if (opt_term_arg_count_max) |value|
                convertSizeFlag(b.allocator, "FLECS_TERM_ARG_COUNT_MAX", value)
            else
                "",
            if (opt_query_variable_count_max) |value|
                convertSizeFlag(b.allocator, "FLECS_QUERY_VARIABLE_COUNT_MAX", value)
            else
                "",
            if (opt_query_scope_nesting_max) |value|
                convertSizeFlag(b.allocator, "FLECS_QUERY_SCOPE_NESTING_MAX", value)
            else
                "",
            if (opt_dag_depth_max) |value| convertSizeFlag(b.allocator, "FLECS_DAG_DEPTH_MAX", value) else "",
        },
    });

    const lib = b.addLibrary(.{
        .name = "flecs",
        .linkage = if (opt_use_shared) .dynamic else .static,
        .root_module = module,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("ws2_32");
        lib.linkSystemLibrary("dbghelp");
    }
    const test_step = b.step("test", "Run zflecs tests");

    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_module.addOptions("build-options", options);

    const tests = b.addTest(.{
        .name = "zflecs-tests",
        .root_module = tests_module,
    });
    tests.addIncludePath(b.path("libs/flecs"));
    tests.linkLibrary(lib);
    tests.linkLibC();
    b.installArtifact(tests);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
