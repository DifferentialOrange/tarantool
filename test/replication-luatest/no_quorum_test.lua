local t = require('luatest')
local log = require('log')
local Cluster =  require('test.luatest_helpers.cluster')

local pg = t.group('no_quorum', {{engine = 'memtx'}, {engine = 'vinyl'}})

pg.before_each(function(cg)
    cg.cluster = Cluster:new({})
    cg.master = cg.cluster:build_server(
        {args = {},}, {alias = 'master', }, 'base_instance.lua')
    cg.replica = cg.cluster:build_server(
        {args = {},}, {alias = 'no_quorum'}, 'replica_no_quorum.lua')

    pcall(log.cfg, {level = 6})
end)

pg.after_each(function(cg)
    cg.cluster.servers = nil
end)


pg.before_test('test_replication_no_quorum', function(cg)
    cg.cluster:join_server(cg.master)
    cg.cluster:join_server(cg.replica)
    cg.master:start()
    cg.master:eval(
        "return box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})")
    cg.master:eval("space = box.schema.space.create('test', {engine = '" .. cg.params.engine .."'})")
    cg.master:eval("index = space:create_index('primary')")
end)

pg.after_test('test_replication_no_quorum', function(cg)
    cg.cluster:stop()
end)

pg.test_replication_no_quorum = function(cg)
     -- gh-3278: test different replication and replication_connect_quorum configs.
    -- Insert something just to check that replica with quorum = 0 works as expected.

    t.assert_equals(cg.master:eval("return space:insert{1}"), {1})
    cg.replica:start()
    t.assert_equals(
        cg.replica:eval('return box.space.test:select()'), {{1}})
    cg.replica:stop()
    cg.master:eval("local listen = box.cfg.listen")
    cg.master:eval("return box.cfg{listen = ''}")
    cg.replica:start()

    -- Check that replica is able to reconnect, case was broken with earlier quorum "fix".

    cg.master:eval("return box.cfg{listen = os.getenv('TARANTOOL_LISTEN')}")
    t.assert_equals(cg.master:eval("return space:insert{2}"), {2})
    local fiber = require('fiber')
    local vclock = cg.master:eval("return box.info.vclock")
    fiber.sleep(vclock[1])
    t.assert_str_matches(
        cg.replica:eval('return box.info.status'), 'running')
    t.assert_equals(cg.master:eval("return space:select()"), {{1}, {2}})
    t.assert_equals(
        cg.replica:eval('return box.space.test:select()'), {{1}, {2}})

end
