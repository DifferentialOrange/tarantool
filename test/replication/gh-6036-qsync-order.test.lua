--
-- gh-6036: verify that terms are locked when we're inside journal
-- write routine, because parallel appliers may ignore the fact that
-- the term is updated already but not yet written leading to data
-- inconsistency.
--
test_run = require('test_run').new()

test_run:cmd('create server master with script="replication/gh-6036-qsync-master.lua"')
test_run:cmd('create server replica1 with script="replication/gh-6036-qsync-replica1.lua"')
test_run:cmd('create server replica2 with script="replication/gh-6036-qsync-replica2.lua"')

test_run:cmd('start server master with wait=False')
test_run:cmd('start server replica1 with wait=False')
test_run:cmd('start server replica2 with wait=False')

test_run:wait_fullmesh({"master", "replica1", "replica2"})

--
-- Create a synchro space on the master node and make
-- sure the write processed just fine.
test_run:switch("master")
box.ctl.promote()
s = box.schema.create_space('test', {is_sync = true})
_ = s:create_index('pk')
s:insert{1}
test_run:switch("replica1")
test_run:wait_cond(function() return box.space.test:get{1} ~= nil end)
test_run:switch("replica2")
test_run:wait_cond(function() return box.space.test:get{1} ~= nil end)

--
-- Drop connection between master and replica1.
test_run:switch("master")
box.cfg({                                   \
    replication = {                         \
        "unix/:./master.sock",              \
        "unix/:./replica2.sock",            \
    },                                      \
})
--
-- Drop connection between replica1 and master.
test_run:switch("replica1")
test_run:wait_cond(function() return box.space.test:get{1} ~= nil end)
box.cfg({                                   \
    replication = {                         \
        "unix/:./replica1.sock",            \
        "unix/:./replica2.sock",            \
    },                                      \
})

--
-- Here we have the following scheme
--
--              replica2 (will be delayed)
--              /     \
--          master    replica1

--
-- Initiate disk delay and remember the max term seen so far.
test_run:switch("replica2")
box.error.injection.set('ERRINJ_WAL_DELAY', true)

--
-- Make replica1 been a leader and start writting data,
-- the PROMOTE request get queued on replica2 and not
-- yet processed, same time INSERT won't complete either
-- waiting for PROMOTE completion first.
test_run:switch("replica1")
box.ctl.promote()
_ = require('fiber').create(function() box.space.test:insert{2} end)

--
-- The master node has no clue that there is a new leader
-- and continue writting data with obsolete term. Since replica2
-- is delayed now the INSERT won't proceed yet but get queued.
test_run:switch("master")
_ = require('fiber').create(function() box.space.test:insert{3} end)

--
-- Finally enable replica2 back. Make sure the data from new replica1
-- leader get writting while old leader's data ignored.
test_run:switch("replica2")
box.error.injection.set('ERRINJ_WAL_DELAY', false)
test_run:wait_cond(function() return box.space.test:get{2} ~= nil end)
box.space.test:select{}

test_run:switch("default")
test_run:cmd('stop server master')
test_run:cmd('stop server replica1')
test_run:cmd('stop server replica2')

test_run:cmd('delete server master')
test_run:cmd('delete server replica1')
test_run:cmd('delete server replica2')
