--
-- gh-4282: synchronous replication. It allows to make certain
-- spaces commit only when their changes are replicated to a
-- quorum of replicas.
--
s = box.schema.create_space('test', {is_sync = true})
s.is_sync
pk = s:create_index('pk')
box.begin() s:insert({1}) s:insert({2}) box.commit()
s:select{}
s:drop()

-- Default is async.
s = box.schema.create_space('test')
s.is_sync
s:drop()
