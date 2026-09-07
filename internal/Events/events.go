package events

import (
	"time"

	"github.com/Vipul984/pg-monitor/pkg"
)

type MetricEvent struct{
	Source string
	MetricName pkg.MetricName
	Value int64
	Time time.Time
}