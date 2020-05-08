#!/usr/bin/env tarantool

local tap = require('tap')
local ffi = require('ffi')
local json = require('json')
local fun = require('fun')
local key_def_lib = require('key_def')

local usage_error = 'Bad params, use: key_def.new({' ..
                    '{fieldno = fieldno, type = type' ..
                    '[, is_nullable = <boolean>]' ..
                    '[, path = <string>]' ..
                    '[, collation_id = <number>]' ..
                    '[, collation = <string>]}, ...}'

local function coll_not_found(fieldno, collation)
    if type(collation) == 'number' then
        return ('Wrong index options (field %d): ' ..
               'collation was not found by ID'):format(fieldno)
    end

    return ('Unknown collation: "%s"'):format(collation)
end

local function set_key_part_defaults(parts)
    local res = {}
    for i, part in ipairs(parts) do
        res[i] = table.copy(part)
        if res[i].is_nullable == nil then
            res[i].is_nullable = false
        end
    end
    return res
end

local key_def_new_cases = {
    -- Cases to call before box.cfg{}.
    {
        'Pass no key parts',
        parts = {},
        exp_err = 'Key definition can only be constructed by using at least 1 key_part',
    },
    {
        "Pass a garbage instead of key parts",
        parts = {fieldno = 1, type = 'unsigned'},
        exp_err = 'Key definition can only be constructed by using at least 1 key_part',
    },
    {
        'Pass a field on an unknown type',
        parts = {{
            fieldno = 2,
            type = 'unknown',
        }},
        exp_err = 'Unknown field type: unknown',
    },
    {
        'Try to use collation_id before box.cfg{}',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 2,
        }},
        exp_err = coll_not_found(1, 2),
    },
    {
        'Try to use collation before box.cfg{}',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation = 'unicode_ci',
        }},
        exp_err = coll_not_found(1, 'unicode_ci'),
    },
    function()
        -- For collations.
        box.cfg{}
    end,
    -- Cases to call after box.cfg{}.
    {
        'Try to use both collation_id and collation',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 2,
            collation = 'unicode_ci',
        }},
        exp_err = 'Conflicting options: collation_id and collation',
    },
    {
        'Unknown collation_id',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation_id = 999,
        }},
        exp_err = coll_not_found(1, 999),
    },
    {
        'Unknown collation name',
        parts = {{
            fieldno = 1,
            type = 'string',
            collation = 'unknown',
        }},
        exp_err = 'Unknown collation: "unknown"',
    },
    {
        'Bad parts parameter type',
        parts = 1,
        exp_err = usage_error,
    },
    {
        'No parameters',
        params = {},
        exp_err = usage_error,
    },
    {
        'Two parameters',
        params = {{}, {}},
        exp_err = usage_error,
    },
    {
        'Invalid JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[3[',
        }},
        exp_err = 'invalid path',
    },
    {
        'Multikey JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[*]',
        }},
        exp_err = 'multikey path is unsupported',
    },
    {
        'Success case; one part',
        parts = {{
            fieldno = 1,
            type = 'string',
        }},
        exp_err = nil,
    },
    {
        'Success case; one part with a JSON path',
        parts = {{
            fieldno = 1,
            type = 'string',
            path = '[3]',
        }},
        exp_err = nil,
    },
    --
    -- gh-4519: key_def should allow the same options as
    -- <space_object>.create_index(). That is, a field number
    -- should be allowed to be specified as `field`, not only
    -- `fieldno`.
    --
    {
        'Success case; `field` is alias to `fieldno`',
        parts = {{
            field = 1,
            type = 'unsigned'
        }},
        exp_err = nil,
    },
    {
        'Field and fieldno can not be set both',
        parts = {{
            field = 1,
            fieldno = 1,
            type = 'unsigned'
        }},
        exp_err = 'Conflicting options: fieldno and field',
    }
}

local test = tap.test('key_def')

test:plan(#key_def_new_cases - 1 + 7)
for _, case in ipairs(key_def_new_cases) do
    if type(case) == 'function' then
        case()
    else
        local ok, res
        if case.params then
            ok, res = pcall(key_def_lib.new, unpack(case.params))
        else
            ok, res = pcall(key_def_lib.new, case.parts)
        end
        if case.exp_err == nil then
            ok = ok and type(res) == 'cdata' and
                ffi.istype('struct key_def', res)
            test:ok(ok, case[1])
        else
            local err = tostring(res) -- cdata -> string
            test:is_deeply({ok, err}, {false, case.exp_err}, case[1])
        end
    end
end

-- Prepare source data for test cases.

-- Case: extract_key().
test:test('extract_key()', function(testcase)
    testcase:plan(13)

    local key_def_a = key_def_lib.new({
        {type = 'unsigned', fieldno = 1},
    })
    local key_def_b = key_def_lib.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local key_def_c = key_def_lib.new({
        {type = 'scalar', fieldno = 2},
        {type = 'scalar', fieldno = 1},
        {type = 'string', fieldno = 4, is_nullable = true},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    testcase:is_deeply(key_def_a:extract_key(tuple_a):totable(), {1}, 'case 1')
    testcase:is_deeply(key_def_b:extract_key(tuple_a):totable(), {1, 22}, 'case 2')

    -- JSON path.
    local res = key_def_lib.new({
        {type = 'string', fieldno = 1, path = 'a.b'},
    }):extract_key(box.tuple.new({{a = {b = 'foo'}}})):totable()
    testcase:is_deeply(res, {'foo'}, 'JSON path (tuple argument)')

    res = key_def_lib.new({
        {type = 'string', fieldno = 1, path = 'a.b'},
    }):extract_key({{a = {b = 'foo'}}}):totable()
    testcase:is_deeply(res, {'foo'}, 'JSON path (table argument)')

    -- A key def has a **nullable** part with a field that is over
    -- a tuple size.
    --
    -- The key def options are:
    --
    -- * is_nullable = true;
    -- * has_optional_parts = true.
    testcase:is_deeply(key_def_c:extract_key(tuple_a):totable(), {1, 1, box.NULL},
        'short tuple with a nullable part')

    -- A key def has a **non-nullable** part with a field that is
    -- over a tuple size.
    --
    -- The key def options are:
    --
    -- * is_nullable = false;
    -- * has_optional_parts = false.
    local exp_err = 'Tuple field [2] required by space format is missing'
    local key_def = key_def_lib.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
    })
    local ok, err = pcall(key_def.extract_key, key_def,
        box.tuple.new({'foo'}))
    testcase:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 1)')

    -- Same as before, but a max fieldno is over tuple:len() + 1.
    exp_err = 'Tuple field [2] required by space format is missing'
    key_def = key_def_lib.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
        {type = 'string', fieldno = 3},
    })
    ok, err = pcall(key_def.extract_key, key_def,
        box.tuple.new({'foo'}))
    testcase:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 2)')

    -- Same as before, but with another key def options:
    --
    -- * is_nullable = true;
    -- * has_optional_parts = false.
    exp_err = 'Tuple field [2] required by space format is missing'
    key_def = key_def_lib.new({
        {type = 'string', fieldno = 1, is_nullable = true},
        {type = 'string', fieldno = 2},
    })
    ok, err = pcall(key_def.extract_key, key_def,
        box.tuple.new({'foo'}))
    testcase:is_deeply({ok, tostring(err)}, {false, exp_err},
        'short tuple with a non-nullable part (case 3)')

    -- A tuple has a field that does not match corresponding key
    -- part type.
    exp_err = 'Supplied key type of part 2 does not match index ' ..
                    'part type: expected string'
    key_def = key_def_lib.new({
        {type = 'string', fieldno = 1},
        {type = 'string', fieldno = 2},
        {type = 'string', fieldno = 3},
    })
    ok, err = pcall(key_def.extract_key, key_def, {'one', 'two', 3})
    testcase:is_deeply({ok, tostring(err)}, {false, exp_err},
        'wrong field type')

    key_def = key_def_lib.new({
        {type = 'number', fieldno = 1, path='a'},
        {type = 'number', fieldno = 1, path='b'},
        {type = 'number', fieldno = 1, path='c', is_nullable=true},
        {type = 'number', fieldno = 3, is_nullable=true},
    })
    ok, err = pcall(key_def.extract_key, key_def,
                          box.tuple.new({1, 1, 22}))
    testcase:is_deeply({ok, tostring(err)},
                {false, 'Tuple field [1]a required by space format is missing'},
                'invalid JSON structure')
    testcase:is_deeply(key_def:extract_key({{a=1, b=2}, 1}):totable(),
                   {1, 2, box.NULL, box.NULL},
                   'tuple with optional parts - case 1')
    testcase:is_deeply(key_def:extract_key({{a=1, b=2, c=3}, 1}):totable(),
                   {1, 2, 3, box.NULL},
                   'tuple with optional parts - case 2')
    testcase:is_deeply(key_def:extract_key({{a=1, b=2}, 1, 3}):totable(),
                   {1, 2, box.NULL, 3},
                   'tuple with optional parts - case 3')
end)

-- Case: compare().
test:test('compare()', function(testcase)
    testcase:plan(8)

    local key_def_a = key_def_lib.new({
        {type = 'unsigned', fieldno = 1},
    })
    local key_def_b = key_def_lib.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local tuple_a = box.tuple.new({1, 1, 22})
    local tuple_b = box.tuple.new({2, 1, 11})
    local tuple_c = box.tuple.new({3, 1, 22})

    testcase:is(key_def_a:compare(tuple_b, tuple_a), 1,
            'case 1: great (tuple argument)')
    testcase:is(key_def_a:compare(tuple_b, tuple_c), -1,
            'case 2: less (tuple argument)')
    testcase:is(key_def_b:compare(tuple_b, tuple_a), -1,
            'case 3: less (tuple argument)')
    testcase:is(key_def_b:compare(tuple_a, tuple_c), 0,
            'case 4: equal (tuple argument)')

    testcase:is(key_def_a:compare(tuple_b:totable(), tuple_a:totable()), 1,
            'case 1: great (table argument)')
    testcase:is(key_def_a:compare(tuple_b:totable(), tuple_c:totable()), -1,
            'case 2: less (table argument)')
    testcase:is(key_def_b:compare(tuple_b:totable(), tuple_a:totable()), -1,
            'case 3: less (table argument)')
    testcase:is(key_def_b:compare(tuple_a:totable(), tuple_c:totable()), 0,
            'case 4: equal (table argument)')
end)

-- Case: compare_with_key().
test:test('compare_with_key()', function(testcase)
    testcase:plan(2)

    local key_def_b = key_def_lib.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    local key = {1, 22}
    testcase:is(key_def_b:compare_with_key(tuple_a:totable(), key), 0, 'table')

    key = box.tuple.new({1, 22})
    testcase:is(key_def_b:compare_with_key(tuple_a, key), 0, 'tuple')
end)

-- Case: totable().
test:test('totable()', function(testcase)
    testcase:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local key_def_a = key_def_lib.new(parts_a)
    local key_def_b = key_def_lib.new(parts_b)

    local exp = set_key_part_defaults(parts_a)
    testcase:is_deeply(key_def_a:totable(), exp, 'case 1')

    exp = set_key_part_defaults(parts_b)
    testcase:is_deeply(key_def_b:totable(), exp, 'case 2')
end)

-- Case: __serialize().
test:test('__serialize()', function(testcase)
    testcase:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local key_def_a = key_def_lib.new(parts_a)
    local key_def_b = key_def_lib.new(parts_b)

    local exp = set_key_part_defaults(parts_a)
    testcase:is(json.encode(key_def_a), json.encode(exp), 'case 1')

    exp = set_key_part_defaults(parts_b)
    testcase:is(json.encode(key_def_b), json.encode(exp), 'case 2')
end)

-- Case: tostring().
test:test('tostring()', function(testcase)
    testcase:plan(2)

    local parts_a = {
        {type = 'unsigned', fieldno = 1}
    }
    local parts_b = {
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    }
    local key_def_a = key_def_lib.new(parts_a)
    local key_def_b = key_def_lib.new(parts_b)

    local exp = '<struct key_def &>'
    testcase:is(tostring(key_def_a), exp, 'case 1')
    testcase:is(tostring(key_def_b), exp, 'case 2')
end)

-- Case: merge().
test:test('merge()', function(testcase)
    testcase:plan(6)

    local key_def_a = key_def_lib.new({
        {type = 'unsigned', fieldno = 1},
    })
    local key_def_b = key_def_lib.new({
        {type = 'number', fieldno = 2},
        {type = 'number', fieldno = 3},
    })
    local key_def_c = key_def_lib.new({
        {type = 'scalar', fieldno = 2},
        {type = 'scalar', fieldno = 1},
        {type = 'string', fieldno = 4, is_nullable = true},
    })
    local tuple_a = box.tuple.new({1, 1, 22})

    local key_def_ab = key_def_a:merge(key_def_b)
    local exp_parts = fun.iter(key_def_a:totable())
        :chain(fun.iter(key_def_b:totable())):totable()
    testcase:is_deeply(key_def_ab:totable(), exp_parts,
        'case 1: verify with :totable()')
    testcase:is_deeply(key_def_ab:extract_key(tuple_a):totable(), {1, 1, 22},
        'case 1: verify with :extract_key()')

    local key_def_ba = key_def_b:merge(key_def_a)
    exp_parts = fun.iter(key_def_b:totable())
        :chain(fun.iter(key_def_a:totable())):totable()
    testcase:is_deeply(key_def_ba:totable(), exp_parts,
        'case 2: verify with :totable()')
    testcase:is_deeply(key_def_ba:extract_key(tuple_a):totable(), {1, 22, 1},
        'case 2: verify with :extract_key()')

    -- Intersecting parts + NULL parts.
    local key_def_cb = key_def_c:merge(key_def_b)
    exp_parts = key_def_c:totable()
    exp_parts[#exp_parts + 1] = {type = 'number', fieldno = 3,
        is_nullable = false}
    testcase:is_deeply(key_def_cb:totable(), exp_parts,
        'case 3: verify with :totable()')
    testcase:is_deeply(key_def_cb:extract_key(tuple_a):totable(),
        {1, 1, box.NULL, 22}, 'case 3: verify with :extract_key()')
end)

os.exit(test:check() and 0 or 1)
