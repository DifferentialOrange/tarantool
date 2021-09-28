local t = require('luatest')
local cluster = require('test.luatest_helpers.cluster')

local g = t.group('gh-4669-applier-reconnect')

local function check_follow_master(server)
    return t.assert_equals(
        server:eval('return box.info.replication[1].upstream.status'), 'follow')
end

g.before_each(function()
    g.cluster = cluster:new({})
    g.master = g.cluster:build_server(
        {}, {alias = 'master'}, 'base_instance.lua')
    g.replica = g.cluster:build_server(
        {args={'master'}}, {alias = 'replica'}, 'replica.lua')

    g.cluster:join_server(g.master)
    g.cluster:join_server(g.replica)
    g.cluster:start()
    check_follow_master(g.replica)
end)

g.after_each(function()
    g.cluster:stop()
end)

-- Test that appliers aren't recreated upon replication reconfiguration.
g.test_applier_connection_on_reconfig = function(g)
    g.replica:eval([[
        box.cfg{
            replication = {
                os.getenv("TARANTOOL_LISTEN"),
                box.cfg.replication[1],
            }
        }
    ]])
    check_follow_master(g.replica)
    t.assert_equals(g.master:grep_log("exiting the relay loop"), nil)
end
