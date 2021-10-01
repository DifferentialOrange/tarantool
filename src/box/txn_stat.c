#include <assert.h>
#include "small/mempool.h"
#include "small/region.h"
#include "histogram.h"
#include "txn_stat.h"
#include "txn.h"
#include "fiber.h"

static uint32_t
txn_stat_key_hash(const struct txn *a)
{
	uintptr_t u = (uintptr_t)a;
	if (sizeof(uintptr_t) <= sizeof(uint32_t))
		return u;
	else
		return u ^ (u >> 32);
}

struct txn_stat {
	struct txn *txn;
	int32_t stats[TXN_ALLOC_MAX];
};

#define mh_name _txn_stats
#define mh_key_t struct txn *
#define mh_node_t struct txn_stat *
#define mh_arg_t int
#define mh_hash(a, arg) (txn_stat_key_hash((*(a))->txn))
#define mh_hash_key(a, arg) (txn_stat_key_hash(a))
#define mh_cmp(a, b, arg) ((*(a))->txn != (*(b))->txn)
#define mh_cmp_key(a, b, arg) ((a) != (*(b))->txn)
#define MH_SOURCE
#include "salad/mhash.h"

struct txn_stat_storage {
	struct histogram *hist;
	int64_t total;
	int32_t obj_count;
};

struct txn_stat_manager {
	struct txn_stat_storage stats_storage[TXN_ALLOC_MAX];
	struct mh_txn_stats_t *stats;
	struct mempool stat_item_pool;
};

static struct txn_stat_manager memtx_tx_stat_manager;

static struct txn_stat *
txn_stat_new()
{
	return mempool_alloc(&memtx_tx_stat_manager.stat_item_pool);
}

static void
txn_stat_forget(struct txn_stat *txn_stat)
{
	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats, txn_stat->txn, 0);
	mh_txn_stats_del(memtx_tx_stat_manager.stats, pos, 0);
	mempool_free(&memtx_tx_stat_manager.stat_item_pool, txn_stat);
}

void
txn_stats_get(struct txn_stat_info *stats)
{
	struct txn_stat_storage *stat_storage = memtx_tx_stat_manager.stats_storage;
	for (int i = 0; i < TXN_ALLOC_MAX; ++i) {
		stats->max[i] = stat_storage[i].hist->max;
		stats->min[i] = histogram_percentile_lower(stat_storage[i].hist, 0);
		stats->total[i] = stat_storage[i].total;
		stats->avg[i] = stat_storage[i].total / stat_storage[i].obj_count;
	}
}

static void
tx_track_allocation(struct txn *txn, int32_t alloc_size, int alloc_type) {
	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats, txn, 0);
	struct txn_stat *stat = NULL;
	if (pos == mh_end(memtx_tx_stat_manager.stats)) {
		stat = txn_stat_new();
	} else {
		stat = *mh_txn_stats_node(memtx_tx_stat_manager.stats, pos);
		histogram_discard(memtx_tx_stat_manager.stats_storage[alloc_type].hist, stat->stats[alloc_type]);
	}
	assert(stat->stats[alloc_type] >= alloc_size);
	stat->stats[alloc_type] += alloc_size;
	stat->
	histogram_collect(memtx_tx_stat_manager.stats_storage[alloc_type].hist, stat->stats[alloc_type]);
}

void *
tx_mempool_alloc(struct txn *txn, struct mempool* pool, int alloc_type)
{
	assert(txn != NULL);
	assert(pool != NULL);
	assert(alloc_type >= 0 && alloc_type < TXN_ALLOC_MAX);

	struct mempool_stats pool_stats;
	mempool_stats(pool, &pool_stats);
	tx_track_allocation(txn, pool_stats.objsize, alloc_type);

	return mempool_alloc(pool);
}

void
tx_mempool_free(struct txn *txn, struct mempool *pool, void *ptr, int alloc_type)
{
	assert(txn != NULL);
	assert(pool != NULL);
	assert(alloc_type >= 0 && alloc_type < TXN_ALLOC_MAX);

	struct mempool_stats pool_stats;
	mempool_stats(pool, &pool_stats);
	tx_track_allocation(txn, -1 * pool_stats.objsize, alloc_type);

	mempool_free(pool, ptr);
}

void *
txn_region_alloc(struct txn *txn, size_t size, int alloc_type)
{
	tx_track_allocation(txn, size, alloc_type);
	return region_alloc(&txn->region, size);
}

void *
tx_region_aligned_alloc(struct txn *txn, size_t size, size_t alignment,
			int alloc_type)
{
	tx_track_allocation(txn, size, alloc_type);
	return region_aligned_alloc(&txn->region, size, alignment);
}

size_t
tx_region_used(struct txn *txn) {
	return region_used(&txn->region);
}

void
tx_region_truncate(struct txn *txn) {
	region_truncate(&txn->region, sizeof(struct txn));

	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats, txn, 0);
	struct txn_stat *stat = *mh_txn_stats_node(memtx_tx_stat_manager.stats, pos);
	for (int i = 0; i < TXN_ALLOC_MAX; ++i) {
		histogram_discard(memtx_tx_stat_manager.stats_storage[i].hist, stat->stats[i]);
		memtx_tx_stat_manager.stats_storage[i].obj_count--;
	}
	txn_stat_forget(stat);
}

void
txn_stat_init()
{
	mempool_create(&memtx_tx_stat_manager.stat_item_pool, cord_slab_cache(), sizeof(struct txn_stat));
	memtx_tx_stat_manager.stats = mh_txn_stats_new();
	int64_t buckets[] = {1, 2, 3, 5, 10, 1000, 10000, 100000};
	for (size_t i = 0; i < TXN_ALLOC_MAX; ++i) {
		memtx_tx_stat_manager.stats_storage[i].hist = histogram_new(buckets, lengthof(buckets));
	}
}

void
txn_stat_free()
{
	mempool_destroy(&memtx_tx_stat_manager.stat_item_pool);
	for (size_t i = 0; i < TXN_ALLOC_MAX; ++i) {
		histogram_delete(memtx_tx_stat_manager.stats_storage[i].hist);
	}
}