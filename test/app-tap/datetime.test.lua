#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test('errno')
local date = require('datetime')

-- local ffi = require('ffi')
-- ffi.cdef [[ void tzset(void); ]]

test:plan(19)

local function assert_raises(test, error_msg, func, ...)
    local ok, err = pcall(func, ...)
    local err_tail = err:gsub("^.+:%d+: ", "")
    return test:is(not ok and err_tail, error_msg,
                   ('"%s" received, "%s" expected'):format(err_tail, error_msg))
end

local function assert_raises_like(test, error_msg, func, ...)
    local ok, err = pcall(func, ...)
    local err_tail = err:gsub("^.+:%d+: ", "")
    return test:like(not ok and err_tail, error_msg,
                   ('"%s" received, "%s" expected'):format(err_tail, error_msg))
end

test:test("Default date creation and comparison", function(test)
    test:plan(25)
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

test:test("Simple tests for parser", function(test)
    test:plan(4)
    test:ok(date("1970-01-01T01:00:00Z") ==
            date {year=1970, mon=1, day=1, hour=1, min=0, sec=0})
    test:ok(date("1970-01-01T02:00:00+02:00") ==
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=0, tzoffset=120})

    test:ok(date("1970-01-01T02:00:00Z") <
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=1})
    test:ok(date("1970-01-01T02:00:00Z") <=
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=0})
end)

test:test("Multiple tests for parser (with nanoseconds)", function(test)
    test:plan(193)
    -- borrowed from p5-time-moments/t/180_from_string.t
    local tests =
    {
        {'1970-01-01T00:00:00Z',               0,         0,    0, 1},
        {'1970-01-01T02:00:00+0200',           0,         0,  120, 1},
        {'1970-01-01T01:30:00+0130',           0,         0,   90, 1},
        {'1970-01-01T01:00:00+0100',           0,         0,   60, 1},
        {'1970-01-01T00:01:00+0001',           0,         0,    1, 1},
        {'1970-01-01T00:00:00Z',               0,         0,    0, 1},
        {'1969-12-31T23:59:00-0001',           0,         0,   -1, 1},
        {'1969-12-31T23:00:00-0100',           0,         0,  -60, 1},
        {'1969-12-31T22:30:00-0130',           0,         0,  -90, 1},
        {'1969-12-31T22:00:00-0200',           0,         0, -120, 1},
        {'1970-01-01T00:00:00.123456789Z',     0, 123456789,    0, 1},
        {'1970-01-01T00:00:00.12345678Z',      0, 123456780,    0, 0},
        {'1970-01-01T00:00:00.1234567Z',       0, 123456700,    0, 0},
        {'1970-01-01T00:00:00.123456Z',        0, 123456000,    0, 1},
        {'1970-01-01T00:00:00.12345Z',         0, 123450000,    0, 0},
        {'1970-01-01T00:00:00.1234Z',          0, 123400000,    0, 0},
        {'1970-01-01T00:00:00.123Z',           0, 123000000,    0, 1},
        {'1970-01-01T00:00:00.12Z',            0, 120000000,    0, 0},
        {'1970-01-01T00:00:00.1Z',             0, 100000000,    0, 0},
        {'1970-01-01T00:00:00.01Z',            0,  10000000,    0, 0},
        {'1970-01-01T00:00:00.001Z',           0,   1000000,    0, 1},
        {'1970-01-01T00:00:00.0001Z',          0,    100000,    0, 0},
        {'1970-01-01T00:00:00.00001Z',         0,     10000,    0, 0},
        {'1970-01-01T00:00:00.000001Z',        0,      1000,    0, 1},
        {'1970-01-01T00:00:00.0000001Z',       0,       100,    0, 0},
        {'1970-01-01T00:00:00.00000001Z',      0,        10,    0, 0},
        {'1970-01-01T00:00:00.000000001Z',     0,         1,    0, 1},
        {'1970-01-01T00:00:00.000000009Z',     0,         9,    0, 1},
        {'1970-01-01T00:00:00.00000009Z',      0,        90,    0, 0},
        {'1970-01-01T00:00:00.0000009Z',       0,       900,    0, 0},
        {'1970-01-01T00:00:00.000009Z',        0,      9000,    0, 1},
        {'1970-01-01T00:00:00.00009Z',         0,     90000,    0, 0},
        {'1970-01-01T00:00:00.0009Z',          0,    900000,    0, 0},
        {'1970-01-01T00:00:00.009Z',           0,   9000000,    0, 1},
        {'1970-01-01T00:00:00.09Z',            0,  90000000,    0, 0},
        {'1970-01-01T00:00:00.9Z',             0, 900000000,    0, 0},
        {'1970-01-01T00:00:00.99Z',            0, 990000000,    0, 0},
        {'1970-01-01T00:00:00.999Z',           0, 999000000,    0, 1},
        {'1970-01-01T00:00:00.9999Z',          0, 999900000,    0, 0},
        {'1970-01-01T00:00:00.99999Z',         0, 999990000,    0, 0},
        {'1970-01-01T00:00:00.999999Z',        0, 999999000,    0, 1},
        {'1970-01-01T00:00:00.9999999Z',       0, 999999900,    0, 0},
        {'1970-01-01T00:00:00.99999999Z',      0, 999999990,    0, 0},
        {'1970-01-01T00:00:00.999999999Z',     0, 999999999,    0, 1},
        {'1970-01-01T00:00:00.0Z',             0,         0,    0, 0},
        {'1970-01-01T00:00:00.00Z',            0,         0,    0, 0},
        {'1970-01-01T00:00:00.000Z',           0,         0,    0, 0},
        {'1970-01-01T00:00:00.0000Z',          0,         0,    0, 0},
        {'1970-01-01T00:00:00.00000Z',         0,         0,    0, 0},
        {'1970-01-01T00:00:00.000000Z',        0,         0,    0, 0},
        {'1970-01-01T00:00:00.0000000Z',       0,         0,    0, 0},
        {'1970-01-01T00:00:00.00000000Z',      0,         0,    0, 0},
        {'1970-01-01T00:00:00.000000000Z',     0,         0,    0, 0},
        {'1973-11-29T21:33:09Z',       123456789,         0,    0, 1},
        {'2013-10-28T17:51:56Z',      1382982716,         0,    0, 1},
        {'9999-12-31T23:59:59Z',    253402300799,         0,    0, 1},
    }
    for _, value in ipairs(tests) do
        local str, epoch, nsec, tzoffset, check
        str, epoch, nsec, tzoffset, check = unpack(value)
        local dt = date(str)
        test:is(dt.epoch, epoch, ('%s: dt.epoch == %d'):format(str, epoch))
        test:is(dt.nsec, nsec, ('%s: dt.nsec == %d'):format(str, nsec))
        test:is(dt.tzoffset, tzoffset, ('%s: dt.tzoffset == %d'):format(str, tzoffset))
        if check > 0 then
            test:is(str, tostring(dt), ('%s == tostring(%s)'):
                    format(str, tostring(dt)))
        end
    end
end)

local function expected_str(msg, value)
    return ("%s: expected string, but received %s"):format(msg, value)
end

test:test("Datetime string formatting", function(test)
    test:plan(10)
    local t = date()
    test:is(t.epoch, 0, ('t.epoch == %d'):format(tonumber(t.epoch)))
    test:is(t.nsec, 0, ('t.nsec == %d'):format(t.nsec))
    test:is(t.tzoffset, 0, ('t.tzoffset == %d'):format(t.tzoffset))
    test:is(t:format('%d/%m/%Y'), '01/01/1970', '%s: format #1')
    test:is(t:format('%A %d. %B %Y'), 'Thursday 01. January 1970', 'format #2')
    test:is(t:format('%FT%T%z'), '1970-01-01T00:00:00+0000', 'format #3')
    test:is(t:format('%FT%T.%f%z'), '1970-01-01T00:00:00.000+0000', 'format #4')
    test:is(t:format('%FT%T.%4f%z'), '1970-01-01T00:00:00.0000+0000', 'format #5')
    test:is(t:format(), '1970-01-01T00:00:00Z', 'format #6')
    assert_raises(test, expected_str('datetime.strftime()', 1234),
                  function() t:format(1234) end)
end)

test:test("Datetime string formatting detailed", function(test)
    test:plan(77)
    local T = date.new{ timestamp = 0.125 }
    T:set{ tzoffset = 180 }
    test:is(tostring(T), '1970-01-01T03:00:00.125+0300', 'tostring()')
    -- %Z and %+ are local timezone dependent. To make sure that
    -- test is deterministic we enforce timezone via TZ environment
    -- manipulations and calling tzset()

    -- temporarily disabled, as there is no cross-platform way
    -- to make behave %Z identically

    -- os.setenv('TZ', 'UTC')
    -- ffi.C.tzset()
    local formats = {
        { '%A',                         'Thursday' },
        { '%a',                         'Thu' },
        { '%B',                         'January' },
        { '%b',                         'Jan' },
        { '%h',                         'Jan' },
        { '%C',                         '19' },
        { '%c',                         'Thu Jan  1 03:00:00 1970' },
        { '%D',                         '01/01/70' },
        { '%m/%d/%y',                   '01/01/70' },
        { '%d',                         '01' },
        { '%Ec',                        'Thu Jan  1 03:00:00 1970' },
        { '%EC',                        '19' },
        { '%Ex',                        '01/01/70' },
        { '%EX',                        '03:00:00' },
        { '%Ey',                        '70' },
        { '%EY',                        '1970' },
        { '%Od',                        '01' },
        { '%oe',                        'oe' },
        { '%OH',                        '03' },
        { '%OI',                        '03' },
        { '%Om',                        '01' },
        { '%OM',                        '00' },
        { '%OS',                        '00' },
        { '%Ou',                        '4' },
        { '%OU',                        '00' },
        { '%OV',                        '01' },
        { '%Ow',                        '4' },
        { '%OW',                        '00' },
        { '%Oy',                        '70' },
        { '%e',                         ' 1' },
        { '%F',                         '1970-01-01' },
        { '%Y-%m-%d',                   '1970-01-01' },
        { '%H',                         '03' },
        { '%I',                         '03' },
        { '%j',                         '001' },
        { '%k',                         ' 3' },
        { '%l',                         ' 3' },
        { '%M',                         '00' },
        { '%m',                         '01' },
        { '%n',                         '\n' },
        { '%p',                         'AM' },
        { '%R',                         '03:00' },
        { '%H:%M',                      '03:00' },
        { '%r',                         '03:00:00 AM' },
        { '%I:%M:%S %p',                '03:00:00 AM' },
        { '%S',                         '00' },
        { '%s',                         '10800' },
        { '%f',                         '125' },
        { '%3f',                        '125' },
        { '%6f',                        '125000' },
        { '%6d',                        '6d' },
        { '%3D',                        '3D' },
        { '%T',                         '03:00:00' },
        { '%H:%M:%S',                   '03:00:00' },
        { '%t',                         '\t' },
        { '%U',                         '00' },
        { '%u',                         '4' },
        { '%V',                         '01' },
        { '%G',                         '1970' },
        { '%g',                         '70' },
        { '%v',                         ' 1-Jan-1970' },
        { '%e-%b-%Y',                   ' 1-Jan-1970' },
        { '%W',                         '00' },
        { '%w',                         '4' },
        { '%X',                         '03:00:00' },
        { '%x',                         '01/01/70' },
        { '%y',                         '70' },
        { '%Y',                         '1970' },
        --{ '%Z',                         'UTC' },
        { '%z',                         '+0300' },
        --{ '%+',                         'Thu Jan  1 03:00:00 UTC 1970' },
        { '%%',                         '%' },
        { '%Y-%m-%dT%H:%M:%S.%9f%z',    '1970-01-01T03:00:00.125000000+0300' },
        { '%Y-%m-%dT%H:%M:%S.%f%z',     '1970-01-01T03:00:00.125+0300' },
        { '%Y-%m-%dT%H:%M:%S.%f',       '1970-01-01T03:00:00.125' },
        { '%FT%T.%f',                   '1970-01-01T03:00:00.125' },
        { '%FT%T.%f%z',                 '1970-01-01T03:00:00.125+0300' },
        { '%FT%T.%9f%z',                '1970-01-01T03:00:00.125000000+0300' },
    }
    for _, row in pairs(formats) do
        local fmt, value = unpack(row)
        test:is(T:format(fmt), value,
                ('format %s, expected %s'):format(fmt, value))
    end
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

test:test("Parse iso date - valid strings", function(test)
    test:plan(32)
    local good = {
        {2012, 12, 24, "20121224",                   8 },
        {2012, 12, 24, "20121224  Foo bar",          8 },
        {2012, 12, 24, "2012-12-24",                10 },
        {2012, 12, 24, "2012-12-24 23:59:59",       10 },
        {2012, 12, 24, "2012-12-24T00:00:00+00:00", 10 },
        {2012, 12, 24, "2012359",                    7 },
        {2012, 12, 24, "2012359T235959+0130",        7 },
        {2012, 12, 24, "2012-359",                   8 },
        {2012, 12, 24, "2012W521",                   8 },
        {2012, 12, 24, "2012-W52-1",                10 },
        {2012, 12, 24, "2012Q485",                   8 },
        {2012, 12, 24, "2012-Q4-85",                10 },
        {   1,  1,  1, "0001-Q1-01",                10 },
        {   1,  1,  1, "0001-W01-1",                10 },
        {   1,  1,  1, "0001-01-01",                10 },
        {   1,  1,  1, "0001-001",                   8 },
    }

    for _, value in ipairs(good) do
        local year, month, day, str, date_part_len
        year, month, day, str, date_part_len = unpack(value)
        local expected_date = date{year = year, month = month, day = day}
        local date_part, len
        date_part, len = date.parse_date(str)
        test:is(len, date_part_len, ('%s: length check %d'):format(str, len))
        test:is(expected_date, date_part, ('%s: expected date'):format(str))
    end
end)

local function invalid_date_fmt_error(str)
    return ('invalid date format %s'):format(str)
end

test:test("Parse iso date - invalid strings", function(test)
    test:plan(31)
    local bad = {
        "20121232"   , -- Invalid day of month
        "2012-12-310", -- Invalid day of month
        "2012-13-24" , -- Invalid month
        "2012367"    , -- Invalid day of year
        "2012-000"   , -- Invalid day of year
        "2012W533"   , -- Invalid week of year
        "2012-W52-8" , -- Invalid day of week
        "2012Q495"   , -- Invalid day of quarter
        "2012-Q5-85" , -- Invalid quarter
        "20123670"   , -- Trailing digit
        "201212320"  , -- Trailing digit
        "2012-12"    , -- Reduced accuracy
        "2012-Q4"    , -- Reduced accuracy
        "2012-Q42"   , -- Invalid
        "2012-Q1-1"  , -- Invalid day of quarter
        "2012Q--420" , -- Invalid
        "2012-Q-420" , -- Invalid
        "2012Q11"    , -- Incomplete
        "2012Q1234"  , -- Trailing digit
        "2012W12"    , -- Incomplete
        "2012W1234"  , -- Trailing digit
        "2012W-123"  , -- Invalid
        "2012-W12"   , -- Incomplete
        "2012-W12-12", -- Trailing digit
        "2012U1234"  , -- Invalid
        "2012-1234"  , -- Invalid
        "2012-X1234" , -- Invalid
        "0000-Q1-01" , -- Year less than 0001
        "0000-W01-1" , -- Year less than 0001
        "0000-01-01" , -- Year less than 0001
        "0000-001"   , -- Year less than 0001
    }

    for _, str in ipairs(bad) do
        assert_raises(test, invalid_date_fmt_error(str),
                      function() date.parse_date(str) end)
    end
end)

test:test("Parse tiny date into seconds and other parts", function(test)
    test:plan(4)
    local str = '19700101 00:00:30.528'
    local tiny = date(str)
    test:is(tiny.epoch, 30, ("epoch of '%s'"):format(str))
    test:is(tiny.nsec, 528000000, ("nsec of '%s'"):format(str))
    test:is(tiny.sec, 30, "sec")
    test:is(tiny.timestamp, 30.528, "timestamp")
end)

local add_object_expected = ('%s - object expected'):format('datetime.add')
local sub_object_expected = ('%s - object expected'):format('datetime.sub')

test:test("Time interval operations", function(test)
    test:plan(16)

    -- check arithmetic with leap dates
    local T = date('1972-02-29')
    test:is(tostring(T:add{year = 1, month = 2}), '1973-05-01T00:00:00Z',
            ('T:add{year=1,month=2}(%s)'):format(T))
    test:is(tostring(T:sub{year = 2, month = 3}), '1971-02-01T00:00:00Z',
            ('T:sub{year=2,month=3}(%s)'):format(T))
    test:is(tostring(T:add{year = -1}), '1970-02-01T00:00:00Z',
            ('T:add{year=-1}(%s)'):format(T))
    test:is(tostring(T:sub{year = -1}), '1971-02-01T00:00:00Z',
            ('T:sub{year=-1}(%s)'):format(T))

    -- check average, not leap dates
    T = date('1970-01-08')
    test:is(tostring(T:add{year = 1, month = 2}), '1971-03-08T00:00:00Z',
            ('T:add{year=1,month=2}(%s)'):format(T))
    test:is(tostring(T:add{week = 10}), '1971-05-17T00:00:00Z',
            ('T:add{week=10}(%s)'):format(T))
    test:is(tostring(T:add{day = 15}), '1971-06-01T00:00:00Z',
            ('T:add{week=15}(%s)'):format(T))
    test:is(tostring(T:add{hour = 2}), '1971-06-01T02:00:00Z',
            ('T:add{hour=2}(%s)'):format(T))
    test:is(tostring(T:add{min = 15}), '1971-06-01T02:15:00Z',
            ('T:add{min=15}(%s)'):format(T))
    test:is(tostring(T:add{sec = 48.123456}),
            '1971-06-01T02:15:48.123455999Z',
            ('T:add{sec}(%s)'):format(T))
    test:is(tostring(T:add{nsec = 2e9}),
            '1971-06-01T02:15:50.123455999Z',
            ('T:add{nsec}(%s)'):format(T))
    test:is(tostring(T:add{ hour = 12, min = 600, sec = 1024}),
            '1971-06-02T00:32:54.123455999Z',
            ('T:add{hour=12,min=600,sec=1024}(%s)'):format(T))

    assert_raises(test, add_object_expected, function() T:add('bogus') end)
    assert_raises(test, add_object_expected, function() T:add(123) end)
    assert_raises(test, sub_object_expected, function() T:sub('bogus') end)
    assert_raises(test, sub_object_expected, function() T:sub(123) end)
end)

local function catchadd(A, B)
    return pcall(function() return A + B end)
end

local expected_interval_but = 'expected interval, but received'

--[[
Matrix of addition operands eligibility and their result type

|                 |  datetime | interval |
+-----------------+-----------+----------+
| datetime        |           | datetime |
| interval        |  datetime | interval |
]]
test:test("Matrix of allowed time and interval additions", function(test)
    test:plan(23)

    -- check arithmetic with leap dates
    local T1970 = date.parse('1970-01-01')
    local T2000 = date.parse('2000-01-01')
    local I1 = date.interval.new{day = 1}
    local M2 = date.interval.new{month = 2}
    local M10 = date.interval.new{month = 10}
    local Y1 = date.interval.new{year = 1}
    local Y5 = date.interval.new{year = 5}

    test:is(catchadd(T1970, I1), true, "status: T + I")
    test:is(catchadd(T1970, M2), true, "status: T + M")
    test:is(catchadd(T1970, Y1), true, "status: T + Y")
    test:is(catchadd(T1970, T2000), false, "status: T + T")
    test:is(catchadd(I1, T1970), true, "status: I + T")
    test:is(catchadd(M2, T1970), true, "status: M + T")
    test:is(catchadd(Y1, T1970), true, "status: Y + T")
    test:is(catchadd(I1, Y1), true, "status: I + Y")
    test:is(catchadd(M2, Y1), true, "status: M + Y")
    test:is(catchadd(I1, Y1), true, "status: I + Y")
    test:is(catchadd(Y5, M10), true, "status: Y + M")
    test:is(catchadd(Y5, I1), true, "status: Y + I")
    test:is(catchadd(Y5, Y1), true, "status: Y + Y")

    test:is(tostring(T1970 + I1), "1970-01-02T00:00:00Z", "value: T + I")
    test:is(tostring(T1970 + M2), "1970-03-01T00:00:00Z", "value: T + M")
    test:is(tostring(T1970 + Y1), "1971-01-01T00:00:00Z", "value: T + Y")
    test:is(tostring(I1 + T1970), "1970-01-02T00:00:00Z", "value: I + T")
    test:is(tostring(M2 + T1970), "1970-03-01T00:00:00Z", "value: M + T")
    test:is(tostring(Y1 + T1970), "1971-01-01T00:00:00Z", "value: Y + T")
    test:is(tostring(Y5 + Y1), "+6 years", "Y + Y")

    assert_raises_like(test, expected_interval_but,
                       function() return T1970 + 123 end)
    assert_raises_like(test, expected_interval_but,
                       function() return T1970 + {} end)
    assert_raises_like(test, expected_interval_but,
                       function() return T1970 + "0" end)
end)

local function catchsub_status(A, B)
    return pcall(function() return A - B end)
end

local expected_datetime_but = 'expected datetime or interval, but received'

--[[
Matrix of subtraction operands eligibility and their result type

|                 |  datetime | interval |
+-----------------+-----------+----------+
| datetime        |  interval | datetime |
| interval        |           | interval |
]]
test:test("Matrix of allowed time and interval subtractions", function(test)
    test:plan(21)

    -- check arithmetic with leap dates
    local T1970 = date.parse('1970-01-01')
    local T2000 = date.parse('2000-01-01')
    local I1 = date.interval.new{day = 1}
    local M2 = date.interval.new{month = 2}
    local M10 = date.interval.new{month = 10}
    local Y1 = date.interval.new{year = 1}
    local Y5 = date.interval.new{year = 5}

    test:is(catchsub_status(T1970, I1), true, "status: T - I")
    test:is(catchsub_status(T1970, M2), true, "status: T - M")
    test:is(catchsub_status(T1970, Y1), true, "status: T - Y")
    test:is(catchsub_status(T1970, T2000), true, "status: T - T")
    test:is(catchsub_status(I1, T1970), false, "status: I - T")
    test:is(catchsub_status(M2, T1970), false, "status: M - T")
    test:is(catchsub_status(Y1, T1970), false, "status: Y - T")
    test:is(catchsub_status(I1, Y1), true, "status: I - Y")
    test:is(catchsub_status(M2, Y1), true, "status: M - Y")
    test:is(catchsub_status(I1, Y1), true, "status: I - Y")
    test:is(catchsub_status(Y5, M10), true, "status: Y - M")
    test:is(catchsub_status(Y5, I1), true, "status: Y - I")
    test:is(catchsub_status(Y5, Y1), true, "status: Y - Y")

    test:is(tostring(T1970 - I1), "1969-12-31T00:00:00Z", "value: T - I")
    test:is(tostring(T1970 - M2), "1969-11-01T00:00:00Z", "value: T - M")
    test:is(tostring(T1970 - Y1), "1969-01-01T00:00:00Z", "value: T - Y")
    test:is(tostring(T1970 - T2000), "-10957 days, 0 hours, 0 minutes, 0 seconds",
            "value: T - T")
    test:is(tostring(Y5 - Y1), "+4 years", "value: Y - Y")

    assert_raises_like(test, expected_datetime_but,
                       function() return T1970 - 123 end)
    assert_raises_like(test, expected_datetime_but,
                       function() return T1970 - {} end)
    assert_raises_like(test, expected_datetime_but,
                       function() return T1970 - "0" end)
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
        TT = date(D):totable()
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
    test:plan(11)

    local T = date.new{}
    local bad_strings = {
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
