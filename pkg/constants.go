package pkg

const (
	MetricRowsInserted MetricName = "rows_inserted"
	MetricRowsUpdated  MetricName = "rows_updated"
	MetricRowsDeleted  MetricName = "rows_deleted"
	MetricSeqScan      MetricName = "seq_scan"
	MetricIdxScan      MetricName = "idx_scan"
	MetricLiveTuples   MetricName = "n_live_tup"
	MetricDeadTuples   MetricName = "n_dead_tup"
)
