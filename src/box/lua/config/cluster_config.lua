local schema = require('internal.config.utils.schema')
local instance_config = require('internal.config.instance_config')

local function find_instance(_schema, data, instance_name)
    -- Find group, replicaset, instance configuration for the
    -- given instance.
    local groups = data.groups or {}
    for gn, g in pairs(groups) do
        local replicasets = g.replicasets or {}
        for rn, r in pairs(replicasets) do
            local instances = r.instances or {}
            if instances[instance_name] ~= nil then
                return {
                    group = g,
                    replicaset = r,
                    instance = instances[instance_name],
                    group_name = gn,
                    replicaset_name = rn,
                }
            end
        end
    end

    return nil
end

local function instantiate(_schema, data, instance_name)
    -- No topology information provided.
    if data.groups == nil then
        return data
    end

    local found = find_instance(nil, data, instance_name)

    if found == nil then
        local res = table.copy(data)
        res.groups = nil
        return res
    end

    local res = {}
    res = instance_config:merge(res, data)
    res = instance_config:merge(res, found.group)
    res = instance_config:merge(res, found.replicaset)
    res = instance_config:merge(res, found.instance)
    return res
end

-- Construct a record from other records and extra fields.
--
-- record_from_fields({
--     <record foo>
--     <record bar>
--     extra_field_baz = <...>,
--     extra_field_fiz = <...>,
-- })
--
-- It allows to write the cluster config schema in a more readable
-- way.
local function record_from_fields(fields)
    local res = {
        type = 'record',
        fields = {},
        -- <..annotations..>
    }

    for k, v in pairs(fields) do
        if type(k) == 'number' then
            -- Assume that a numeric key contains a record to
            -- copy its fields and annotations into the resulting
            -- record.
            assert(type(v) == 'table')
            assert(v.type == 'record')

            -- Copy fields.
            for kk, vv in pairs(v.fields) do
                assert(res.fields[kk] == nil, 'record_from_fields: duplicate '..
                                              'fields '..tostring(kk))
                res.fields[kk] = vv
            end

            -- Copy annotations.
            for kk, vv in pairs(v) do
                if kk ~= 'fields' and kk ~= 'type' then
                    assert(res[kk] == nil, 'record_from_fields: duplicate '..
                                           'annotations '..tostring(kk))
                    res[kk] = vv
                end
            end
        else
            -- Assume that a string key represents a field name
            -- and the corresponding value contains a schema node
            -- for the field.
            assert(type(k) == 'string')

            -- Copy the field.
            assert(res.fields[k] == nil, 'record_from_fields: duplicate '..
                                         'fields '..tostring(k))
            res.fields[k] = v
        end
    end

    return res
end

--
-- Return the instance configuration schema as a record with the given scope
-- annotation.
--
local function instance_config_with_scope(scope)
    assert(type(instance_config) == 'table')
    assert(type(instance_config.schema) == 'table')
    assert(instance_config.schema.type == 'record')

    local schema = table.copy(instance_config.schema)
    schema.scope = scope
    return schema
end

return schema.new('cluster_config', record_from_fields({
    instance_config_with_scope('global'),
    groups = schema.map({
        key = schema.scalar({type = 'string'}),
        value = record_from_fields({
            instance_config_with_scope('group'),
            replicasets = schema.map({
                key = schema.scalar({type = 'string'}),
                value = record_from_fields({
                    leader = schema.scalar({type = 'string'}),
                    instance_config_with_scope('replicaset'),
                    instances = schema.map({
                        key = schema.scalar({type = 'string'}),
                        value = instance_config_with_scope('instance'),
                    }),
                }),
            }),
        }),
    }),
}), {
    methods = {
        instantiate = instantiate,
        find_instance = find_instance,
    },
})
