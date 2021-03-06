env = require('test_run')
test_run = env.new()

--
-- gh-2783
-- A ddl operation shoud fail before trying to lock a ddl latch
-- in a multi-statement transaction.
-- If operation tries to lock already an locked latch then the
-- current transaction will be silently rolled back under our feet.
-- This is confusing. So check for multi-statement transaction
-- before locking the latch.
--
test_latch = box.schema.space.create('test_latch')
_ = test_latch:create_index('primary', {unique = true, parts = {1, 'unsigned'}})
fiber = require('fiber')
c = fiber.channel(1)
test_run:cmd("setopt delimiter ';'")
_ = fiber.create(function()
    test_latch:create_index("sec", {unique = true, parts = {2, 'unsigned'}})
    c:put(true)
end);

-- Should be Ok for now
box.begin()
    test_latch:create_index("sec2", {unique = true, parts = {2, 'unsigned'}})
box.commit();
test_run:cmd("setopt delimiter ''");
-- Explicitly roll back the transaction in multi-statement,
-- which hasn't finished due to DDL error
box.rollback()

_ = c:get()
test_latch:drop() -- this is where everything stops
