local schema = require('internal.config.utils.schema')
local tarantool = require('tarantool')
local compat = require('compat')
local uuid = require('uuid')
local urilib = require('uri')

-- List of annotations:
--
-- * enterprise_edition (boolean)
--
--   Available only in Tarantool Enterprise Edition.
--
-- * default (any)
--
--   Default value.
--
-- * scope ('global', 'group', 'replicaset', 'instance')
--
--   A place of an instance config option in the cluster config
--   hierarchy.
--
-- * box_cfg (string)
--
--   A name of the corresponding box.cfg() option.
--
-- * box_cfg_nondynamic (boolean)
--
--   `true` if the option can only be set at first box.cfg() call
--   and cannot be changed by a subsequent box.cfg() call.
--
-- * allowed_values
--
--   A list of allowed values.
--
-- * mkdir (boolean)
--
--   Create the given directory before box.cfg().
--
-- * mk_parent_dir (boolean)
--
--   Create a parent directory for the given file before box.cfg().

local CONFIG_VERSION = 'dev'

-- Any configuration data should contain a version of the config
-- schema for which it is written.
--
-- However, it is allowed only in the global scope of the cluster
-- config and in the instance config.
--
-- * In the instance config: must be present.
--
--   TODO: This check is disabled for the early config schema
--   version, because the schema is often changed and there is no
--   schema evolution support yet.
-- * In the cluster config: must be present in the global scope.
--
--   TODO: This check is disabled as well, see above.
-- * In the cluster config: must not be present in the other
--   scopes (group, replicaset, instance).
-- * If present, must correspond to one of supported config
--   versions, but is it validated by the config.version schema
--   node definition.
local function validate_config_version(data, w)
    -- scope == nil means that it is the instance config.
    local scope = w.schema.scope
    if scope == nil or scope == 'global' then
        -- Must be present.
        if data.config == nil or data.config.version == nil then
            -- TODO: Enable this check closer to 3.0.0 release.
            -- w.error('config.version is mandatory')
            return
        end
    else
        -- Must not be present.
        assert(scope == 'group' or scope == 'replicaset' or scope == 'instance')
        if data.config ~= nil and data.config.version ~= nil then
            w.error('config.version must not be present in the %s scope', scope)
        end
    end
end

-- Verify that replication.failover option is not present in the
-- instance scope of the cluster config.
local function validate_replication_failover(data, w)
    -- scope == nil means that it is the instance config.
    local scope = w.schema.scope

    -- There is no much sense to set the failover option for a
    -- particular instance, not the whole replicaset. So, the
    -- option is forbidden for the instance scope of the cluster
    -- config.
    --
    -- However, it is allowed for the instance config to accept an
    -- instantiated cluster config as valid.
    if scope ~= 'instance' then
        return
    end

    if data.replication ~= nil and data.replication.failover ~= nil then
        w.error('replication.failover must not be present in the %s scope',
            scope)
    end
end

local function validate_outmost_record(data, w)
    -- Ensure that the function is called for the outmost record
    -- of the instance_config schema, where the scope is present
    -- in the cluster config.
    assert(w.schema.config_version ~= nil)

    validate_config_version(data, w)
    validate_replication_failover(data, w)
end

local function enterprise_edition_validate(data, w)
    -- OK if we're on Tarantool EE.
    if tarantool.package == 'Tarantool Enterprise' then
        return
    end

    assert(tarantool.package == 'Tarantool')

    -- OK, if the value is nil or box.NULL.
    if data == nil then
        return
    end

    -- NB: Let's fail the validation for an empty table, because
    -- otherwise we will get a less descriptive error from a lower
    -- level API. For example, box.cfg({wal_ext = {}}) on Tarantool
    -- Community Edition says the following:
    --
    -- > Incorrect value for option 'wal_ext': unexpected option

    w.error('This configuration parameter is available only in Tarantool ' ..
        'Enterprise Edition')
end

local function enterprise_edition_apply_default_if(_data, _w)
    return tarantool.package == 'Tarantool Enterprise'
end

-- Available only in Tarantool Enterprise Edition.
local function enterprise_edition(schema_node)
    schema_node.enterprise_edition = true
    schema_node.validate = enterprise_edition_validate
    schema_node.apply_default_if = enterprise_edition_apply_default_if
    return schema_node
end

local function validate_uuid_str(data, w)
    if uuid.fromstr(data) == nil then
        w.error('Unable to parse the value as a UUID: %q', data)
    end
    if data == uuid.NULL:str() then
        w.error('nil UUID is reserved')
    end
end

-- Accepts an uri object (one produced by urilib.parse()).
--
-- Performs several checks regarding ability to use the URI to
-- create a client socket. IOW, to call connect() on it.
--
-- The function returns `true` if the URI is OK to connect and
-- `false, err` otherwise.
--
-- If the URI doesn't fit the given criteria an error is raised.
-- The function returns nothing otherwise.
--
-- The following checks are performed:
--
-- * INADDR_ANY IPv4 address (0.0.0.0) or in6addr_any IPv6 address
--   (::) in the host part of the URI.
--
--   It means 'bind to all interfaces' for the bind() call, but it
--   has no meaning at the connect() call on a client.
-- * Zero TCP port (service part of the URI).
--
--   It means 'bind to a random free port' for the bind() call,
--   but it has no meaning at the connect() call on a client.
local function uri_is_suitable_to_connect(_, uri)
    assert(uri ~= nil)

    if uri.ipv4 == '0.0.0.0' then
        return false, 'INADDR_ANY (0.0.0.0) cannot be used to create ' ..
            'a client socket'
    end
    if uri.ipv6 == '::' then
        return false, 'in6addr_any (::) cannot be used to create a client ' ..
            'socket'
    end
    if uri.service == '0' then
        return false, 'An URI with zero port cannot be used to create ' ..
            'a client socket'
    end

    return true
end

local function advertise_peer_uri_validate(data, w)
    -- Accept the special syntax user@ or user:pass@.
    --
    -- It means using iproto.listen value to connect and using the
    -- given user and password.
    --
    -- If the password is not given, it is extracted from the
    -- `credentials` section of the config.
    if data:endswith('@') then
        return
    end

    -- Substitute variables with placeholders to don't confuse the
    -- URI parser with the curly brackets.
    data = data:gsub('{{ *.- *}}', 'placeholder')

    local uri, err = urilib.parse(data)
    if uri == nil then
        if data:find(',') then
            w.error('A single URI is expected, not a list of URIs')
        end
        w.error('Unable to parse an URI: %s', err)
    end
    local ok, err = uri_is_suitable_to_connect(nil, uri)
    if not ok then
        w.error(err)
    end

    -- The return value is ignored by schema.lua, but useful in
    -- iproto.advertise.client validation.
    return uri
end

return schema.new('instance_config', schema.record({
    config = schema.record({
        version = schema.enum({
            CONFIG_VERSION,
        }),
        reload = schema.enum({
            'auto',
            'manual',
        }, {
            default = 'auto',
        }),
        -- Defaults can't be set there, because the `validate`
        -- annotation expects either no data or data with existing
        -- prefix field. The prefix field has no default. So,
        -- applying defaults to an empty data would make the data
        -- invalid.
        etcd = enterprise_edition(schema.record({
            prefix = schema.scalar({
                type = 'string',
                validate = function(data, w)
                    if not data:startswith('/') then
                        w.error(('config.etcd.prefix should be a path alike ' ..
                            'value, got %q'):format(data))
                    end
                end,
            }),
            endpoints = schema.array({
                items = schema.scalar({
                    type = 'string',
                }),
            }),
            username = schema.scalar({
                type = 'string',
            }),
            password = schema.scalar({
                type = 'string',
            }),
            http = schema.record({
                request = schema.record({
                    timeout = schema.scalar({
                        type = 'number',
                        -- default = 0.3 is applied right in the
                        -- etcd source. See a comment above
                        -- regarding defaults in config.etcd.
                    }),
                    unix_socket = schema.scalar({
                        type = 'string',
                    }),
                }),
            }),
            ssl = schema.record({
                ssl_key = schema.scalar({
                    type = 'string',
                }),
                ca_path = schema.scalar({
                    type = 'string',
                }),
                ca_file = schema.scalar({
                    type = 'string',
                }),
                verify_peer = schema.scalar({
                    type = 'boolean',
                }),
                verify_host = schema.scalar({
                    type = 'boolean',
                }),
            }),
        }, {
            validate = function(data, w)
                -- No config.etcd section at all -- OK.
                if data == nil or next(data) == nil then
                    return
                end
                -- There is some data -- the prefix should be there.
                if data.prefix == nil then
                    w.error('No config.etcd.prefix provided')
                end
            end,
        })),
    }),
    process = schema.record({
        strip_core = schema.scalar({
            type = 'boolean',
            box_cfg = 'strip_core',
            box_cfg_nondynamic = true,
            default = true,
        }),
        coredump = schema.scalar({
            type = 'boolean',
            box_cfg = 'coredump',
            box_cfg_nondynamic = true,
            default = false,
        }),
        background = schema.scalar({
            type = 'boolean',
            box_cfg = 'background',
            box_cfg_nondynamic = true,
            default = false,
        }),
        title = schema.scalar({
            type = 'string',
            box_cfg = 'custom_proc_title',
            default = 'tarantool - {{ instance_name }}',
        }),
        username = schema.scalar({
            type = 'string',
            box_cfg = 'username',
            box_cfg_nondynamic = true,
            default = box.NULL,
        }),
        work_dir = schema.scalar({
            type = 'string',
            box_cfg = 'work_dir',
            box_cfg_nondynamic = true,
            default = box.NULL,
        }),
        pid_file = schema.scalar({
            type = 'string',
            box_cfg = 'pid_file',
            box_cfg_nondynamic = true,
            mk_parent_dir = true,
            default = '{{ instance_name }}.pid',
        }),
    }),
    console = schema.record({
        enabled = schema.scalar({
            type = 'boolean',
            default = true,
        }),
        socket = schema.scalar({
            type = 'string',
            default = '{{ instance_name }}.control',
        }),
    }),
    fiber = schema.record({
        io_collect_interval = schema.scalar({
            type = 'number',
            box_cfg = 'io_collect_interval',
            default = box.NULL,
        }),
        too_long_threshold = schema.scalar({
            type = 'number',
            box_cfg = 'too_long_threshold',
            default = 0.5,
        }),
        worker_pool_threads = schema.scalar({
            type = 'number',
            box_cfg = 'worker_pool_threads',
            default = 4,
        }),
        slice = schema.record({
            warn = schema.scalar({
                type = 'number',
                default = 0.5,
            }),
            err = schema.scalar({
                type = 'number',
                default = 1,
            }),
        }),
        top = schema.record({
            enabled = schema.scalar({
                type = 'boolean',
                default = false,
            }),
        }),
    }),
    log = schema.record({
        -- The logger destination is handled separately in the
        -- box_cfg applier, so there are no explicit box_cfg and
        -- box_cfg_nondynamic annotations.
        --
        -- The reason is that there is no direct-no-transform
        -- mapping from, say, `log.file` to `box_cfg.log`.
        -- The applier should add the `file:` prefix.
        to = schema.enum({
            'stderr',
            'file',
            'pipe',
            'syslog',
        }, {
            default = 'stderr',
        }),
        file = schema.scalar({
            type = 'string',
            default = '{{ instance_name }}.log',
        }),
        pipe = schema.scalar({
            type = 'string',
            default = box.NULL,
        }),
        syslog = schema.record({
            identity = schema.scalar({
                type = 'string',
                default = 'tarantool',
            }),
            facility = schema.scalar({
                type = 'string',
                default = 'local7',
            }),
            server = schema.scalar({
                type = 'string',
                -- The logger tries /dev/log and then
                -- /var/run/syslog if no server is provided.
                default = box.NULL,
            }),
        }),
        nonblock = schema.scalar({
            type = 'boolean',
            box_cfg = 'log_nonblock',
            box_cfg_nondynamic = true,
            default = false,
        }),
        level = schema.scalar({
            type = 'number, string',
            box_cfg = 'log_level',
            default = 5,
            allowed_values = {
                0, 'fatal',
                1, 'syserror',
                2, 'error',
                3, 'crit',
                4, 'warn',
                5, 'info',
                6, 'verbose',
                7, 'debug',
            },
        }),
        format = schema.enum({
            'plain',
            'json',
        }, {
            box_cfg = 'log_format',
            default = 'plain',
        }),
        -- box.cfg({log_modules = <...>}) replaces the previous
        -- value without any merging.
        --
        -- If a key in this map is removed in the provided
        -- configuration, then it will be removed in the actually
        -- applied configuration.
        --
        -- It is exactly what we need there to make the
        -- configuration independent of previously applied values.
        modules = schema.map({
            key = schema.scalar({
                type = 'string',
            }),
            value = schema.scalar({
                type = 'number, string',
            }),
            box_cfg = 'log_modules',
            -- TODO: This default doesn't work now. It needs
            -- support of non-scalar schema nodes in
            -- <schema object>:map().
            default = box.NULL,
        }),
    }, {
        validate = function(log, w)
            if log.to == 'pipe' and log.pipe == nil then
                w.error('The pipe logger is set by the log.to parameter but ' ..
                    'the command is not set (log.pipe parameter)')
            end
        end,
    }),
    iproto = schema.record({
        -- XXX: listen/advertise are specific: accept a string of
        -- a particular format, a number (port), a table of a
        -- particular format.
        --
        -- Only a string is accepted for now.
        listen = schema.scalar({
            type = 'string',
            box_cfg = 'listen',
            default = box.NULL,
            validate = function(data, w)
                -- Substitute variables with placeholders to don't
                -- confuse the URI parser with the curly brackets.
                data = data:gsub('{{ *.- *}}', 'placeholder')

                local uris, err = urilib.parse_many(data)
                if uris == nil then
                    w.error('Unable to parse an URI/a list of URIs: %s', err)
                end
            end,
        }),
        -- URIs for clients to let them know where to connect.
        --
        -- There are several possibly different URIs:
        --
        -- * client
        --
        --   The informational value for clients. It is not used
        --   in tarantool anyhow (only validated). Contains only
        --   host:port: no user, no password.
        --
        --   Must be suitable to connect (no INADDR_ANY, no
        --   in6addr_any, no zero port).
        --
        --   Note: the host:port part may represent a Unix domain
        --   socket: host = 'unix/', port = '/path/to/socket'.
        --
        -- * peer
        --
        --   The general purpose peer URI, used for connections
        --   within the cluster (replica -> master, router ->
        --   storage, rebalancer -> storage).
        --
        --   Usually points to a user with the 'replication' role.
        --
        -- * sharding
        --
        --   The URI for router and rebalancer.
        --
        --   If unset, the general peer URI should be used.
        --
        -- The iproto.advertise.{peer,sharding} options have the
        -- following syntax variants:
        --
        -- 1. user@
        -- 2. user:pass@
        -- 3. user@host:port
        -- 4. host:port
        --
        -- Note: the host:port part may represent a Unix domain
        -- socket: host = 'unix/', port = '/path/to/socket'.
        --
        -- If there is no host:port (1, 2), it is to be looked in
        -- iproto.listen.
        --
        -- If there is a user, but no password (1, 3), the
        -- password is to be looked in the `credentials` section
        -- of the configuration (except user 'guest', which can't
        -- have a password).
        advertise = schema.record({
            client = schema.scalar({
                type = 'string',
                default = box.NULL,
                validate = function(data, w)
                    -- Re-use peer URI validation code, but add
                    -- several extra constraints.
                    local uri = advertise_peer_uri_validate(data, w)

                    if data:endswith('@') then
                        w.error('user@ and user:pass@ syntax is not ' ..
                            'accepted by iproto.advertise.client option: ' ..
                            'only host:port is considered valid')
                    end

                    if uri.login ~= nil or uri.password ~= nil then
                        w.error('user@host:port and user:pass@host:port ' ..
                            'syntax is not accepted by iproto.advertise.' ..
                            'client option: only host:port is considered valid')
                    end
                end,
            }),
            peer = schema.scalar({
                type = 'string',
                default = box.NULL,
                validate = advertise_peer_uri_validate,
            }),
            sharding = schema.scalar({
                type = 'string',
                default = box.NULL,
                validate = advertise_peer_uri_validate,
            }),
        }),
        threads = schema.scalar({
            type = 'integer',
            box_cfg = 'iproto_threads',
            box_cfg_nondynamic = true,
            default = 1,
        }),
        net_msg_max = schema.scalar({
            type = 'integer',
            box_cfg = 'net_msg_max',
            default = 768,
        }),
        readahead = schema.scalar({
            type = 'integer',
            box_cfg = 'readahead',
            default = 16320,
        }),
    }),
    database = schema.record({
        instance_uuid = schema.scalar({
            type = 'string',
            box_cfg = 'instance_uuid',
            default = box.NULL,
            validate = validate_uuid_str,
        }),
        replicaset_uuid = schema.scalar({
            type = 'string',
            box_cfg = 'replicaset_uuid',
            default = box.NULL,
            validate = validate_uuid_str,
        }),
        hot_standby = schema.scalar({
            type = 'boolean',
            box_cfg = 'hot_standby',
            box_cfg_nondynamic = true,
            default = false,
        }),
        -- Applied to box_cfg.read_only.
        --
        -- The effective default depends on amount of instances in
        -- a replicaset.
        --
        -- A singleton instance (the only instance in the
        -- replicaset) is in the 'rw' mode by default.
        --
        -- If the replicaset contains several (more than one)
        -- instances, the default is 'ro'.
        mode = schema.enum({
            'ro',
            'rw',
        }, {
            default = box.NULL,
        }),
        txn_timeout = schema.scalar({
            type = 'number',
            box_cfg = 'txn_timeout',
            default = 365 * 100 * 86400,
        }),
        txn_isolation = schema.enum({
            'read-committed',
            'read-confirmed',
            'best-effort',
        }, {
            box_cfg = 'txn_isolation',
            default = 'best-effort',
        }),
        use_mvcc_engine = schema.scalar({
            type = 'boolean',
            box_cfg = 'memtx_use_mvcc_engine',
            box_cfg_nondynamic = true,
            default = false,
        }),
    }),
    sql = schema.record({
        cache_size = schema.scalar({
            type = 'integer',
            box_cfg = 'sql_cache_size',
            default = 5 * 1024 * 1024,
        }),
    }),
    memtx = schema.record({
        memory = schema.scalar({
            type = 'integer',
            box_cfg = 'memtx_memory',
            default = 256 * 1024 * 1024,
        }),
        allocator = schema.enum({
            'small',
            'system',
        }, {
            box_cfg = 'memtx_allocator',
            box_cfg_nondynamic = true,
            default = 'small',
        }),
        slab_alloc_granularity = schema.scalar({
            type = 'integer',
            box_cfg = 'slab_alloc_granularity',
            box_cfg_nondynamic = true,
            default = 8,
        }),
        slab_alloc_factor = schema.scalar({
            type = 'number',
            box_cfg = 'slab_alloc_factor',
            box_cfg_nondynamic = true,
            default = 1.05,
        }),
        min_tuple_size = schema.scalar({
            type = 'integer',
            box_cfg = 'memtx_min_tuple_size',
            box_cfg_nondynamic = true,
            default = 16,
        }),
        max_tuple_size = schema.scalar({
            type = 'integer',
            box_cfg = 'memtx_max_tuple_size',
            default = 1024 * 1024,
        }),
    }),
    vinyl = schema.record({
        bloom_fpr = schema.scalar({
            type = 'number',
            box_cfg = 'vinyl_bloom_fpr',
            box_cfg_nondynamic = true,
            default = 0.05,
        }),
        cache = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_cache',
            default = 128 * 1024 * 1024,
        }),
        defer_deletes = schema.scalar({
            type = 'boolean',
            box_cfg = 'vinyl_defer_deletes',
            default = false,
        }),
        dir = schema.scalar({
            type = 'string',
            box_cfg = 'vinyl_dir',
            box_cfg_nondynamic = true,
            mkdir = true,
            default = '{{ instance_name }}',
        }),
        max_tuple_size = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_max_tuple_size',
            default = 1024 * 1024,
        }),
        memory = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_memory',
            default = 128 * 1024 * 1024,
        }),
        page_size = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_page_size',
            box_cfg_nondynamic = true,
            default = 8 * 1024,
        }),
        range_size = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_range_size',
            box_cfg_nondynamic = true,
            default = box.NULL,
        }),
        read_threads = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_read_threads',
            box_cfg_nondynamic = true,
            default = 1,
        }),
        run_count_per_level = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_run_count_per_level',
            box_cfg_nondynamic = true,
            default = 2,
        }),
        run_size_ratio = schema.scalar({
            type = 'number',
            box_cfg = 'vinyl_run_size_ratio',
            box_cfg_nondynamic = true,
            default = 3.5,
        }),
        timeout = schema.scalar({
            type = 'number',
            box_cfg = 'vinyl_timeout',
            default = 60,
        }),
        write_threads = schema.scalar({
            type = 'integer',
            box_cfg = 'vinyl_write_threads',
            box_cfg_nondynamic = true,
            default = 2,
        }),
    }),
    wal = schema.record({
        dir = schema.scalar({
            type = 'string',
            box_cfg = 'wal_dir',
            box_cfg_nondynamic = true,
            mkdir = true,
            default = '{{ instance_name }}',
        }),
        mode = schema.enum({
            'none',
            'write',
            'fsync',
        }, {
            box_cfg = 'wal_mode',
            box_cfg_nondynamic = true,
            default = 'write',
        }),
        max_size = schema.scalar({
            type = 'integer',
            box_cfg = 'wal_max_size',
            box_cfg_nondynamic = true,
            default = 256 * 1024 * 1024,
        }),
        dir_rescan_delay = schema.scalar({
            type = 'number',
            box_cfg = 'wal_dir_rescan_delay',
            default = 2,
        }),
        queue_max_size = schema.scalar({
            type = 'integer',
            box_cfg = 'wal_queue_max_size',
            default = 16 * 1024 * 1024,
        }),
        cleanup_delay = schema.scalar({
            type = 'number',
            box_cfg = 'wal_cleanup_delay',
            default = 4 * 3600,
        }),
        -- box.cfg({wal_ext = <...>}) replaces the previous
        -- value without any merging. See explanation why it is
        -- important in the log.modules description.
        ext = enterprise_edition(schema.record({
            old = schema.scalar({
                type = 'boolean',
                -- TODO: This default is applied despite the outer
                -- apply_default_if, because the annotation has no
                -- effect on child schema nodes.
                --
                -- This default is purely informational: lack of the
                -- value doesn't break configuration applying
                -- idempotence.
                -- default = false,
            }),
            new = schema.scalar({
                type = 'boolean',
                -- TODO: See wal.ext.old.
                -- default = false,
            }),
            spaces = schema.map({
                key = schema.scalar({
                    type = 'string',
                }),
                value = schema.record({
                    old = schema.scalar({
                        type = 'boolean',
                        default = false,
                    }),
                    new = schema.scalar({
                        type = 'boolean',
                        default = false,
                    }),
                }),
            }),
        }, {
            box_cfg = 'wal_ext',
            -- TODO: This default doesn't work now. It needs
            -- support of non-scalar schema nodes in
            -- <schema object>:map().
            default = box.NULL,
        })),
    }),
    snapshot = schema.record({
        dir = schema.scalar({
            type = 'string',
            box_cfg = 'memtx_dir',
            box_cfg_nondynamic = true,
            mkdir = true,
            default = '{{ instance_name }}',
        }),
        by = schema.record({
            interval = schema.scalar({
                type = 'number',
                box_cfg = 'checkpoint_interval',
                default = 3600,
            }),
            wal_size = schema.scalar({
                type = 'integer',
                box_cfg = 'checkpoint_wal_threshold',
                default = 1e18,
            }),
        }),
        count = schema.scalar({
            type = 'integer',
            box_cfg = 'checkpoint_count',
            default = 2,
        }),
        snap_io_rate_limit = schema.scalar({
            type = 'number',
            box_cfg = 'snap_io_rate_limit',
            default = box.NULL,
        }),
    }),
    replication = schema.record({
        failover = schema.enum({
            -- No failover ('off').
            --
            -- The leadership in replicasets is controlled using
            -- the database.mode options. It is allowed to have
            -- several writable instances in a replicaset.
            --
            -- The default database.mode is determined as follows.
            --
            -- * 1 instance in a replicaset: 'rw'.
            -- * >1 instances in a replicaset: 'ro'.
            'off',
            -- Manual failover ('manual').
            --
            -- The leadership is controlled using the 'leader'
            -- option of a replicaset. Master-master configuration
            -- is forbidden.
            --
            -- The database.mode option can't be set directly in
            -- the manual failover mode. The leader is configured
            -- in the read-write mode, all the other instances are
            -- read-only.
            'manual',
            -- Automatic leader election ('election').
            --
            -- Uses a RAFT based algorithm for the leader election.
            --
            -- No database.mode or 'leader' options should be set.
            'election',
        }, {
            default = 'off',
        }),
        -- XXX: needs more validation
        peers = schema.array({
            items = schema.scalar({
                type = 'string',
            }),
            box_cfg = 'replication',
            default = box.NULL,
        }),
        anon = schema.scalar({
            type = 'boolean',
            box_cfg = 'replication_anon',
            default = false,
        }),
        threads = schema.scalar({
            type = 'integer',
            box_cfg = 'replication_threads',
            box_cfg_nondynamic = true,
            default = 1,
        }),
        timeout = schema.scalar({
            type = 'number',
            box_cfg = 'replication_timeout',
            default = 1,
        }),
        synchro_timeout = schema.scalar({
            type = 'number',
            box_cfg = 'replication_synchro_timeout',
            default = 5,
        }),
        connect_timeout = schema.scalar({
            type = 'number',
            box_cfg = 'replication_connect_timeout',
            default = 30,
        }),
        sync_timeout = schema.scalar({
            type = 'number',
            box_cfg = 'replication_sync_timeout',
            default = compat.box_cfg_replication_sync_timeout.default == 'old'
                and 300 or 0,
        }),
        sync_lag = schema.scalar({
            type = 'number',
            box_cfg = 'replication_sync_lag',
            default = 10,
        }),
        synchro_quorum = schema.scalar({
            type = 'string, number',
            box_cfg = 'replication_synchro_quorum',
            default = 'N / 2 + 1',
        }),
        skip_conflict = schema.scalar({
            type = 'boolean',
            box_cfg = 'replication_skip_conflict',
            default = false,
        }),
        election_mode = schema.enum({
            'off',
            'voter',
            'manual',
            'candidate',
        }, {
            box_cfg = 'election_mode',
            -- The effective default is determined depending of
            -- the replication.failover option.
            default = box.NULL,
        }),
        election_timeout = schema.scalar({
            type = 'number',
            box_cfg = 'election_timeout',
            default = 5,
        }),
        election_fencing_mode = schema.enum({
            'off',
            'soft',
            'strict',
        }, {
            box_cfg = 'election_fencing_mode',
            default = 'soft',
        }),
        bootstrap_strategy = schema.enum({
            'auto',
            'config',
            'supervised',
            'legacy',
        }, {
            box_cfg = 'bootstrap_strategy',
            default = 'auto',
        }),
    }),
    -- Unlike other sections, credentials contains the append-only
    -- parameters. It means that deletion of a value from the
    -- config doesn't delete the corresponding user/role/privilege.
    credentials = schema.record({
        roles = schema.map({
            -- Name of the role.
            key = schema.scalar({
                type = 'string',
            }),
            value = schema.record({
                -- Privileges granted to the role.
                privileges = schema.array({
                    items = schema.record({
                        permissions = schema.set({
                            'read',
                            'write',
                            'execute',
                            'create',
                            'alter',
                            'drop',
                            'usage',
                            'session',
                        }),
                        universe = schema.scalar({
                            type = 'boolean',
                        }),
                        -- TODO: It is not possible to grant a
                        -- permission for a non-existing object.
                        -- It blocks ability to set it from a
                        -- config. Disabled for now.
                        --[[
                        spaces = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        functions = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        sequences = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        ]]--
                    }),
                }),
                -- The given role has all the privileges from
                -- these underlying roles.
                roles = schema.array({
                    items = schema.scalar({
                        type = 'string',
                    }),
                }),
            }),
        }),
        users = schema.map({
            -- Name of the user.
            key = schema.scalar({
                type = 'string',
            }),
            -- Parameters of the user.
            value = schema.record({
                password = schema.record({
                    plain = schema.scalar({
                        type = 'string',
                    }),
                    sha1 = schema.scalar({
                        type = 'string',
                    }),
                    sha256 = schema.scalar({
                        type = 'string',
                    }),
                }, {
                    validate = function(password, w)
                        if next(password, next(password)) ~= nil then
                            w.error('Only one of plain, sha1, and sha256 '..
                                    'can appear at the same time.')
                        end
                    end,
                }),
                privileges = schema.array({
                    items = schema.record({
                        permissions = schema.set({
                            'read',
                            'write',
                            'execute',
                            'create',
                            'alter',
                            'drop',
                            'usage',
                            'session',
                        }),
                        universe = schema.scalar({
                            type = 'boolean',
                        }),
                        -- TODO: It is not possible to grant a
                        -- permission for a non-existing object.
                        -- It blocks ability to set it from a
                        -- config. Disabled for now.
                        --[[
                        spaces = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        functions = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        sequences = schema.array({
                            items = schema.scalar({
                                type = 'string',
                            }),
                        }),
                        ]]--
                    }),
                }),
                -- The given user has all the privileges from
                -- these underlying roles.
                roles = schema.array({
                    items = schema.scalar({
                        type = 'string',
                    }),
                }),
            }),
        }),
    }),
    app = schema.record({
        file = schema.scalar({
            type = 'string',
        }),
        module = schema.scalar({
            type = 'string',
        }),
        cfg = schema.map({
            key = schema.scalar({
                type = 'string',
            }),
            value = schema.scalar({
                type = 'any',
            }),
        }),
    }, {
        validate = function(app, w)
            if app.file ~= nil and app.module ~= nil then
                w.error('Fields file and module cannot appear at the same time')
            end
        end,
    }),
}, {
    -- This kind of validation cannot be implemented as the
    -- 'validate' annotation of a particular schema node. There
    -- are two reasons:
    --
    -- * Missed fields are not validated.
    -- * The outmost instance config record is marked with the
    --   'scope' annotation (when the instance config is part of
    --   the cluster config), but this annotation is not easy to
    --   reach from the 'validate' function of a nested schema
    --   node.
    validate = validate_outmost_record,
    -- Store the config schema version right in the outmost schema
    -- node as an annotation. It simplifies accesses from other
    -- code.
    config_version = CONFIG_VERSION,
}), {
    methods = {
        uri_is_suitable_to_connect = uri_is_suitable_to_connect,
    },
})
