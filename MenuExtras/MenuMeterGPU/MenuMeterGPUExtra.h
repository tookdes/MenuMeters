//
//  MenuMeterGPUExtra.h
//  MenuMeters
//

#import <Cocoa/Cocoa.h>
#import "MenuMeters.h"
#import "MenuMeterDefaults.h"
#import "MenuMeterGPU.h"
#import "AppleSiliconPerformanceReader.h"

@interface MenuMeterGPUExtra : NSMenuExtra {
    NSMenu *extraMenu;
    MenuMeterDefaults *ourPrefs;
    AppleSiliconPerformanceReader *performanceReader;
    NSMutableArray *gpuHistory;
    AppleSiliconPerformanceSample *currentSample;
    // Public-API fallback (ported from YuyaIwata/MenuMeters add-gpu-meter
    // branch, GPL-2.0): IOAccelerator PerformanceStatistics utilization and
    // memory for the busiest accelerator. Refreshed alongside currentSample;
    // used only when the private IOReport sample has no usage/memory.
    // -1 usage / 0 memory = unavailable.
    double publicGpuUsageFallback;
    uint64_t publicGpuMemoryFallback;
    NSNumberFormatter *percentFormatter;
    NSNumberFormatter *wattsFormatter;
    NSColor *gpuColor;
    NSColor *gpuTextColor;
    NSColor *aneColor;
    NSColor *fgMenuThemeColor;
}

@end
