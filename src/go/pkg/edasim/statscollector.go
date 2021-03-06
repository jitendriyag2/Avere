// Copyright (C) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE-CODE in the project root for license information.
package edasim

import (
	"context"
	"sync"
	"time"

	"github.com/Azure/Avere/src/go/pkg/log"
)

const (
	millisecondsSleep   = 10
	secondsBetweenStats = time.Duration(5) * time.Second
)

// StatsCollector is a go routine that prints the queue statistics on a schedule
func StatsCollector(ctx context.Context, syncWaitGroup *sync.WaitGroup) {
	log.Info.Printf("starting Stats Collector\n")
	defer syncWaitGroup.Done()
	defer log.Info.Printf("StatsCollector complete")
	start := time.Now()

	// for statistics
	lastJobsProcessedCount := 0
	lastProcessFilesWritten := 0
	lastCompletedJobsCount := 0
	lastUploadCount := 0
	lastErrorCount := 0
	jobsProcessedCount := 0
	processFilesWritten := 0
	completedJobsCount := 0
	uploadCount := 0
	errorCount := 0

	statsChannel := GetStatsChannel(ctx)

	ticker := time.NewTicker(time.Duration(millisecondsSleep) * time.Millisecond)
	defer ticker.Stop()

	keepRunning := true
	for keepRunning {
		select {
		case <-statsChannel.ChJobProcessed:
			jobsProcessedCount++
		case <-statsChannel.ChProcessedFilesWritten:
			processFilesWritten++
		case <-statsChannel.ChJobCompleted:
			completedJobsCount++
		case <-statsChannel.ChUpload:
			uploadCount++
		case <-statsChannel.ChError:
			errorCount++
		case <-ctx.Done():
			keepRunning = false
		case <-ticker.C:
		}
		if time.Since(start) > secondsBetweenStats || !keepRunning {
			start = start.Add(secondsBetweenStats)
			if jobsProcessedCount > 0 {
				log.Info.Printf("jobsProcessedCount: %d (delta %d)", jobsProcessedCount, (jobsProcessedCount - lastJobsProcessedCount))
				lastJobsProcessedCount = jobsProcessedCount
			}
			if processFilesWritten > 0 {
				log.Info.Printf("processFilesWritten: %d (delta %d)", processFilesWritten, (processFilesWritten - lastProcessFilesWritten))
				lastProcessFilesWritten = processFilesWritten
			}
			if completedJobsCount > 0 {
				log.Info.Printf("completedJobsCount: %d (delta %d)", completedJobsCount, (completedJobsCount - lastCompletedJobsCount))
				lastCompletedJobsCount = completedJobsCount
			}
			if uploadCount > 0 {
				log.Info.Printf("uploadCount: %d (delta %d)", uploadCount, (uploadCount - lastUploadCount))
				lastUploadCount = uploadCount
			}
			if errorCount > 0 {
				log.Info.Printf("errorCount: %d (delta %d)", errorCount, (errorCount - lastErrorCount))
				lastErrorCount = errorCount
			}
		}
	}
}
