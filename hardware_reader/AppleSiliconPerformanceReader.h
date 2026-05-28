//
//  AppleSiliconPerformanceReader.h
//  MenuMeters
//

#import <Foundation/Foundation.h>

@interface AppleSiliconPerformanceSample : NSObject

@property(nonatomic) BOOL available;
@property(nonatomic) double gpuUsagePercent;
@property(nonatomic) NSInteger gpuFrequencyMHz;
@property(nonatomic) double cpuPowerWatts;
@property(nonatomic) double gpuPowerWatts;
@property(nonatomic) double gpuSRAMPowerWatts;
@property(nonatomic) double anePowerWatts;

@end

@interface AppleSiliconPerformanceReader : NSObject

+ (instancetype)sharedReader;
- (AppleSiliconPerformanceSample *)currentSample;
- (BOOL)isAvailable;

@end
