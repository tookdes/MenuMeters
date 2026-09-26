//
//  gpu_reader.h
//  MenuMeters
//
//  Reads overall GPU utilization from the IOAccelerator performance
//  statistics exposed through the IOKit registry. Works on both Apple
//  Silicon (AGXAccelerator) and Intel/AMD (IOAccelerator) GPUs without
//  needing any special entitlements.
//

#ifndef gpu_reader_h
#define gpu_reader_h

#import <Foundation/Foundation.h>

// A snapshot of GPU statistics read from the IOAccelerator registry.
typedef struct {
	// Highest "Device Utilization %" reported by any GPU accelerator,
	// in the range 0-100. -1 if no GPU statistics could be read.
	float utilization;
	// In-use GPU/driver memory in bytes for that same accelerator.
	// 0 if unavailable.
	uint64_t inUseMemoryBytes;
} GPUStats;

// Reads the current GPU statistics. Picks the accelerator with the
// highest utilization (handles multi-GPU / eGPU setups).
extern GPUStats GPUReadStats(void);

#endif /* gpu_reader_h */
