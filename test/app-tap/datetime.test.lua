#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test('errno')
local date = require('datetime')

test:plan(10)

local function assert_raises(test, error_msg, func, ...)
    local ok, err = pcall(func, ...)
    local err_tail = err:gsub("^.+:%d+: ", "")
    return test:is(not ok and err_tail, error_msg,
                   ('"%s" received, "%s" expected'):format(err_tail, error_msg))
end

local incompat_types = 'incompatible types for comparison'

test:test("Default date creation and comparison", function(test)
    test:plan(37)
    -- check empty arguments
    local T1 = date.new()
    test:is(T1.epoch, 0, "T.epoch ==0")
    test:is(T1.nsec, 0, "T.nsec == 0")
    test:is(T1.tzoffset, 0, "T.tzoffset == 0")
    test:is(tostring(T1), "1970-01-01T00:00:00Z", "tostring(T1)")
    -- check empty table
    local T2 = date.new{}
    test:is(T2.epoch, 0, "T.epoch ==0")
    test:is(T2.nsec, 0, "T.nsec == 0")
    test:is(T2.tzoffset, 0, "T.tzoffset == 0")
    test:is(tostring(T2), "1970-01-01T00:00:00Z", "tostring(T2)")
    -- check their equivalence
    test:is(T1, T2, "T1 == T2")
    test:is(T1 ~= T2, false, "not T1 != T2")

    test:isnt(T1, nil, "T1 != {}")
    test:isnt(T1, {}, "T1 != {}")
    test:isnt(T1, "1970-01-01T00:00:00Z", "T1 != '1970-01-01T00:00:00Z'")
    test:isnt(T1, 19700101, "T1 != 19700101")

    test:isnt(nil, T1, "{} ~= T1")
    test:isnt({}, T1 ,"{} ~= T1")
    test:isnt("1970-01-01T00:00:00Z", T1, "'1970-01-01T00:00' ~= T1")
    test:isnt(19700101, T1, "T1 ~= T1")

    test:is(T1 < T2, false, "not T1 < T2")
    test:is(T1 > T2, false, "not T1 < T2")
    test:is(T1 <= T2, true, "not T1 < T2")
    test:is(T1 >= T2, true, "not T1 < T2")

    -- check is_datetime
    test:is(date.is_datetime(T1), true, "T1 is datetime")
    test:is(date.is_datetime(T2), true, "T2 is datetime")
    test:is(date.is_datetime({}), false, "bogus is not datetime")

    -- check comparison errors -- ==, ~= not raise errors, other
    -- comparison operators should raise
    assert_raises(test, incompat_types, function() return T1 < nil end)
    assert_raises(test, incompat_types, function() return T1 < 123 end)
    assert_raises(test, incompat_types, function() return T1 < '1970-01-01' end)
    assert_raises(test, incompat_types, function() return T1 <= nil end)
    assert_raises(test, incompat_types, function() return T1 <= 123 end)
    assert_raises(test, incompat_types, function() return T1 <= '1970-01-01' end)
    assert_raises(test, incompat_types, function() return T1 > nil end)
    assert_raises(test, incompat_types, function() return T1 > 123 end)
    assert_raises(test, incompat_types, function() return T1 > '1970-01-01' end)
    assert_raises(test, incompat_types, function() return T1 >= nil end)
    assert_raises(test, incompat_types, function() return T1 >= 123 end)
    assert_raises(test, incompat_types, function() return T1 >= '1970-01-01' end)
end)

local function nyi_error(msg)
    return ("Not yet implemented : '%s'"):format(msg)
end

local function table_expected(msg, value)
    return ("%s: expected table, but received %s"):
            format(msg, value)
end

test:test("Simple date creation by attributes", function(test)
    test:plan(12)
    local T
    local obj = {}
    local attribs = {
        { 'year', 2000, '2000-01-01T00:00:00Z' },
        { 'month', 11, '2000-11-01T00:00:00Z' },
        { 'day', 30, '2000-11-30T00:00:00Z' },
        { 'hour', 6, '2000-11-30T06:00:00Z' },
        { 'min', 12, '2000-11-30T06:12:00Z' },
        { 'sec', 23, '2000-11-30T06:12:23Z' },
        { 'tzoffset', -8*60, '2000-11-30T06:12:23-0800' },
        { 'tzoffset', '+0800', '2000-11-30T06:12:23+0800' },
    }
    for _, row in pairs(attribs) do
        local key, value, str = unpack(row)
        obj[key] = value
        T = date.new(obj)
        test:is(tostring(T), str, ('{%s = %s}, expected %s'):
                format(key, value, str))
    end
    test:is(tostring(date.new{timestamp = 1630359071.125}),
            '2021-08-30T21:31:11.125Z', '{timestamp}')
    test:is(tostring(date.new{timestamp = 1630359071, msec = 123}),
            '2021-08-30T21:31:11.123Z', '{timestamp.msec}')
    test:is(tostring(date.new{timestamp = 1630359071, usec = 123}),
            '2021-08-30T21:31:11.000123Z', '{timestamp.usec}')
    test:is(tostring(date.new{timestamp = 1630359071, nsec = 123}),
            '2021-08-30T21:31:11.000000123Z', '{timestamp.nsec}')
end)

local only_integer_ts = 'only integer values allowed in timestamp'..
                        ' if nsec, usec, or msecs provided'
local only_one_of = 'only one of nsec, usec or msecs may defined simultaneously'
local timestamp_and_ymd = 'timestamp is not allowed if year/month/day provided'
local timestamp_and_hms = 'timestamp is not allowed if hour/min/sec provided'

local function range_check_error(name, value, range)
    return ('value %s of %s is out of allowed range [%d, %d]'):
              format(value, name, range[1], range[2])
end

local function range_check_3_error(v)
    return ('value %d of %s is out of allowed range [%d, %d..%d]'):
            format(v, 'day', -1, 1, 31)
end

test:test("Simple date creation by attributes - check failed", function(test)
    test:plan(19)
    assert_raises(test, nyi_error('tz'), function() date.new{tz = 400} end)
    assert_raises(test, table_expected('datetime.new()', '2001-01-01'),
                  function() date.new('2001-01-01') end)
    assert_raises(test, table_expected('datetime.new()', 20010101),
                  function() date.new(20010101) end)

    assert_raises(test, only_integer_ts, function()
                    date.new{timestamp = 1630359071.125, nsec = 123}
                  end)
    assert_raises(test, only_integer_ts, function()
                    date.new{timestamp = 1630359071.125, msec = 123}
                  end)
    assert_raises(test, only_integer_ts, function()
                    date.new{timestamp = 1630359071.125, usec = 123}
                  end)
    assert_raises(test, only_one_of, function()
                    date.new{msec = 123, usec = 123 }
                  end)
    assert_raises(test, only_one_of, function()
                    date.new{msec = 123, nsec = 123 }
                  end)
    assert_raises(test, only_one_of, function()
                    date.new{usec = 123, nsec = 123 }
                  end)
    assert_raises(test, only_one_of, function()
                    date.new{msec = 123, usec = 123, nsec = 123 }
                  end)
    assert_raises(test, range_check_error('msec', 1e10, {0, 1e3}),
                  function() date.new{ msec = 1e10} end)
    assert_raises(test, range_check_error('usec', 1e10, {0, 1e6}),
                  function() date.new{ usec = 1e10} end)
    assert_raises(test, range_check_error('nsec', 1e10, {0, 1e9}),
                  function() date.new{ nsec = 1e10} end)
    assert_raises(test, timestamp_and_ymd, function()
                    date.new{timestamp = 1630359071.125, year = 2021 }
                  end)
    assert_raises(test, timestamp_and_ymd, function()
                    date.new{timestamp = 1630359071.125, month = 9 }
                  end)
    assert_raises(test, timestamp_and_ymd, function()
                    date.new{timestamp = 1630359071.125, day = 29 }
                  end)
    assert_raises(test, timestamp_and_hms, function()
                    date.new{timestamp = 1630359071.125, hour = 20 }
                  end)
    assert_raises(test, timestamp_and_hms, function()
                    date.new{timestamp = 1630359071.125, min = 10 }
                  end)
    assert_raises(test, timestamp_and_hms, function()
                    date.new{timestamp = 1630359071.125, sec = 29 }
                  end)
end)

local function expected_str(msg, value)
    return ("%s: expected string, but received %s"):format(msg, value)
end

test:test("Datetime string formatting", function(test)
    test:plan(8)
    local t = date.new()
    test:is(t.epoch, 0, ('t.epoch == %d'):format(tonumber(t.epoch)))
    test:is(t.nsec, 0, ('t.nsec == %d'):format(t.nsec))
    test:is(t.tzoffset, 0, ('t.tzoffset == %d'):format(t.tzoffset))
    test:is(t:format('%d/%m/%Y'), '01/01/1970', '%s: format #1')
    test:is(t:format('%A %d. %B %Y'), 'Thursday 01. January 1970', 'format #2')
    test:is(t:format('%FT%T'), '1970-01-01T00:00:00', 'format #3')
    test:is(t:format(), '1970-01-01T00:00:00Z', 'format #6')
    assert_raises(test, expected_str('datetime.strftime()', 1234),
                  function() t:format(1234) end)
end)

test:test("__index functions()", function(test)
    test:plan(12)
    -- 2000-01-29T03:30:12Z'
    local T = date.new{sec = 12, min = 30, hour = 3,
                       tzoffset = 0,  day = 29, month = 1, year = 2000,
                       nsec = 123000000}

    test:is(T.min, 30, 'T.min')
    test:is(T.wday, 7, 'T.wday')
    test:is(T.yday, 29, 'T.yday')
    test:is(T.year, 2000, 'T.year')
    test:is(T.month, 1, 'T.month')
    test:is(T.day, 29, 'T.day')
    test:is(T.hour, 3, 'T.hour')
    test:is(T.min, 30, 'T.min')
    test:is(T.sec, 12, 'T.sec')

    test:is(T.nsec, 123000000, 'T.nsec')
    test:is(T.usec, 123000, 'T.usec')
    test:is(T.msec, 123, 'T.msec')
end)

test:test("totable{}", function(test)
    test:plan(78)
    local exp = {sec = 0, min = 0, wday = 5, day = 1,
                 nsec = 0, isdst = false, yday = 1,
                 tzoffset = 0, month = 1, year = 1970, hour = 0}
    local T = date.new()
    local TT = T:totable()
    test:is_deeply(TT, exp, 'date:totable()')

    local D = os.date('*t')
    TT = date.new(D):totable()
    local keys = {
        'sec', 'min', 'wday', 'day', 'yday', 'month', 'year', 'hour'
    }
    for _, key in pairs(keys) do
        test:is(TT[key], D[key], ('[%s]: %s == %s'):format(key, TT[key], D[key]))
    end
    for tst_d = 21,28 do
        -- check wday wrapping for the whole week
        D = os.date('*t', os.time{year = 2021, month = 9, day = tst_d})
        TT = date.new(D):totable()
        for _, key in pairs(keys) do
            test:is(TT[key], D[key], ('[%s]: %s == %s'):format(key, TT[key], D[key]))
        end
    end
    -- date.now() and os.date('*t') could span day boundary in between their
    -- invocations. If midnight suddenly happened - simply call them both again
    T = date.now() D = os.date('*t')
    if T.day ~= D.day then
        T = date.now() D = os.date('*t')
    end
    for _, key in pairs({'wday', 'day', 'yday', 'month', 'year'}) do
        test:is(T[key], D[key], ('[%s]: %s == %s'):format(key, T[key], D[key]))
    end
end)

local function invalid_days_in_mon(d, M, y)
    return ('invalid number of days %d in month %d for %d'):format(d, M, y)
end

test:test("Time :set{} operations", function(test)
    test:plan(13)

    local T = date.new{ year = 2021, month = 8, day = 31,
                  hour = 0, min = 31, sec = 11, tzoffset = '+0300'}
    test:is(tostring(T), '2021-08-31T00:31:11+0300', 'initial')
    test:is(tostring(T:set{ year = 2020 }), '2020-08-31T00:31:11+0300', '2020 year')
    test:is(tostring(T:set{ month = 11, day = 30 }), '2020-11-30T00:31:11+0300', 'month = 11, day = 30')
    test:is(tostring(T:set{ day = 9 }), '2020-11-09T00:31:11+0300', 'day 9')
    test:is(tostring(T:set{ hour = 6 }),  '2020-11-09T06:31:11+0300', 'hour 6')
    test:is(tostring(T:set{ min = 12, sec = 23 }), '2020-11-09T04:12:23+0300', 'min 12, sec 23')
    test:is(tostring(T:set{ tzoffset = -8*60 }), '2020-11-08T17:12:23-0800', 'offset -0800' )
    test:is(tostring(T:set{ tzoffset = '+0800' }), '2020-11-09T09:12:23+0800', 'offset +0800' )
    test:is(tostring(T:set{ timestamp = 1630359071.125 }),
            '2021-08-31T05:31:11.125+0800', 'timestamp 1630359071.125' )
    test:is(tostring(T:set{ msec = 123}), '2021-08-31T05:31:11.123+0800',
            'msec = 123')
    test:is(tostring(T:set{ usec = 123}), '2021-08-31T05:31:11.000123+0800',
            'usec = 123')
    test:is(tostring(T:set{ nsec = 123}), '2021-08-31T05:31:11.000000123+0800',
            'nsec = 123')
    assert_raises(test, invalid_days_in_mon(31, 6, 2021),
                  function() T:set{ month = 6, day = 31} end)
end)

test:test("Time invalid :set{} operations", function(test)
    test:plan(23)

    local T = date.new{}

    assert_raises(test, range_check_error('year', 10000, {1, 9999}),
                  function() T:set{ year = 10000} end)
    assert_raises(test, range_check_error('year', -10, {1, 9999}),
                  function() T:set{ year = -10} end)

    assert_raises(test, range_check_error('month', 20, {1, 12}),
                  function() T:set{ month = 20} end)
    assert_raises(test, range_check_error('month', 0, {1, 12}),
                  function() T:set{ month = 0} end)
    assert_raises(test, range_check_error('month', -20, {1, 12}),
                  function() T:set{ month = -20} end)

    assert_raises(test,  range_check_3_error(40),
                  function() T:set{ day = 40} end)
    assert_raises(test,  range_check_3_error(0),
                  function() T:set{ day = 0} end)
    assert_raises(test,  range_check_3_error(-10),
                  function() T:set{ day = -10} end)

    assert_raises(test,  range_check_error('hour', 31, {0, 23}),
                  function() T:set{ hour = 31} end)
    assert_raises(test,  range_check_error('hour', -1, {0, 23}),
                  function() T:set{ hour = -1} end)

    assert_raises(test,  range_check_error('min', 60, {0, 59}),
                  function() T:set{ min = 60} end)
    assert_raises(test,  range_check_error('min', -1, {0, 59}),
                  function() T:set{ min = -1} end)

    assert_raises(test,  range_check_error('sec', 61, {0, 60}),
                  function() T:set{ sec = 61} end)
    assert_raises(test,  range_check_error('sec', -1, {0, 60}),
                  function() T:set{ sec = -1} end)

    local only1 = 'only one of nsec, usec or msecs may defined simultaneously'
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, usec = 123}
                  end)
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, msec = 123}
                  end)
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, usec = 1234, msec = 123}
                  end)

    local only_int = 'only integer values allowed in timestamp '..
                     'if nsec, usec, or msecs provided'
    assert_raises(test, only_int, function()
                    T:set{ timestamp = 12345.125, usec = 123}
                  end)
    assert_raises(test, only_int, function()
                    T:set{ timestamp = 12345.125, msec = 123}
                  end)
    assert_raises(test, only_int, function()
                    T:set{ timestamp = 12345.125, nsec = 123}
                  end)

    assert_raises(test, range_check_error('msec', 1e10, {0, 1e3}),
                  function() T:set{ msec = 1e10} end)
    assert_raises(test, range_check_error('usec', 1e10, {0, 1e6}),
                  function() T:set{ usec = 1e10} end)
    assert_raises(test, range_check_error('nsec', 1e10, {0, 1e9}),
                  function() T:set{ nsec = 1e10} end)
end)

local function invalid_tz_fmt_error(val)
    return ('invalid time-zone format %s'):format(val)
end

test:test("Time invalid tzoffset in :set{} operations", function(test)
    test:plan(14)

    local T = date.new{}
    local bad_strings = {
        '+03:00 what?',
        '-0000 ',
        '+0000 ',
        'bogus',
        '0100',
        '+-0100',
        '+25:00',
        '+9900',
        '-99:00',
    }
    for _, val in ipairs(bad_strings) do
        assert_raises(test, invalid_tz_fmt_error(val),
                      function() T:set{ tzoffset = val } end)
    end

    local bad_numbers = {
        800,
        -800,
        10000,
        -10000,
    }
    for _, val in ipairs(bad_numbers) do
        assert_raises(test, range_check_error('tzoffset', val, {-720, 720}),
                      function() T:set{ tzoffset = val } end)
    end
    assert_raises(test, nyi_error('tz'), function() T:set{tz = 400} end)
end)


test:test("Time :set{day = -1} operations", function(test)
    test:plan(14)
    local tests = {
        {{ year = 2000, month = 3, day = -1}, '2000-03-31T00:00:00Z'},
        {{ year = 2000, month = 2, day = -1}, '2000-02-29T00:00:00Z'},
        {{ year = 2001, month = 2, day = -1}, '2001-02-28T00:00:00Z'},
        {{ year = 1900, month = 2, day = -1}, '1900-02-28T00:00:00Z'},
        {{ year = 1904, month = 2, day = -1}, '1904-02-29T00:00:00Z'},
    }
    local T
    for _, row in ipairs(tests) do
        local args, str = unpack(row)
        T = date.new(args)
        test:is(tostring(T), str, ('checking -1 with %s'):format(str))
    end
    assert_raises(test, range_check_3_error(0), function() T = date.new{day = 0} end)
    assert_raises(test, range_check_3_error(-2), function() T = date.new{day = -2} end)
    assert_raises(test, range_check_3_error(-10), function() T = date.new{day = -10} end)

    T = date.new{ year = 1904, month = 2, day = -1 }
    test:is(tostring(T), '1904-02-29T00:00:00Z', 'base before :set{}')
    test:is(tostring(T:set{month = 3, day = 2}), '1904-03-02T00:00:00Z', '2 March')
    test:is(tostring(T:set{day = -1}), '1904-03-31T00:00:00Z', '31 March')

    assert_raises(test, range_check_3_error(0), function() T:set{day = 0} end)
    assert_raises(test, range_check_3_error(-2), function() T:set{day = -2} end)
    assert_raises(test, range_check_3_error(-10), function() T:set{day = -10} end)
end)

os.exit(test:check() and 0 or 1)
