//
//  gpu_reader.m
//  MenuMeters
//
//  Reads overall GPU utilization from the IOAccelerator performance
//  statistics exposed through the IOKit registry. This is the same
//  source Activity Monitor uses for its GPU history.
//

#import "gpu_reader.h"
#import <IOKit/IOKitLib.h>

// kIOMainPortDefault was introduced in the macOS 12 SDK as the replacement
// for the (now deprecated) kIOMasterPortDefault. Fall back to the old name
// when building against older SDKs so we compile everywhere.
#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

GPUStats GPUReadStats(void) {
    GPUStats stats = { .utilization = -1, .inUseMemoryBytes = 0 };

    CFMutableDictionaryRef matching = IOServiceMatching("IOAccelerator");
    if (!matching) {
        return stats;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return stats;
    }

    io_registry_entry_t entry = IO_OBJECT_NULL;
    while ((entry = IOIteratorNext(iterator))) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
            NSDictionary *props = (__bridge NSDictionary *)properties;
            NSDictionary *perf = props[@"PerformanceStatistics"];
            NSNumber *utilization = perf[@"Device Utilization %"];
            if (utilization) {
                float usage = utilization.floatValue;
                // Keep the busiest accelerator and its matching memory figure.
                if (usage > stats.utilization) {
                    stats.utilization = usage;
                    NSNumber *inUse = perf[@"In use system memory"];
                    stats.inUseMemoryBytes = inUse ? inUse.unsignedLongLongValue : 0;
                }
            }
        }
        if (properties) {
            CFRelease(properties);
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);

    return stats;
}
