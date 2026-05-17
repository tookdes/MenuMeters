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
    NSNumberFormatter *percentFormatter;
    NSNumberFormatter *wattsFormatter;
    NSColor *gpuColor;
    NSColor *gpuTextColor;
    NSColor *aneColor;
    NSColor *fgMenuThemeColor;
}

@end
