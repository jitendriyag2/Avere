// Copyright (C) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE-CODE in the project root for license information.
package edasim

import (
	"encoding/json"
	"fmt"
	"path"

	"github.com/Azure/Avere/src/go/pkg/file"
	"github.com/Azure/Avere/src/go/pkg/log"
	"github.com/Azure/Avere/src/go/pkg/random"
)

// JobConfigFile represents a job configuration file
type JobConfigFile struct {
	Name           string
	IsCompleteFile bool
	JobRun         JobRun
	PaddedString   string
}

// InitializeJobConfigFile sets the unique name of the job configuration and the batch name
func InitializeJobConfigFile(name string, jobRun *JobRun) *JobConfigFile {
	return initializeJobFile(name, false, jobRun)
}

// InitializeJobCompleteFile sets the unique name of the job configuration and the batch name and is used to signify job completion
func InitializeJobCompleteFile(name string, jobRun *JobRun) *JobConfigFile {
	return initializeJobFile(name, true, jobRun)
}

func initializeJobFile(name string, isCompleteFile bool, jobRun *JobRun) *JobConfigFile {
	return &JobConfigFile{
		Name:           name,
		IsCompleteFile: isCompleteFile,
		JobRun:         *jobRun,
	}
}

// ReadJobConfigFile reads a job config file from disk
func ReadJobConfigFile(reader *file.ReaderWriter, filename string) (*JobConfigFile, error) {
	log.Debug.Printf("[ReadJobConfigFile %s", filename)
	defer log.Debug.Printf("ReadJobConfigFile %s]", filename)
	uniqueName, runName := GetBatchNamePartsFromJobRun(filename)
	byteValue, err := reader.ReadFile(filename, uniqueName, runName)
	if err != nil {
		return nil, err
	}

	var result JobConfigFile
	if err := json.Unmarshal([]byte(byteValue), &result); err != nil {
		return nil, err
	}

	// clear the padded string for GC
	result.PaddedString = ""
	return &result, nil
}

// WriteJobConfigFile writes the job configuration file to disk, padding it so it makes the necessary size
func (j *JobConfigFile) WriteJobConfigFile(writer *file.ReaderWriter, filepath string, fileSize int) (string, error) {
	filename := ""
	if j.IsCompleteFile == true {
		filename = path.Join(filepath, j.getJobConfigCompleteName())
	} else {
		filename = path.Join(filepath, j.getJobConfigName())
	}

	log.Debug.Printf("[WriteJobConfigFile(%s)", filename)
	defer log.Debug.Printf("WriteJobConfigFile(%s)]", filename)
	// learn the size of the current object
	data, err := json.Marshal(j)
	if err != nil {
		return "", err
	}

	// pad and re-martial to match the bytes
	padLength := (KB * fileSize) - len(data)
	if padLength > 0 {
		j.PaddedString = random.RandStringRunesUltraFast(padLength / KB)
		data, err = json.Marshal(j)
		if err != nil {
			return "", err
		}
	}

	uniqueName, runName := GetBatchNamePartsFromJobRun(filename)
	if err := writer.WriteFile(filename, []byte(data), uniqueName, runName); err != nil {
		return "", err
	}

	return filename, nil
}

func (j *JobConfigFile) getJobConfigName() string {
	return fmt.Sprintf("%s.job", j.Name)
}

func (j *JobConfigFile) getJobConfigCompleteName() string {
	return fmt.Sprintf("%s.complete", j.getJobConfigName())
}
