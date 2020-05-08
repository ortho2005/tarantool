#!/usr/bin/env tarantool
box.load_cfg()
-- testing start-up script
require("math").floor

--
-- Access to box.cfg from start-up script
--

local box_cfg = box.cfg()

local function print_config()
	return box_cfg
end


--
-- Test for bug #977898
-- Insert from detached fiber
--

local function do_insert()
    box.fiber.detach()
    box.space[0]:insert{1, 2, 4, 8}
end

local space = box.schema.create_space('tweedledum', { id = 0 })
space:create_index('primary', { type = 'hash' })

local fiber = box.fiber.create(do_insert)
box.fiber.resume(fiber)

--
-- Test insert from start-up script
--

space:insert{2, 4, 8, 16}

--
-- A test case for https://github.com/tarantool/tarantool/issues/53
--

assert (require ~= nil)
box.fiber.sleep(0.0)
assert (require ~= nil)
