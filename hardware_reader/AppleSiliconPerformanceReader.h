//
//  AppleSiliconPerformanceReader.h
//  MenuMeters
//
//  Shared Apple Silicon IOReport/SMC sampler for GPU, power, bandwidth, and media.
//

#import <Foundation/Foundation.h>

@interface AppleSiliconPerformanceSample : NSObject

@property(nonatomic) BOOL available;
@property(nonatomic) double gpuUsagePercent;       // <0 if unavailable
@property(nonatomic) NSInteger gpuFrequencyMHz;
@property(nonatomic) double cpuPowerWatts;         // <0 if unavailable
@property(nonatomic) double gpuPowerWatts;         // <0 if unavailable
@property(nonatomic) double gpuSRAMPowerWatts;
@property(nonatomic) double anePowerWatts;         // <0 if unavailable
@property(nonatomic) double bandwidthTotalGBs;     // <0 if unavailable
@property(nonatomic) double bandwidthMediaGBs;     // <0 if unavailable
@property(nonatomic) uint64_t gpuMemoryInUseBytes; // 0 if unavailable
@property(nonatomic) uint64_t gpuMemoryAllocBytes;

@end

@interface AppleSiliconPerformanceReader : NSObject

+ (instancetype)sharedReader;
- (AppleSiliconPerformanceSample *)currentSample;
- (BOOL)isAvailable;

@end
