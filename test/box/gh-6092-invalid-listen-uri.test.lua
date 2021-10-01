test_run = require('test_run').new()
netbox = require('net.box')
fio = require('fio')
fiber = require('fiber')
errinj = box.error.injection

-- Check that an invalid listening uri
-- does not make tarantool blind.
bad_uri = "baduribaduri:1"
old_listen = box.cfg.listen
conn = netbox.connect(old_listen)
assert(conn:ping())
box.cfg({ listen = bad_uri })
assert(conn:ping())
assert(fio.path.exists(old_listen))
assert(box.cfg.listen == old_listen)

-- Check that failure in listen does
-- not make tarantool blind and not
-- leads to unreleased resources.
errinj.set("ERRINJ_IPROTO_CFG_LISTEN", true)
new_listen = old_listen .. "A"
conn = netbox.connect(old_listen)
assert(conn:ping())
box.cfg({ listen = new_listen })
test_run:wait_cond(function() return fio.path.exists(old_listen) end)
test_run:wait_cond(function() return not fio.path.exists(new_listen) end)
assert(conn:ping())
assert(box.cfg.listen == old_listen)
errinj.set("ERRINJ_IPROTO_CFG_LISTEN", false)
