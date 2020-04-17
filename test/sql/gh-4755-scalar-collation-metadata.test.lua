env = require('test_run')
test_run = env.new()

--
-- gh-4755: Collation in metadata must be displayed as for string
-- filed as for scalar field.
--
test_run:cmd("setopt delimiter ';'");
box.execute([[UPDATE "_session_settings"
                  SET "value" = true
                  WHERE "name" = 'sql_full_metadata';]]);
box.execute([[CREATE TABLE test (a SCALAR COLLATE "unicode_ci" PRIMARY KEY,
                                 b STRING COLLATE "unicode_ci");]]);
box.execute("SELECT * FROM test;");

--
-- Cleanup.
--
box.execute([[UPDATE "_session_settings"
                  SET "value" = false
                  WHERE "name" = 'sql_full_metadata';]]);
box.execute("DROP TABLE test;");
