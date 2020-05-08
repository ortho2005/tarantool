#!/usr/bin/env tarantool

local function on_gc()
end;

local function test_finalizers()
    local result = {}
    local i = 1
    local ffi = require('ffi')
    while true do
        local result[i] = ffi.gc(ffi.cast('void *', 0), on_gc)
        i = i + 1
    end
end;

test_finalizers()
test_finalizers()
