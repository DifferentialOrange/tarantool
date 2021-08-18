#pragma once
/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <limits.h>
#include <stdint.h>
#include <sys/types.h>

#if defined(__cplusplus)
extern "C" {
#endif /* defined(__cplusplus) */

/**
 * We count dates since so called "Rata Die" date
 * January 1, 0001, Monday (as Day 1).
 * But datetime structure keeps seconds since
 * Unix "Epoch" date:
 * Unix, January 1, 1970, Thursday
 *
 * The difference between Epoch (1970-01-01)
 * and Rata Die (0001-01-01) is 719163 days.
 */

#ifndef SECS_PER_DAY
#define SECS_PER_DAY          86400
#define DT_EPOCH_1970_OFFSET  719163
#endif

/**
 * c-dt library uses int as type for dt value, which
 * represents the number of days since Rata Die date.
 * This implies limits to the number of seconds we
 * could safely store in our structures and then safely
 * pass to c-dt functions.
 *
 * So supported ranges will be
 * - for seconds [-185604722870400 .. 185480451417600]
 * - for dates   [-5879610-06-22T00:00Z .. 5879611-07-11T00:00Z]
 */
#define MAX_DT_DAY_VALUE (int64_t)INT_MAX
#define MIN_DT_DAY_VALUE (int64_t)INT_MIN
#define SECS_EPOCH_1970_OFFSET 	\
	((int64_t)DT_EPOCH_1970_OFFSET * SECS_PER_DAY)
#define MAX_EPOCH_SECS_VALUE    \
	(MAX_DT_DAY_VALUE * SECS_PER_DAY - SECS_EPOCH_1970_OFFSET)
#define MIN_EPOCH_SECS_VALUE    \
	(MIN_DT_DAY_VALUE * SECS_PER_DAY - SECS_EPOCH_1970_OFFSET)

/**
 * datetime structure keeps number of seconds and
 * nanoseconds since Unix Epoch.
 * Time is normalized by UTC, so time-zone offset
 * is informative only.
 */
struct datetime {
	/** Seconds since Epoch. */
	double epoch;
	/** Nanoseconds, if any. */
	int32_t nsec;
	/** Offset in minutes from UTC. */
	int16_t tzoffset;
	/** Olson timezone id */
	int16_t tzindex;
};

/**
 * Required size of tnt_datetime_to_string string buffer
 */
#define DT_TO_STRING_BUFSIZE 48

/*
 * Compare arguments of a datetime type
 * @param lhs left datetime argument
 * @param rhs right datetime argument
 * @retval < 0 if lhs less than rhs
 * @retval = 0 if lhs and rhs equal
 * @retval > 0 if lhs greater than rhs
 */
int
datetime_compare(const struct datetime *lhs, const struct datetime *rhs);

/**
 * Convert datetime to string using default format
 * @param date source datetime value
 * @param buf output character buffer
 * @param len size of output buffer
 * @retval length of a resultant text
 */
size_t
tnt_datetime_to_string(const struct datetime *date, char *buf, ssize_t len);

/**
 * Convert datetime to string using default format provided
 * Wrapper around standard strftime() function
 * @param date source datetime value
 * @param buf output buffer
 * @param len size of output buffer
 * @param fmt format
 * @retval length of a resultant text
 */
size_t
tnt_datetime_strftime(const struct datetime *date, char *buf, size_t len,
		      const char *fmt);

void
tnt_datetime_now(struct datetime *now);

/**
 * Local version resembling ISO C' tm structure.
 * Includes original epoch value, and nanoseconds.
 */
struct datetime_tm {
	/** Seconds. [0-60] (1 leap second) */
	int tm_sec;
	/** Minutes. [0-59] */
	int tm_min;
	/** Hours. [0-23] */
	int tm_hour;
	/** Day. [1-31] */
	int tm_mday;
	/** Month. [0-11] */
	int tm_mon;
	/** Year - 1900. */
	int tm_year;
	/** Day of week. [0-6] */
	int tm_wday;
	/** Days in year.[0-365] */
	int tm_yday;
	/** DST. [-1/0/1] */
	int tm_isdst;

	/** Seconds east of UTC. */
	long int tm_gmtoff;
	/** Timezone abbreviation. */
	const char *tm_zone;
	/** Seconds since Epoch */
	int64_t tm_epoch;
	/** nanoseconds */
	int tm_nsec;
};

/**
 * Convert @sa datetime to @sa dt_tm
 */
void
datetime_to_tm(const struct datetime *date, struct datetime_tm *tm);

/**
 * tnt_strftime is Tarantol version of POSIX' strftime()
 * which has been extended with %f (fractions of second)
 * flag support. In all other aspect it's behaving exactly
 * like standard strftime.
 * @sa strftime()
 */
size_t
tnt_strftime(char *s, size_t maxsize, const char *format,
	     const struct datetime_tm *tm);

#if defined(__cplusplus)
} /* extern "C" */
#endif /* defined(__cplusplus) */
