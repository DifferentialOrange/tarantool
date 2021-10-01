env = require('test_run')
net_box = require('net.box')
fiber = require('fiber')
test_run = env.new()
test_run:cmd("create server test with script='box/tx_man.lua'")
test_run:cmd(string.format("start server test"))

-- Checks for local transactions
test_run:cmd("switch test")
fiber = require('fiber')

-- Check arguments for 'box.begin'
box.begin(1)
box.begin({timeout = 0})
box.begin({timeout = -1})
box.begin({timeout = "5"})
-- Check new configuration option 'txn_timeout'
box.cfg({txn_timeout = 0})
box.cfg({txn_timeout = -1})
box.cfg({txn_timeout = "5"})

s = box.schema.space.create('test')
_ = s:create_index('pk')
txn_timeout = 0.5
box.cfg({ txn_timeout = txn_timeout })

-- Check that transaction aborted by timeout, which
-- was set by the change of box.cfg.txn_timeout
box.begin()
s:replace({1})
s:select({}) -- [1]
fiber.sleep(txn_timeout  / 2)
s:select({}) -- [1]
fiber.sleep(txn_timeout  / 2 + 0.1)
s:select({}) --[]
s:replace({2})
fiber.yield()
s:select({}) -- []
box.commit() -- Transaction has been aborted by timeout

-- Check that transaction aborted by timeout, which
-- was set by appropriate option in box.begin
box.begin({timeout = txn_timeout})
s:replace({1})
s:select({}) -- [1]
fiber.sleep(txn_timeout  / 2)
s:select({}) -- [1]
fiber.sleep(txn_timeout  / 2 + 0.1)
s:select({}) --[]
s:replace({2})
fiber.yield()
s:select({}) -- []
box.commit() -- Transaction has been aborted by timeout

s:drop()
test_run:cmd("switch default")

test_run:cmd("stop server test")
test_run:cmd("cleanup server test")
test_run:cmd("delete server test")
