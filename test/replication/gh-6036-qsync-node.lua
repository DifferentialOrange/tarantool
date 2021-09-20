local INSTANCE_ID = string.match(arg[0], "gh%-6036%-qsync%-(.+)%.lua")

local function unix_socket(name)
    return "unix/:./" .. name .. '.sock';
end

require('console').listen(os.getenv('ADMIN'))

local box_cfg_common = {
        listen                      = unix_socket(INSTANCE_ID),
        replication                 = {
            unix_socket("master"),
            unix_socket("replica1"),
            unix_socket("replica2"),
        },
        replication_connect_quorum  = 1,
        replication_synchro_quorum  = 1,
        replication_synchro_timeout = 10000,
}

if INSTANCE_ID == "master" then
    box_cfg_common['election_mode'] = "manual"
    box.cfg(box_cfg_common)
elseif INSTANCE_ID == "replica1" then
    box_cfg_common['election_mode'] = "manual"
    box.cfg(box_cfg_common)
else
    assert(INSTANCE_ID == "replica2")
    box_cfg_common['election_mode'] = "manual"
    box.cfg(box_cfg_common)
end

box.once("bootstrap", function()
    box.schema.user.grant('guest', 'super')
end)
