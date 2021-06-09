test_run = require('test_run').new()

NUM_INSTANCES = 2

box.schema.user.grant('guest', 'replication')
box.cfg{replication_synchro_quorum=NUM_INSTANCES}
_ = box.schema.space.create('sync', {is_sync=true})
_ = box.space.sync:create_index('pk')
<<<<<<< HEAD
=======
box.ctl.promote()
-- Testcase body.
test_run:switch('default')
box.space.sync:insert{1} -- success
box.space.sync:insert{2} -- success
box.space.sync:insert{3} -- success
test_run:cmd('switch replica_anon')
box.space.sync:select{} -- 1, 2, 3
-- Testcase cleanup.
test_run:switch('default')
box.space.sync:drop()
>>>>>>> box: introduce `box.ctl.demote`


-- Setup a cluster with anonymous replica
test_run:cmd('create server replica_anon with rpl_master=default,\
              script="replication/anon1.lua"')
test_run:cmd('start server replica_anon')


-- Testcase
box.space.sync:insert{1}    -- error
box.space.sync:insert{3}    -- error
test_run:cmd('switch replica_anon')
box.space.sync:select{}     -- []

-- Testcase cleanup
test_run:switch('default')
box.space.sync:drop()


-- Teardown
test_run:cmd('stop server replica_anon')
test_run:cmd('cleanup server replica_anon')
test_run:cmd('delete server replica_anon')
<<<<<<< HEAD
=======
box.schema.user.revoke('guest', 'replication')
box.cfg{                                                                        \
    replication_synchro_quorum = orig_synchro_quorum,                           \
    replication_synchro_timeout = orig_synchro_timeout,                         \
}
box.ctl.demote()
test_run:cleanup_cluster()
>>>>>>> box: introduce `box.ctl.demote`
