include_files = {
    "**/*.lua",
    "extra/dist/tarantoolctl.in",
}

exclude_files = {
    "build/**/*.lua",
    "src/box/lua/serpent.lua", -- third-party source code
    "test/app/*.lua",
    "test/app-tap/lua/serializer_test.lua",
    "test/box/**/*.lua",
    "test/engine/*.lua",
    "test/engine_long/*.lua",
    "test/long_run-py/**/*.lua",
    "test/vinyl/*.lua",
    "test/replication/*.lua",
    "test/sql/*.lua",
    "test/swim/*.lua",
    "test/xlog/*.lua",
    "test/wal_off/*.lua",
    "test/var/**/*.lua",
    "test-run/**/*.lua",
    "third_party/**/*.lua",
    ".rocks/**/*.lua",
    ".git/**/*.lua",
}

files["**/*.lua"] = {
    globals = {"box", "_TARANTOOL", "help", "tutorial"},
    ignore = {"212/self", "122"}
}
files["extra/dist/tarantoolctl.in"] = {ignore = {"212/self", "122", "431"}}
files["src/lua/*.lua"] = {ignore = {"212/self"}}
files["src/lua/init.lua"] = {globals = {"dostring"}}
files["src/lua/swim.lua"] = {ignore = {"431"}}
files["src/box/lua/console.lua"] = {ignore = {"212"}}
files["src/box/lua/load_cfg.lua"] = {ignore = {"542"}}
files["src/box/lua/net_box.lua"] = {ignore = {"431", "432", "411"}}
files["src/box/lua/schema.lua"] = {ignore = {"431", "432"}}
files["test/app/lua/fiber.lua"] = {globals = {"box_fiber_run_test"}}
files["test/app-tap/console.test.lua"] = {globals = {"long_func"}}
files["test/app-tap/lua/require_mod.lua"] = {globals = {"exports"}}
files["test/app-tap/module_api.test.lua"] = {ignore = {"311"}}
files["test/app-tap/string.test.lua"] = {globals = {"utf8"}}
files["test/app-tap/tarantoolctl.test.lua"] = {ignore = {"113", "421"}}
files["test/box-tap/session.test.lua"] = {
	globals = {"active_connections", "session", "space", "f1", "f2"},
	ignore = {"211"}
}
files["test/box/lua/push.lua"] = {globals = {"push_collection"}}
files["test/box/lua/index_random_test.lua"] = {globals = {"index_random_test"}}
files["test/box/lua/utils.lua"] = {
	globals = {"space_field_types", "iterate", "arithmetic", "table_shuffle",
	"table_generate", "tuple_to_string", "check_space", "space_bsize",
	"create_iterator", "setmap", "sort"}}
files["test/box/lua/bitset.lua"] = {
	globals = {"create_space", "fill", "delete", "clear", "drop_space",
	"dump", "test_insert_delete"}
}
files["test/box/lua/fifo.lua"] = {globals = {"fifomax", "find_or_create_fifo", "fifo_push", "fifo_top"}}
files["test/box/lua/identifier.lua"] = {globals = {"run_test"}}
files["test/box/lua/require_mod.lua"] = {globals = {"exports"}}
files["test/luajit-tap/gh-4476-fix-string-find-recording.test.lua"] = {ignore = {"231"}}
files["test/luajit-tap/or-232-unsink-64-kptr.test.lua"] = {ignore = {"542"}}
files["test/replication/lua/fast_replica.lua"] = {
	globals = {"join", "start_all", "stop_all", "wait_all",
	"drop_all", "drop_all", "vclock_diff", "unregister",
	"delete", "start", "stop", "call_all", "drop", "wait"},
	ignore = {"212", "213"}
}
files["test/sql-tap/*.lua"] = {ignore = {"611", "612", "613", "614", "621", "631", "211", "113", "111"}}
files["test/sql-tap/lua/sqltester.lua"] = {globals = {"table_match_regex_p"}}
files["test/sql-tap/e_expr.test.lua"] = {ignore = {"512"}}
