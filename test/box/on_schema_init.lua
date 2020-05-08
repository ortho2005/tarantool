#!/usr/bin/env tarantool
local os = require('os')

function test_before_replace_trig(old, new)
    -- return multiple values so that the stack fills earlier.
    return new:update{{'+', 2, 1}}, new:update{{'+', 2, 1}}, new:update{{'+', 2, 1}}, new:update{{'+', 2, 1}}
end

function space_on_replace_trig(old, new)
    if new and new[3] == 'test_on_schema_init' then
        box.on_commit(function()
            box.space.test_on_schema_init:before_replace(test_before_replace_trig)
        end)
    end
end

function on_init_trig()
    box.space._space:on_replace(space_on_replace_trig)
end

box.ctl.on_schema_init(on_init_trig)

box.cfg{
    listen = os.getenv("LISTEN")
}

require('console').listen(os.getenv('ADMIN'))
