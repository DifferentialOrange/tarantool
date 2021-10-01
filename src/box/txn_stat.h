#ifndef TARANTOOL_TXN_STAT_H
#define TARANTOOL_TXN_STAT_H

#ifdef __cplusplus
extern "C" {
#endif

#include "small/mempool.h"

enum {
	TXN_ALLOC_TRACKER = 0,
	TXN_ALLOC_STORY = 1,
	TXN_ALLOC_SVP = 2,
	TXN_ALLOC_STMT = 3,
	TXN_PIN_TUPLE = 4,
	TXN_ALLOC_MAX = 5
};

struct txn;
struct tuple;

struct txn_stat_info {
	uint64_t min[TXN_ALLOC_MAX];
	uint64_t max[TXN_ALLOC_MAX];
	uint64_t avg[TXN_ALLOC_MAX];
	uint64_t total[TXN_ALLOC_MAX];
};

void
txn_stats_get(struct txn_stat_info *stats);

void *
tx_region_alloc(struct txn *txn, size_t size, int alloc_type);

size_t
tx_region_used(struct txn *txn);

void
tx_region_truncate(struct txn *txn);

void *
tx_region_aligned_alloc(struct txn *txn, size_t size, size_t alignment, int alloc_type);

void *
tx_mempool_alloc(struct txn *txn, struct mempool *pool, int alloc_type);

void
tx_mempool_free(struct txn *txn, struct mempool *pool, void *ptr, int alloc_type);

void
tx_pin_tuple(struct txn *txn, struct tuple *tuple);

void
txn_stat_init();

void
txn_stat_free();

#define tx_region_alloc_object(txn, T, size, alloc_type) ({		            \
	*(size) = sizeof(T);							    \
	(T *)tx_region_aligned_alloc((txn), sizeof(T), alignof(T), (alloc_type));   \
})

#ifdef __cplusplus
}
#endif

#endif //TARANTOOL_TXN_STAT_H
