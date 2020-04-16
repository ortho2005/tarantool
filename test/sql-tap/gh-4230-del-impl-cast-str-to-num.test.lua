#!/usr/bin/env tarantool
test = require("sqltester")
test:plan(8)

--
-- Make sure that there is no implicit cast between string and
-- number.
--
test:do_catchsql_test(
    "gh-4230-1",
    [[
        SELECT '1' > 0;
    ]], {
        1, "Type mismatch: can not convert 1 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-2",
    [[
        SELECT 0 > '1';
    ]], {
        1, "Type mismatch: can not convert 1 to numeric"
    })

test:execsql([[
        CREATE TABLE t (i INT PRIMARY KEY, d DOUBLE, n NUMBER, s STRING);
        INSERT INTO t VALUES (1, 1.0, 1, '2'), (2, 2.0, 2.0, '2');
    ]])

test:do_catchsql_test(
    "gh-4230-3",
    [[
        SELECT * from t where i > s;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-4",
    [[
        SELECT * from t WHERE s > i;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-5",
    [[
        SELECT * from t WHERE d > s;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-6",
    [[
        SELECT * from t WHERE s > d;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-7",
    [[
        SELECT * from t WHERE i = 1 and n > s;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:do_catchsql_test(
    "gh-4230-8",
    [[
        SELECT * from t WHERE i = 2 and s > n;
    ]], {
        1, "Type mismatch: can not convert 2 to numeric"
    })

test:finish_test()
