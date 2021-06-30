local ffi = require('ffi')

--[[
    `c-dt` library functions handles properly both positive and negative `dt`
    values, where `dt` is a number of dates since Rata Die date (0001-01-01).

    For better compactness of our typical data in MessagePack stream we shift
    root of our time to the Unix Epoch date (1970-01-01), thus our 0 is
    actually dt = 719163.

    So here is a simple formula how convert our epoch-based seconds to dt values
        dt = (secs / 86400) + 719163
    Where 719163 is an offset of Unix Epoch (1970-01-01) since Rata Die
    (0001-01-01) in dates.
]]

ffi.cdef[[

/* dt_core.h definitions */
typedef int dt_t;

typedef enum {
    DT_MON       = 1,
    DT_MONDAY    = 1,
    DT_TUE       = 2,
    DT_TUESDAY   = 2,
    DT_WED       = 3,
    DT_WEDNESDAY = 3,
    DT_THU       = 4,
    DT_THURSDAY  = 4,
    DT_FRI       = 5,
    DT_FRIDAY    = 5,
    DT_SAT       = 6,
    DT_SATURDAY  = 6,
    DT_SUN       = 7,
    DT_SUNDAY    = 7,
} dt_dow_t;

dt_t   tnt_dt_from_rdn     (int n);
dt_t   tnt_dt_from_ymd     (int y, int m, int d);
void   tnt_dt_to_ymd       (dt_t dt, int *y, int *m, int *d);

dt_dow_t tnt_dt_dow        (dt_t dt);

/* dt_util.h */
int     tnt_dt_days_in_month   (int y, int m);

/* dt_accessor.h */
int     tnt_dt_year         (dt_t dt);
int     tnt_dt_month        (dt_t dt);
int     tnt_dt_doy          (dt_t dt);
int     tnt_dt_dom          (dt_t dt);

/* dt_parse_iso.h definitions */
size_t tnt_dt_parse_iso_zone_lenient(const char *str, size_t len, int *offset);

/* Tarantool functions - datetime.c */
size_t tnt_datetime_to_string(const struct datetime * date, char *buf,
                              ssize_t len);
size_t tnt_datetime_strftime(const struct datetime *date, char *buf,
                             uint32_t len, const char *fmt);
void   tnt_datetime_now(struct datetime *now);

]]

local builtin = ffi.C
local math_modf = math.modf
local math_floor = math.floor

local SECS_PER_DAY     = 86400
local NANOS_PER_SEC    = 1000000000

-- Unix, January 1, 1970, Thursday
local DAYS_EPOCH_OFFSET = 719163
local SECS_EPOCH_OFFSET = DAYS_EPOCH_OFFSET * SECS_PER_DAY
local TOSTRING_BUFSIZE = 48

local datetime_t = ffi.typeof('struct datetime')

local function is_datetime(o)
    return ffi.istype(datetime_t, o)
end

local function check_table(o, message)
    if type(o) ~= 'table' then
        return error(("%s: expected table, but received %s"):
                     format(message, o), 2)
    end
end

local function check_str(s, message)
    if type(s) ~= 'string' then
        return error(("%s: expected string, but received %s"):
                     format(message, s), 2)
    end
end

-- range may be of a form of pair {begin, end} or
-- tuple {begin, end, negative}
-- negative is a special value (so far) used for days only
local function check_range(v, from, to, txt, extra)
    if extra == v or (v >= from and v <= to) then
        return
    end

    if extra == nil then
        error(('value %d of %s is out of allowed range [%d, %d]'):
              format(v, txt, from, to), 2)
    else
        error(('value %d of %s is out of allowed range [%d, %d..%d]'):
              format(v, txt, extra, from, to), 2)
    end
end

local function nyi(msg)
    local text = 'Not yet implemented'
    if msg ~= nil then
        text = ("%s : '%s'"):format(text, msg)
    end
    error(text, 3)
end

-- convert from epoch related time to Rata Die related
local function local_rd(secs)
    return math_floor((secs + SECS_EPOCH_OFFSET) / SECS_PER_DAY)
end

-- convert UTC seconds to local seconds, adjusting by timezone
local function local_secs(obj)
    return obj.epoch + obj.tzoffset * 60
end

local function utc_secs(epoch, tzoffset)
    return epoch - tzoffset * 60
end

-- get epoch seconds, shift to the local timezone
-- adjust from 1970-related to 0000-related time
-- then return dt in those coordinates (number of days
-- since Rata Die date)
local function local_dt(obj)
    return builtin.tnt_dt_from_rdn(local_rd(local_secs(obj)))
end

local function normalize_nsec(secs, nsec)
    if nsec < 0 or nsec >= NANOS_PER_SEC then
        secs = secs + math_floor(nsec / NANOS_PER_SEC)
        nsec = nsec % NANOS_PER_SEC
    end
    return secs, nsec
end

local function datetime_cmp(lhs, rhs)
    if not is_datetime(lhs) or not is_datetime(rhs) then
        return nil
    end
    local sdiff = lhs.epoch - rhs.epoch
    return sdiff ~= 0 and sdiff or (lhs.nsec - rhs.nsec)
end

local function datetime_eq(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc == 0
end

local function datetime_lt(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc == nil and error('incompatible types for comparison', 2) or
           rc < 0
end

local function datetime_le(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc == nil and error('incompatible types for comparison', 2) or
           rc <= 0
end

local function datetime_serialize(self)
    return { epoch = self.epoch, nsec = self.nsec,
             tzoffset = self.tzoffset, tzindex = 0 }
end

--[[
    parse_tzoffset accepts time-zone strings in both basic
    and extended iso-8601 formats.

    Basic    Extended
    Z        N/A
    +hh      N/A
    -hh      N/A
    +hhmm    +hh:mm
    -hhmm    -hh:mm

    Returns timezone offset in minutes if string was accepted
    by parser, otherwise raise an error.
]]
local function parse_tzoffset(str)
    local offset = ffi.new('int[1]')
    local len = builtin.tnt_dt_parse_iso_zone_lenient(str, #str, offset)
    if len ~= #str then
        error(('invalid time-zone format %s'):format(str), 3)
    end
    return offset[0]
end

local function datetime_new_raw(epoch, nsec, tzoffset)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.epoch = epoch
    dt_obj.nsec = nsec or 0
    dt_obj.tzoffset = tzoffset or 0
    dt_obj.tzindex = 0
    return dt_obj
end

local function datetime_new_dt(dt, secs, nanosecs, offset)
    local epoch = (dt - DAYS_EPOCH_OFFSET) * SECS_PER_DAY
    return datetime_new_raw(epoch + secs - offset * 60, nanosecs, offset)
end

local function get_timezone(offset)
    if type(offset) == 'number' then
        return offset
    elseif type(offset) == 'string' then
        return parse_tzoffset(offset)
    end
end

local function bool2int(b)
    return b and 1 or 0
end

-- create datetime given attribute values from obj
local function datetime_new(obj)
    if obj == nil then
        return datetime_new_raw(0, 0, 0)
    end
    check_table(obj, 'datetime.new()')

    local ymd = false
    local hms = false
    local dt = DAYS_EPOCH_OFFSET

    local y = obj.year
    if y ~= nil then
        check_range(y, 1, 9999, 'year')
        ymd = true
    end
    local M = obj.month
    if M ~= nil then
        check_range(M, 1, 12, 'month')
        ymd = true
    end
    local d = obj.day
    if d ~= nil then
        check_range(d, 1, 31, 'day', -1)
        ymd = true
    end
    local h = obj.hour
    if h ~= nil then
        check_range(h, 0, 23, 'hour')
        hms = true
    end
    local m = obj.min
    if m ~= nil then
        check_range(m, 0, 59, 'min')
        hms = true
    end
    local s = obj.sec
    if s ~= nil then
        check_range(s, 0, 60, 'sec')
        hms = true
    end

    local nsec, usec, msec = obj.nsec, obj.usec, obj.msec
    local count_usec = bool2int(nsec ~= nil) + bool2int(usec ~= nil) +
                       bool2int(msec ~= nil)
    if count_usec > 0 then
        if count_usec > 1 then
            error('only one of nsec, usec or msecs may defined '..
                  'simultaneously', 2)
        end
        if usec ~= nil then
            check_range(usec, 0, 1e6, 'usec')
            nsec = usec * 1e3
        elseif msec ~= nil then
            check_range(msec, 0, 1e3, 'msec')
            nsec = msec * 1e6
        else
            check_range(nsec, 0, 1e9, 'nsec')
        end
    end
    local ts = obj.timestamp
    if ts ~= nil then
        if ymd then
            error('timestamp is not allowed if year/month/day provided', 2)
        end
        if hms then
            error('timestamp is not allowed if hour/min/sec provided', 2)
        end
        local fraction
        s, fraction = math_modf(ts)
        -- if there are separate nsec, usec, or msec provided then
        -- timestamp should be integer
        if count_usec == 0 then
            nsec = fraction * 1e9
        elseif fraction ~= 0 then
            error('only integer values allowed in timestamp '..
                  'if nsec, usec, or msecs provided', 2)
        end
        hms = true
    end

    local offset = obj.tzoffset
    if offset ~= nil then
        offset = get_timezone(offset)
        check_range(offset, -720, 720, offset)
    end

    if obj.tz ~= nil then
        nyi('tz')
    end

    -- .year, .month, .day
    if ymd then
        y = y or 1970
        M = M or 1
        d = d or 1
        if d < 0 then
            d = builtin.tnt_dt_days_in_month(y, M)
        end
        dt = builtin.tnt_dt_from_ymd(y, M, d)
    end

    -- .hour, .minute, .second
    local secs = 0
    if hms then
        secs = (h or 0) * 3600 + (m or 0) * 60 + (s or 0)
    end

    return datetime_new_dt(dt, secs, nsec, offset or 0)
end

--[[
    Convert to text datetime values

    - datetime will use ISO-8601 format:
        1970-01-01T00:00Z
        2021-08-18T16:57:08.981725+03:00
]]
local function datetime_tostring(self)
    local buff = ffi.new('char[?]', TOSTRING_BUFSIZE)
    local len = builtin.tnt_datetime_to_string(self, buff, TOSTRING_BUFSIZE)
    assert(len < TOSTRING_BUFSIZE)
    return ffi.string(buff)
end

--[[
    Dispatch function to create datetime from string or table.
    Creates default timeobject (pointing to Epoch date) if
    called without arguments.
]]
local function datetime_from(o)
    if o == nil or type(o) == 'table' then
        return datetime_new(o)
    end
end

--[[
    Create datetime object representing current time using microseconds
    platform timer and local timezone information.
]]
local function datetime_now()
    local d = datetime_new_raw(0, 0, 0)
    builtin.tnt_datetime_now(d)
    return d
end

--[[
    dt_dow() returns days of week in range: 1=Monday .. 7=Sunday
    convert it to os.date() wday which is in range: 1=Sunday .. 7=Saturday
]]
local function dow_to_wday(dow)
    return tonumber(dow) % 7 + 1
end
--[[
    Return table in os.date('*t') format, but with timezone
    and nanoseconds
]]
local function datetime_totable(self)
    local secs = local_secs(self) -- hour:minute should be in local timezone
    local dt = local_dt(self)

    return {
        year = builtin.tnt_dt_year(dt),
        month = builtin.tnt_dt_month(dt),
        yday = builtin.tnt_dt_doy(dt),
        day = builtin.tnt_dt_dom(dt),
        wday = dow_to_wday(builtin.tnt_dt_dow(dt)),
        hour = math_floor((secs / 3600) % 24),
        min = math_floor((secs / 60) % 60),
        sec = secs % 60,
        isdst = false,
        nsec = self.nsec,
        tzoffset = self.tzoffset,
    }
end

local function datetime_update_dt(self, dt, new_offset)
    local epoch = local_secs(self)
    local secs_day = epoch % SECS_PER_DAY
    epoch = (dt - DAYS_EPOCH_OFFSET) * SECS_PER_DAY +
            secs_day
    self.epoch = utc_secs(epoch, new_offset)
end

local function datetime_ymd_update(self, y, M, d, new_offset)
    if d < 0 then
        d = builtin.tnt_dt_days_in_month(y, M)
    end
    if d > 28 then
        local day_in_month = builtin.tnt_dt_days_in_month(y, M)
        if d > day_in_month then
            error(('invalid number of days %d in month %d for %d'):
                  format(d, M, y), 3)
        end
    end
    local dt = builtin.tnt_dt_from_ymd(y, M, d)
    datetime_update_dt(self, dt, new_offset)
end

local function datetime_hms_update(self, h, m, s, new_offset)
    local epoch = local_secs(self)
    local secs_day = epoch - (epoch % SECS_PER_DAY)
    self.epoch = utc_secs(secs_day + h * 3600 + m * 60 + s, new_offset)
end

local function datetime_set(self, obj)
    check_table(obj, "datetime.set()")

    local ymd = false
    local hms = false

    local dt = local_dt(self)
    local y0 = ffi.new('int[1]')
    local M0 = ffi.new('int[1]')
    local d0 = ffi.new('int[1]')
    builtin.tnt_dt_to_ymd(dt, y0, M0, d0)
    y0, M0, d0 = y0[0], M0[0], d0[0]

    local y = obj.year
    if y ~= nil then
        check_range(y, 1, 9999, 'year')
        ymd = true
    end
    local M = obj.month
    if M ~= nil then
        check_range(M, 1, 12, 'month')
        ymd = true
    end
    local d = obj.day
    if d ~= nil then
        check_range(d, 1, 31, 'day', -1)
        ymd = true
    end

    local lsecs = local_secs(self)
    local h0 = math_floor(lsecs / (24 * 60)) % 24
    local m0 = math_floor(lsecs / 60) % 60
    local sec0 = lsecs % 60

    local h = obj.hour
    if h ~= nil then
        check_range(h, 0, 23, 'hour')
        hms = true
    end
    local m = obj.min
    if m ~= nil then
        check_range(m, 0, 59, 'min')
        hms = true
    end
    local sec = obj.sec
    if sec ~= nil then
        check_range(sec, 0, 60, 'sec')
        hms = true
    end

    local nsec, usec, msec = obj.nsec, obj.usec, obj.msec
    local count_usec = bool2int(nsec ~= nil) + bool2int(usec ~= nil) +
                       bool2int(msec ~= nil)
    if count_usec > 0 then
        if count_usec > 1 then
            error('only one of nsec, usec or msecs may defined simultaneously', 2)
        end
        if usec ~= nil then
            check_range(usec, 0, 1e6, 'usec')
            self.nsec = usec * 1e3
        elseif msec ~= nil then
            check_range(msec, 0, 1e3, 'msec')
            self.nsec = msec * 1e6
        elseif nsec ~= nil then
            check_range(nsec, 0, 1e9, 'nsec')
            self.nsec = nsec
        end
    end

    local ts = obj.timestamp
    if ts ~= nil then
        local sec_int, fraction
        sec_int, fraction = math_modf(ts)
        -- if there is one of nsec, usec, msec provided
        -- then ignore fraction in timestamp
        -- otherwise - use nsec, usec, or msec
        if count_usec == 0 then
            nsec = fraction * 1e9
        else
            error('only integer values allowed in timestamp '..
                  'if nsec, usec, or msecs provided', 2)
        end

        self.epoch = sec_int
        self.nsec = nsec

        return self
    end

    local offset0 = self.tzoffset
    local offset = obj.tzoffset
    if offset ~= nil then
        offset = get_timezone(offset)
        check_range(offset, -720, 720, 'tzoffset')
    end

    if obj.tz ~= nil then
        nyi('tz')
    end

    -- .year, .month, .day
    if ymd then
        datetime_ymd_update(self, y or y0, M or M0, d or d0, offset or offset0)
    end

    -- .hour, .minute, .second
    if hms then
        datetime_hms_update(self, h or h0, m or m0, sec or sec0, offset or offset0)
    end

    self.epoch, self.nsec = normalize_nsec(self.epoch, self.nsec)

    if offset ~= nil then
        self.tzoffset = offset
    end

    return self
end

local function datetime_strftime(self, fmt)
    local strfmt_sz = 128
    local buff = ffi.new('char[?]', strfmt_sz)
    check_str(fmt, "datetime.strftime()")
    builtin.tnt_datetime_strftime(self, buff, strfmt_sz, fmt)
    return ffi.string(buff)
end

local function datetime_format(self, fmt)
    if fmt ~= nil then
        return datetime_strftime(self, fmt)
    else
        return datetime_tostring(self)
    end
end

local datetime_index_fields = {
    timestamp = function(self) return self.epoch + self.nsec / 1e9 end,

    year = function(self) return builtin.tnt_dt_year(local_dt(self)) end,
    yday = function(self) return builtin.tnt_dt_doy(local_dt(self)) end,
    month = function(self) return builtin.tnt_dt_month(local_dt(self)) end,
    day = function(self)
        return builtin.tnt_dt_dom(local_dt(self))
    end,
    wday = function(self)
        return dow_to_wday(builtin.tnt_dt_dow(local_dt(self)))
    end,
    hour = function(self) return math_floor((local_secs(self) / 3600) % 24) end,
    min = function(self) return math_floor((local_secs(self) / 60) % 60) end,
    sec = function(self) return self.epoch % 60 end,
    usec = function(self) return self.nsec / 1e3 end,
    msec = function(self) return self.nsec / 1e6 end,
}

local datetime_index_functions = {
    format = datetime_format,
    totable = datetime_totable,
    set = datetime_set,
    __serialize = datetime_serialize,
}

local function datetime_index(self, key)
    local handler_field = datetime_index_fields[key]
    return handler_field ~= nil and handler_field(self) or
           datetime_index_functions[key]
end

ffi.metatype(datetime_t, {
    __tostring = datetime_tostring,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __index = datetime_index,
})

return setmetatable(
    {
        new         = datetime_new,

        now         = datetime_now,

        is_datetime = is_datetime,
    }, {
        __call = function(self, ...) return datetime_from(...) end
    }
)
