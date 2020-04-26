#!/usr/bin/env tarantool
test = require("sqltester")
test:plan(57)

--!./tcltestrunner.lua
-- 2008 July 15
--
-- The author disclaims copyright to this source code.  In place of
-- a legal notice, here is a blessing:
--
--    May you do good and not evil.
--    May you find forgiveness for yourself and forgive others.
--    May you share freely, never taking more than you give.
--
-------------------------------------------------------------------------
-- This file implements regression tests for sql library.
--
-- The focus of this file is testing how sql generates the names
-- of columns in a result set.
--
-- $Id: colname.test,v 1.7 2009/06/02 15:47:38 drh Exp $
-- ["set","testdir",[["file","dirname",["argv0"]]]]
-- ["source",[["testdir"],"\/tester.tcl"]]
-- Rules (applied in order):
--
-- (1) If there is an AS clause, use it.
--
-- (2) A non-trival expression (not a table column name) then the name is
--     a copy of the expression text.
--
-- (3) If full_column_names=OFF, then just the abbreviated column name without
--     the table name.
--
-- (4) When full_column_names=ON then use the form: TABLE.COLUMN
--
-- Verify the default settings for full_column_name
--
local function lreplace(arr, pos, len, val)
    for i = pos + 1, pos + len + 1, 1 do
        arr[i] = val
    end
    return arr
end

test:do_test(
    "colname-1.1",
    function()
        return box.space._session_settings:get("sql_full_column_names").value
    end,
        -- <colname-1.2>
        false
        -- </colname-1.2>
    )

-- Tests for then short=ON and full=any
--
test:do_test(
    "colname-2.1",
    function()
        test:execsql [[
            CREATE TABLE tabc(a INT PRIMARY KEY,b INT,c INT);
            INSERT INTO tabc VALUES(1,2,3);
            CREATE TABLE txyz(x INT PRIMARY KEY,y INT,z INT);
            INSERT INTO txyz VALUES(4,5,6);
            CREATE TABLE tboth(a INT PRIMARY KEY,b INT,c INT,x INT,y INT,z INT);
            INSERT INTO tboth VALUES(11,12,13,14,15,16);
        ]]
        return test:execsql2 [[
            SELECT * FROM tabc;
        ]]
    end, {
        -- <colname-2.1>
        "A", 1, "B", 2, "C", 3
        -- </colname-2.1>
    })

test:do_execsql2_test(
    "colname-2.2",
    [[
        SELECT Tabc.a, tAbc.b, taBc.c, * FROM tabc
    ]], {
        -- <colname-2.2>
        "A", 1, "B", 2, "C", 3, "A", 1, "B", 2, "C", 3
        -- </colname-2.2>
    })

test:do_execsql2_test(
    "colname-2.3",
    [[
        SELECT +tabc.a, -tabc.b, tabc.c, * FROM tabc
    ]], {
        -- <colname-2.3>
        "COLUMN_1",1,"COLUMN_2",-2,"C",3,"A",1,"B",2,"C",3
        -- </colname-2.3>
    })

test:do_execsql2_test(
    "colname-2.4",
    [[
        SELECT +tabc.a AS AAA, -tabc.b AS BBB, tabc.c CCC, * FROM tabc
    ]], {
        -- <colname-2.4>
        "AAA", 1, "BBB", -2, "CCC", 3, "A", 1, "B", 2, "C", 3
        -- </colname-2.4>
    })

test:do_execsql2_test(
    "colname-2.5",
    [[
        SELECT tabc.a, txyz.x, * FROM tabc, txyz;
    ]], {
        -- <colname-2.5>
        "A", 1, "X", 4, "A", 1, "B", 2, "C", 3, "X", 4, "Y", 5, "Z", 6
        -- </colname-2.5>
    })

test:do_execsql2_test(
    "colname-2.6",
    [[
        SELECT tabc.a, txyz.x, tabc.*, txyz.* FROM tabc, txyz;
    ]], {
        -- <colname-2.6>
        "A", 1, "X", 4, "A", 1, "B", 2, "C", 3, "X", 4, "Y", 5, "Z", 6
        -- </colname-2.6>
    })

test:do_execsql2_test(
    "colname-2.7",
    [[
        SELECT tabc.a, txyz.x, tboth.a, tboth.x, * FROM tabc, txyz, tboth;
    ]], {
        -- <colname-2.7>
    "A",1,"X",4,"A",11,"X",14,"A",1,"B",2,"C",3,"X",4,"Y",5,"Z",6,"A",11,"B",12,"C",13,"X",14,"Y",15,"Z",16
        -- </colname-2.7>
    })

-- Tests for full=OFF
test:do_test(
    "colname-3.1",
    function()
        return test:execsql2 [[
            SELECT * FROM tabc;
        ]]
    end, {
        -- <colname-3.1>
        "A", 1, "B", 2, "C", 3
        -- </colname-3.1>
    })

test:do_execsql2_test(
    "colname-3.2",
    [[
        SELECT Tabc.a, tAbc.b, taBc.c FROM tabc
    ]], {
        -- <colname-3.2>
        "A", 1, "B", 2, "C", 3
        -- </colname-3.2>
    })

test:do_execsql2_test(
    "colname-3.3",
    [[
        SELECT +tabc.a, -tabc.b, tabc.c FROM tabc
    ]], {
        -- <colname-3.3>
        "COLUMN_1",1,"COLUMN_2",-2,"C",3
        -- </colname-3.3>
    })

test:do_execsql2_test(
    "colname-3.4",
    [[
        SELECT +tabc.a AS AAA, -tabc.b AS BBB, tabc.c CCC FROM tabc
    ]], {
        -- <colname-3.4>
        "AAA", 1, "BBB", -2, "CCC", 3
        -- </colname-3.4>
    })

test:do_execsql2_test(
    "colname-3.5",
    [[
        SELECT Tabc.a, Txyz.x, * FROM tabc, txyz;
    ]], {
        -- <colname-3.5>
        "A", 1, "X", 4, "A", 1, "B", 2, "C", 3, "X", 4, "Y", 5, "Z", 6
        -- </colname-3.5>
    })

test:do_execsql2_test(
    "colname-3.6",
    [[
        SELECT tabc.*, txyz.* FROM tabc, txyz;
    ]], {
        -- <colname-3.6>
        "A", 1, "B", 2, "C", 3, "X", 4, "Y", 5, "Z", 6
        -- </colname-3.6>
    })

test:do_execsql2_test(
    "colname-3.7",
    [[
        SELECT * FROM tabc, txyz, tboth;
    ]], {
        -- <colname-3.7>
        "A",1,"B",2,"C",3,"X",4,"Y",5,"Z",6,"A",11,"B",12,"C",13,"X",14,"Y",15,"Z",16
        -- </colname-3.7>
    })

-- Test for full=ON
test:do_test(
    "colname-4.1",
    function()
        test:execsql [[
            UPDATE "_session_settings" SET "value" = true WHERE "name" = 'sql_full_column_names';
        ]]
        return test:execsql2 [[
            SELECT * FROM tabc;
        ]]
    end, {
        -- <colname-4.1>
        "TABC.A", 1, "TABC.B", 2, "TABC.C", 3
        -- </colname-4.1>
    })

test:do_execsql2_test(
    "colname-4.2",
    [[
        SELECT Tabc.a, tAbc.b, taBc.c FROM tabc
    ]], {
        -- <colname-4.2>
        "TABC.A", 1, "TABC.B", 2, "TABC.C", 3
        -- </colname-4.2>
    })

test:do_execsql2_test(
    "colname-4.3",
    [[
        SELECT +tabc.a, -tabc.b, tabc.c FROM tabc
    ]], {
        -- <colname-4.3>
        "COLUMN_1",1,"COLUMN_2",-2,"TABC.C",3
        -- </colname-4.3>
    })

test:do_execsql2_test(
    "colname-4.4",
    [[
        SELECT +tabc.a AS AAA, -tabc.b AS BBB, tabc.c CCC FROM tabc
    ]], {
        -- <colname-4.4>
        "AAA", 1, "BBB", -2, "CCC", 3
        -- </colname-4.4>
    })

test:do_execsql2_test(
    "colname-4.5",
    [[
        SELECT Tabc.a, Txyz.x, * FROM tabc, txyz;
    ]], {
        -- <colname-4.5>
        "TABC.A", 1, "TXYZ.X", 4, "TABC.A", 1, "TABC.B", 2, "TABC.C", 3, "TXYZ.X", 4, "TXYZ.Y", 5, "TXYZ.Z", 6
        -- </colname-4.5>
    })

test:do_execsql2_test(
    "colname-4.6",
    [[
        SELECT tabc.*, txyz.* FROM tabc, txyz;
    ]], {
        -- <colname-4.6>
        "TABC.A", 1, "TABC.B", 2, "TABC.C", 3, "TXYZ.X", 4, "TXYZ.Y", 5, "TXYZ.Z", 6
        -- </colname-4.6>
    })

test:do_execsql2_test(
    "colname-4.7",
    [[
        SELECT * FROM tabc, txyz, tboth;
    ]], {
        -- <colname-4.7>
        "TABC.A", 1, "TABC.B", 2, "TABC.C", 3, "TXYZ.X", 4, "TXYZ.Y", 5, "TXYZ.Z", 6, "TBOTH.A", 11, "TBOTH.B", 12, "TBOTH.C", 13, "TBOTH.X", 14, "TBOTH.Y", 15, "TBOTH.Z", 16
        -- </colname-4.7>
    })

-- MUST_WORK_TEST avoid using sql_master
-- ticket #3229
--    test:do_test(
--        "colname-5.1",
--        function()
--            return lreplace( test:execsql("SELECT x.* FROM sql_master X LIMIT 1;"), 3, 3,"x")
--        end, {
--            -- <colname-5.1>
--            "table", "tabc", "tabc", "x", "CREATE TABLE tabc(a INT,b INT,c INT)"
--            -- </colname-5.1>
--        })

-- ticket #3370, #3371, #3372
--
test:do_test(
    "colname-6.1",
    function()
        --db("close")
        --sql("db", "test.db")
        -- instead of reconnect to database
        -- we are just turning settings to default state
        test:execsql([[
            UPDATE "_session_settings" SET "value" = false WHERE "name" = 'sql_full_column_names';
            ]])
        test:execsql [=[
            CREATE TABLE t6(a INT primary key, "'a'" INT, """a""" INT, "[a]" INT,  "`a`" INT);
            INSERT INTO t6 VALUES(1,2,3,4,5);
        ]=]
        return test:execsql2 "SELECT * FROM t6"
    end, {
        -- <colname-6.1>
        "A", 1, "'a'", 2, [["a"]], 3, "[a]", 4, "`a`", 5
        -- </colname-6.1>
    })

test:do_execsql2_test(
    "colname-6.3",
    [=[
        SELECT "'a'", "`a`", "[a]", "A", """a""" FROM t6
    ]=], {
        -- <colname-6.3>
        "'a'", 2, "`a`", 5, "[a]", 4, "A", 1, [["a"]], 3
        -- </colname-6.3>
    })

test:do_execsql2_test(
    "colname-6.11",
    [[
        SELECT a, max(a) AS m FROM t6
    ]], {
        -- <colname-6.11>
        "A", 1, "M", 1
        -- </colname-6.11>
    })

test:do_execsql2_test(
    "colname-6.13",
    [[
        SELECT a, max(a) AS m FROM t6
    ]], {
        -- <colname-6.13>
        "A", 1, "M", 1
        -- </colname-6.13>
    })

test:do_execsql2_test(
    "colname-6.15",
    [[
        SELECT t6.a, max(a) AS m FROM t6
    ]], {
        -- <colname-6.15>
        "A", 1, "M", 1
        -- </colname-6.15>
    })

test:do_execsql2_test(
    "colname-6.18",
    [=[
        SELECT "[a]", max("[a]") AS m FROM t6
    ]=], {
        -- <colname-6.18>
        "[a]", 4, "M", 4
        -- </colname-6.18>
    })

test:do_execsql2_test(
    "colname-6.19",
    [=[
        SELECT "`a`", max("`a`") AS m FROM t6
    ]=], {
        -- <colname-6.19>
        "`a`", 5, "M", 5
        -- </colname-6.19>
    })

-- Ticket #3429
-- We cannot find anything wrong, but it never hurts to add another
-- test case.
test:do_test(
    "colname-7.1",
    function()
        test:execsql [[
            CREATE TABLE t7(x INTEGER PRIMARY KEY, y INT);
            INSERT INTO t7 VALUES(1,2);
        ]]
        return test:execsql2 "SELECT x, * FROM t7"
    end, {
        -- <colname-7.1>
        "X", 1, "X", 1, "Y", 2
        -- </colname-7.1>
    })

-- Tickets #3893 and #3984.  (Same problem; independently reported)
--
test:do_test(
    "colname-8.1",
    function()
        return test:execsql [[
            CREATE TABLE t3893("x" INT PRIMARY KEY);
            INSERT INTO t3893 VALUES(123);
            SELECT "y"."x" FROM (SELECT "x" FROM t3893) AS "y";
        ]]
    end, {
        -- <colname-8.1>
        123
        -- </colname-8.1>
    })

local data = {
    [[`a`]],
    "[a]",
}
for i, val in ipairs(data) do
    test:do_catchsql_test(
        "colname-9.1."..i,
        string.format("SELECT %s FROM t6", val),
        {1, "/unrecognized token/"}
    )
end

local data2 = {
    {[['a']],{1, "/Syntax error/"}}, -- because ' is delimiter for strings
    {[[`a`]],{1, "/unrecognized token/"}}, -- because ` is undefined symbol
    {"[a]",{1, "/unrecognized token/"}} -- because [ is undefined symbol
}
for i, val in ipairs(data2) do
    test:do_catchsql_test(
        "colname-9.2"..i,
        string.format("create table %s(a primary key)", val[1]),
        val[2]
    )
end


for i, val in ipairs(data2) do
    test:do_catchsql_test(
        "colname-9.3."..i,
        string.format("create table a(%s primary key)", val[1]),
        val[2]
    )
end

test:execsql([[ create table table1("a" TEXT primary key, "b" TEXT) ]])
test:execsql("insert into table1 values('a1', 'a1')")

-- " is used for identifiers
-- ' is used for strings

local data3 = {
    --{1, [["a1" = "b1"]], {0, {}}}, -- should be error: column does not exist?
    {2, [["a" = 'a1']], {0, {"a1", "a1"}}},
    {3, [['a' = 'a1']], {0, {}}},
    {4, [["a" = "b"]], {0, {"a1", "a1"}}},
    {5, [['a1' = "a"]], {0, {"a1", "a1"}}},
    {6, [['a' = "a"]], {0, {}}},
    {7, [[ "a" = "a"]], {0, {"a1", "a1"}}},
}

for _, val in ipairs(data3) do
    test:do_catchsql_test(
        "colname-10.1."..val[1],
        string.format([[select * from table1 where %s]], val[2]),
        val[3])
end

test:do_test(
    "colname-11.0.1",
    function ()
        test:drop_all_views()
    end,
    nil)

test:do_test(
    "colname-11.0.2",
    function ()
        test:drop_all_tables()
    end,
    nil)

test:do_catchsql_test(
    "colname-11.1",
    [[ create table t1(a INT, b INT, c INT, primary key('A'))]],
    {1, "Expressions are prohibited in an index definition"})

test:do_catchsql_test(
    "colname-11.2",
    [[CREATE TABLE t1(a INT, b INT, c INT, d INT, e INT,
      PRIMARY KEY(a), UNIQUE('b' COLLATE "unicode_ci" DESC));]],
    {1, "/Tarantool does not support functional indexes/"})

test:execsql("create table table1(a  INT primary key, b INT, c INT)")

test:do_catchsql_test(
    "colname-11.3",
    [[ CREATE INDEX t1c ON table1('c'); ]],
    {1, "/Tarantool does not support functional indexes/"})

--
-- gh-3962: Check auto generated names in different selects.
--
test:do_execsql2_test(
    "colname-12.1",
    [[
        VALUES(1, 2, 'aaa');
    ]], {
        "COLUMN_1",1,"COLUMN_2",2,"COLUMN_3","aaa"
    })

test:do_execsql2_test(
    "colname-12.2",
    [[
        SELECT * FROM (VALUES (1+1, 1+1, 'aaa'));
    ]], {
        "COLUMN_1",2,"COLUMN_2",2,"COLUMN_3","aaa"
    })

test:do_execsql2_test(
    "colname-12.3",
    [[
        SELECT 1+1, 1+1, 'aaa';
    ]], {
        "COLUMN_1",2,"COLUMN_2",2,"COLUMN_3","aaa"
    })

test:do_execsql2_test(
    "colname-12.4",
    [[
        SELECT * FROM (SELECT * FROM (VALUES(1, 2, 'aaa'))),
                      (SELECT * FROM (VALUES(1, 2, 'aaa')))
    ]], {
        "COLUMN_1",1,"COLUMN_2",2,"COLUMN_3","aaa","COLUMN_4",1,"COLUMN_5",2,
        "COLUMN_6","aaa"
    })

test:do_execsql2_test(
    "colname-12.5",
    [[
        CREATE TABLE j (s1 SCALAR PRIMARY KEY);
        INSERT INTO j VALUES(1);
    ]], {})

--
-- Column named as 's1', because <COLLATE> is skipped in such
-- expressions.
--
test:do_execsql2_test(
    "colname-12.6",
    [[
        SELECT s1 COLLATE "unicode_ci" FROM j;
    ]], {
        "S1",1
    })

test:do_catchsql_test(
    "colname-12.7",
    [[
        SELECT s1 COLLATE "unicode_ci" FROM j ORDER BY column_1;
    ]], {
        1,"Can’t resolve field 'COLUMN_1'"
    })

test:finish_test()
