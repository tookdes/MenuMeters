//
//  MenuMeterGPU.h
//  MenuMeters
//

#import <Cocoa/Cocoa.h>
#import "MenuMeterWorkarounds.h"

///////////////////////////////////////////////////////////////
//
// Constants
//
///////////////////////////////////////////////////////////////

// Menu item indexes
#define kGPUUsageInfoMenuIndex          1
#define kGPUFrequencyInfoMenuIndex      2
#define kGPUPowerInfoMenuIndex          3
#define kGPUANEPowerInfoMenuIndex       4
#define kGPUBandwidthInfoMenuIndex      5
#define kGPUMediaInfoMenuIndex          6
#define kGPUMemoryInfoMenuIndex         7

///////////////////////////////////////////////////////////////
//
// Preference information
//
///////////////////////////////////////////////////////////////

// Pref dictionary keys
#define kGPUIntervalPref                @"GPUInterval"
#define kGPUDisplayModePref             @"GPUDisplayMode"
#define kGPUGraphLengthPref             @"GPUGraphLength"
#define kGPUColorPref                   @"GPUColor"
#define kGPUTextColorPref               @"GPUTextColor"
#define kGPUANEColorPref                @"GPUANEColor"

// Shared status item layout
#define kMenuBarHorizontalPaddingPref   @"MenuBarHorizontalPadding"

// Display modes
enum {
    kGPUDisplayPercent                  = 1,
    kGPUDisplayGraph                    = 2,
    kGPUDisplayFrequency                = 4,
    kGPUDisplayPower                    = 8,
    kGPUDisplayANEPower                 = 16,
    kGPUDisplayBandwidth                = 32,
    kGPUDisplayMedia                    = 64,
    kGPUDisplayMemory                   = 128
};
#define kGPUDisplayDefault              (kGPUDisplayPercent | kGPUDisplayGraph)
#define kGPUDisplayValidFlags           (kGPUDisplayPercent | kGPUDisplayGraph | kGPUDisplayFrequency | kGPUDisplayPower | kGPUDisplayANEPower | kGPUDisplayBandwidth | kGPUDisplayMedia | kGPUDisplayMemory)

// Timer
#define kGPUUpdateIntervalMin           0.5
#define kGPUUpdateIntervalMax           10.0
#define kGPUUpdateIntervalDefault       1.0

// Graph display
#define kGPUGraphWidthMin               11
#define kGPUGraphWidthMax               88
#define kGPUGraphWidthDefault           33

// Shared status item layout
#define kMenuBarHorizontalPaddingMin    0
#define kMenuBarHorizontalPaddingMax    12
#define kMenuBarHorizontalPaddingDefault 0

// Colors
#define kGPUColorDefault                [NSColor colorWithDeviceRed:0.35f green:0.15f blue:0.75f alpha:1.0f]
#define kGPUTextColorDefault            [NSColor colorWithDeviceRed:0.0f green:0.45f blue:0.65f alpha:1.0f]
#define kGPUANEColorDefault             [NSColor orangeColor]
