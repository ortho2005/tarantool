CREATE TABLE t1 (a INT PRIMARY KEY)
CREATE TABLE t2 (a INT PRIMARY KEY)

-- Names of columns can be duplicated.
SELECT * FROM (SELECT * FROM t1, t2)

-- Make sure that a view with duplicated column names
-- can't be created.
CREATE VIEW v AS SELECT * FROM t1, t2
CREATE VIEW v AS SELECT * FROM t1, (SELECT * FROM t2)