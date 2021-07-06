local t = require('luatest')
local log = require('log')
local Cluster =  require('test.luatest_helpers.cluster')
local test_checks = require('test.luatest_helpers.checks')

local pg = t.group('quorum_orphan', {{engine = 'memtx'}, {engine = 'vinyl'}})

pg.before_each(function(cg)
    local engine = cg.params.engine
    cg.cluster = Cluster:new({})
    cg.quorum1 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum1', }, 'quorum.lua', engine)
    cg.quorum2 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum2', }, 'quorum.lua', engine)
    cg.quorum3 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum3', }, 'quorum.lua', engine)

    pcall(log.cfg, {level = 6})

end)

pg.after_each(function(cg)
    cg.cluster.servers = nil
    cg.cluster:stop()
end)

pg.before_test('test_replica_is_orphan_after_restart', function(cg)
    cg.cluster:join_server(cg.quorum1)
    cg.cluster:join_server(cg.quorum2)
    cg.cluster:join_server(cg.quorum3)
    cg.cluster:start({wait_for_readiness = false})
end)

pg.test_replica_is_orphan_after_restart = function(cg)
    -- Stop one replica and try to restart another one.
    -- It should successfully restart, but stay in the
    -- 'orphan' mode, which disables write accesses.
    -- There are three ways for the replica to leave the
    -- 'orphan' mode:
    -- * reconfigure replication
    -- * reset box.cfcg.replication_connect_quorum
    -- * wait until a quorum is formed asynchronously
    test_checks:check_follow_all_master({cg.quorum1, cg.quorum2, cg.quorum3})
    cg.quorum1:stop()
    cg.quorum2:restart({args = {'0.1', '10'}})
    t.assert_equals(cg.quorum2.net_box.state, 'active')
    t.assert_str_matches(
        cg.quorum2:eval('return box.info.status'), 'orphan')
    t.assert_error_msg_content_equals('timed out', function()
            cg.quorum2:eval('return box.ctl.wait_rw(0.001)')
    end)
    t.assert(cg.quorum2:eval('return box.info.ro'))
    t.helpers.retrying({timeout = 20}, function()
        t.assert(cg.quorum2:eval('return box.space.test ~= nil'))
    end)
    t.assert_error_msg_content_equals(
        "Can't modify data because this instance is in read-only mode.",
        function()
            cg.quorum2:eval('return box.space.test:replace{100}')
        end
    )
    cg.quorum2:eval('box.cfg{replication={}}')
    t.assert_str_matches(
        cg.quorum2:eval('return box.info.status'), 'running')
    cg.quorum2:restart({args = {'0.1', '10'}})
    t.assert_equals(cg.quorum2.net_box.state, 'active')
    t.assert_str_matches(
        cg.quorum2:eval('return box.info.status'), 'orphan')
    t.assert_error_msg_content_equals('timed out', function()
            cg.quorum2:eval('return box.ctl.wait_rw(0.001)')
    end)
    t.assert(cg.quorum2:eval('return box.info.ro'))
    t.helpers.retrying({timeout = 10}, function()
        t.assert(cg.quorum2:eval('return box.space.test ~= nil'))
    end)
    t.assert_error_msg_content_equals(
        "Can't modify data because this instance is in read-only mode.",
        function()
            cg.quorum2:eval('return box.space.test:replace{100}')
        end
    )

    cg.quorum2:eval('box.cfg{replication_connect_quorum = 2}')
    cg.quorum2:eval('return box.ctl.wait_rw()')
    t.assert_not(cg.quorum2:eval('return box.info.ro'))
    t.assert_str_matches(
        cg.quorum2:eval('return box.info.status'), 'running')
    cg.quorum2:restart({args = {'0.1', '10'}})
    t.assert_equals(cg.quorum2.net_box.state, 'active')
    t.assert_str_matches(
        cg.quorum2:eval('return box.info.status'), 'orphan')
    t.assert_error_msg_content_equals('timed out', function()
            cg.quorum2:eval('return box.ctl.wait_rw(0.001)')
    end)
    t.assert(cg.quorum2:eval('return box.info.ro'))
    t.helpers.retrying({timeout = 10}, function()
        t.assert(cg.quorum2:eval('return box.space.test ~= nil'))
    end)
    t.assert_error_msg_content_equals(
        "Can't modify data because this instance is in read-only mode.",
        function()
            cg.quorum2:eval('return box.space.test:replace{100}')
        end
    )
    cg.quorum1.args = {'0.1'}
    cg.quorum1:start()
    t.assert_equals(cg.quorum1.net_box.state, 'active',
        'wrong state for server="%s"', cg.quorum1.alias)
    cg.quorum1:eval('return box.ctl.wait_rw()')
    t.assert_not(cg.quorum1:eval('return box.info.ro'))
    t.assert_str_matches(cg.quorum1:eval('return box.info.status'), 'running')

end
