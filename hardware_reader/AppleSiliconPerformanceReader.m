//
//  AppleSiliconPerformanceReader.m
//  MenuMeters
//
//  IOReport-based GPU/ANE sampling. The IOReport channel choices and
//  performance-state interpretation are based on the MIT-licensed mactop
//  project by Carsen Klock: https://github.com/metaspartan/mactop
//

#import "AppleSiliconPerformanceReader.h"
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#include <stdint.h>

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group,
                                                   CFStringRef subgroup,
                                                   uint64_t a,
                                                   uint64_t b,
                                                   uint64_t c);
extern void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef unused);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *a,
                                                          CFMutableDictionaryRef channels,
                                                          CFMutableDictionaryRef *out,
                                                          uint64_t d,
                                                          CFTypeRef e);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
                                             CFMutableDictionaryRef channels,
                                             CFTypeRef unused);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef a,
                                                  CFDictionaryRef b,
                                                  CFTypeRef unused);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef item);
extern int32_t IOReportStateGetCount(CFDictionaryRef item);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef item, int32_t idx);
extern int64_t IOReportStateGetResidency(CFDictionaryRef item, int32_t idx);

@implementation AppleSiliconPerformanceSample
@end

@interface AppleSiliconPerformanceReader ()
@end

@implementation AppleSiliconPerformanceReader {
    BOOL initialized;
    BOOL available;
    IOReportSubscriptionRef subscription;
    CFMutableDictionaryRef channels;
    CFDictionaryRef previousSample;
    NSDate *previousSampleDate;
    uint32_t gpuFrequencies[64];
    int gpuFrequencyCount;
}

+ (instancetype)sharedReader
{
    static AppleSiliconPerformanceReader *reader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reader = [[AppleSiliconPerformanceReader alloc] init];
    });
    return reader;
}

- (void)dealloc
{
    if (previousSample) {
        CFRelease(previousSample);
    }
    if (channels) {
        CFRelease(channels);
    }
}

static BOOL MMGetCString(CFStringRef string, char *buffer, size_t size)
{
    if (!string || !buffer || size == 0) {
        return NO;
    }
    buffer[0] = 0;
    return CFStringGetCString(string, buffer, size, kCFStringEncodingUTF8);
}

static double MMEnergyToWatts(int64_t energy, CFStringRef unitRef, NSTimeInterval elapsedSeconds)
{
    if (elapsedSeconds <= 0.0) {
        elapsedSeconds = 1.0;
    }

    double rate = (double)energy / elapsedSeconds;
    if (!unitRef) {
        return rate / 1000000.0;
    }

    char unit[32] = {0};
    MMGetCString(unitRef, unit, sizeof(unit));
    for (int i = 0; unit[i]; i++) {
        if (unit[i] == ' ') {
            unit[i] = '\0';
            break;
        }
    }

    if (strcmp(unit, "mJ") == 0) {
        return rate / 1000.0;
    }
    if (strcmp(unit, "uJ") == 0) {
        return rate / 1000000.0;
    }
    if (strcmp(unit, "nJ") == 0) {
        return rate / 1000000000.0;
    }
    return rate / 1000000.0;
}

static BOOL MMStringStartsWith(CFStringRef string, const char *prefix)
{
    if (!string || !prefix) {
        return NO;
    }
    CFStringRef prefixString = CFStringCreateWithCString(kCFAllocatorDefault, prefix, kCFStringEncodingUTF8);
    if (!prefixString) {
        return NO;
    }
    BOOL result = CFStringHasPrefix(string, prefixString);
    CFRelease(prefixString);
    return result;
}

- (void)loadGPUFrequencies
{
    if (gpuFrequencyCount > 0) {
        return;
    }

    io_iterator_t iterator = 0;
    CFMutableDictionaryRef matching = IOServiceMatching("AppleARMIODevice");
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) != kIOReturnSuccess) {
        return;
    }

    io_object_t entry = 0;
    while ((entry = IOIteratorNext(iterator)) != 0) {
        io_name_t name;
        IORegistryEntryGetName(entry, name);
        if (strcmp(name, "pmgr") != 0 && strcmp(name, "clpc") != 0) {
            IOObjectRelease(entry);
            continue;
        }

        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess) {
            CFDataRef bestData = (CFDataRef)CFDictionaryGetValue(properties, CFSTR("voltage-states9-sram"));
            if (!bestData) {
                bestData = (CFDataRef)CFDictionaryGetValue(properties, CFSTR("voltage-states9"));
            }

            if (!bestData) {
                CFIndex count = CFDictionaryGetCount(properties);
                const void **keys = calloc((size_t)count, sizeof(void *));
                const void **values = calloc((size_t)count, sizeof(void *));
                if (keys && values) {
                    CFDictionaryGetKeysAndValues(properties, keys, values);
                    for (CFIndex i = 0; i < count; i++) {
                        CFStringRef key = (CFStringRef)keys[i];
                        if (MMStringStartsWith(key, "voltage-states")) {
                            bestData = (CFDataRef)values[i];
                            break;
                        }
                    }
                }
                free(keys);
                free(values);
            }

            if (bestData && CFGetTypeID(bestData) == CFDataGetTypeID()) {
                CFIndex length = CFDataGetLength(bestData);
                const UInt8 *bytes = CFDataGetBytePtr(bestData);
                int total = (int)MIN(length / 8, 64);
                gpuFrequencyCount = 0;
                for (int i = 0; i < total; i++) {
                    uint32_t rawFrequency = 0;
                    memcpy(&rawFrequency, bytes + (i * 8), sizeof(rawFrequency));
                    uint32_t mhz = 0;
                    if (rawFrequency >= 100000000) {
                        mhz = rawFrequency / 1000000;
                    } else if (rawFrequency >= 100000) {
                        mhz = rawFrequency / 1000;
                    }
                    if (mhz > 0) {
                        gpuFrequencies[gpuFrequencyCount++] = mhz;
                    }
                }
            }
            CFRelease(properties);
        }

        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
}

- (BOOL)initializeIfNeeded
{
    if (initialized) {
        return available;
    }
    initialized = YES;

    CFDictionaryRef energyChannels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!energyChannels) {
        available = NO;
        return NO;
    }

    CFDictionaryRef gpuChannels = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), NULL, 0, 0, 0);
    if (gpuChannels) {
        IOReportMergeChannels(energyChannels, gpuChannels, NULL);
        CFRelease(gpuChannels);
    }

    CFDictionaryRef pmpChannels = IOReportCopyChannelsInGroup(CFSTR("PMP"), NULL, 0, 0, 0);
    if (pmpChannels) {
        IOReportMergeChannels(energyChannels, pmpChannels, NULL);
        CFRelease(pmpChannels);
    }

    channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(energyChannels), energyChannels);
    CFRelease(energyChannels);
    if (!channels) {
        available = NO;
        return NO;
    }

    CFMutableDictionaryRef subscribedChannels = NULL;
    subscription = IOReportCreateSubscription(NULL, channels, &subscribedChannels, 0, NULL);
    if (subscribedChannels) {
        CFRelease(subscribedChannels);
    }
    if (!subscription) {
        available = NO;
        return NO;
    }

    [self loadGPUFrequencies];
    previousSample = IOReportCreateSamples(subscription, channels, NULL);
    previousSampleDate = [NSDate date];
    available = previousSample != NULL;
    return available;
}

- (BOOL)isAvailable
{
    return [self initializeIfNeeded];
}

- (AppleSiliconPerformanceSample *)currentSample
{
    AppleSiliconPerformanceSample *sample = [[AppleSiliconPerformanceSample alloc] init];
    sample.gpuUsagePercent = -1.0;
    sample.gpuFrequencyMHz = 0;
    sample.gpuPowerWatts = -1.0;
    sample.gpuSRAMPowerWatts = 0.0;
    sample.anePowerWatts = -1.0;

    if (![self initializeIfNeeded]) {
        return sample;
    }

    CFDictionaryRef currentSample = IOReportCreateSamples(subscription, channels, NULL);
    NSDate *currentDate = [NSDate date];
    if (!currentSample) {
        return sample;
    }

    if (!previousSample || !previousSampleDate) {
        if (previousSample) {
            CFRelease(previousSample);
        }
        previousSample = currentSample;
        previousSampleDate = currentDate;
        sample.available = YES;
        return sample;
    }

    NSTimeInterval elapsed = [currentDate timeIntervalSinceDate:previousSampleDate];
    CFDictionaryRef delta = IOReportCreateSamplesDelta(previousSample, currentSample, NULL);
    CFRelease(previousSample);
    previousSample = currentSample;
    previousSampleDate = currentDate;

    if (!delta) {
        return sample;
    }

    CFArrayRef reportChannels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    CFIndex count = reportChannels ? CFArrayGetCount(reportChannels) : 0;
    BOOL foundAnyMetric = NO;

    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef item = (CFDictionaryRef)CFArrayGetValueAtIndex(reportChannels, i);
        if (!item) {
            continue;
        }

        char group[64] = {0};
        char channel[256] = {0};
        MMGetCString(IOReportChannelGetGroup(item), group, sizeof(group));
        MMGetCString(IOReportChannelGetChannelName(item), channel, sizeof(channel));

        if (strcmp(group, "Energy Model") == 0) {
            int64_t energy = IOReportSimpleGetIntegerValue(item, 0);
            double watts = MMEnergyToWatts(energy, IOReportChannelGetUnitLabel(item), elapsed);
            if (strcmp(channel, "GPU Energy") == 0) {
                sample.gpuPowerWatts = MAX(0.0, watts);
                foundAnyMetric = YES;
            } else if (strncmp(channel, "GPU SRAM", 8) == 0) {
                sample.gpuSRAMPowerWatts += MAX(0.0, watts);
                foundAnyMetric = YES;
            } else if (strncmp(channel, "ANE", 3) == 0) {
                if (sample.anePowerWatts < 0.0) {
                    sample.anePowerWatts = 0.0;
                }
                sample.anePowerWatts += MAX(0.0, watts);
                foundAnyMetric = YES;
            }
        } else if (strcmp(group, "PMP") == 0) {
            char subgroup[128] = {0};
            MMGetCString(IOReportChannelGetSubGroup(item), subgroup, sizeof(subgroup));
            if (strcmp(subgroup, "Energy Counters") == 0) {
                int64_t energy = IOReportSimpleGetIntegerValue(item, 0);
                double watts = MMEnergyToWatts(energy, IOReportChannelGetUnitLabel(item), elapsed);
                if (strcmp(channel, "ANE") == 0) {
                    if (sample.anePowerWatts < 0.0) {
                        sample.anePowerWatts = 0.0;
                    }
                    sample.anePowerWatts += MAX(0.0, watts);
                    foundAnyMetric = YES;
                } else if (strcmp(channel, "GPU") == 0) {
                    if (sample.gpuPowerWatts < 0.0) {
                        sample.gpuPowerWatts = MAX(0.0, watts);
                        foundAnyMetric = YES;
                    }
                } else if (strncmp(channel, "GPU SRAM", 8) == 0) {
                    sample.gpuSRAMPowerWatts += MAX(0.0, watts);
                    foundAnyMetric = YES;
                }
            }
        } else if (strcmp(group, "GPU Stats") == 0) {
            char subgroup[128] = {0};
            MMGetCString(IOReportChannelGetSubGroup(item), subgroup, sizeof(subgroup));
            if (strcmp(subgroup, "GPU Performance States") == 0 && strcmp(channel, "GPUPH") == 0) {
                int32_t stateCount = IOReportStateGetCount(item);
                int64_t totalTime = 0;
                int64_t activeTime = 0;
                double weightedFrequency = 0.0;
                int activeStateIndex = 0;

                for (int32_t stateIndex = 0; stateIndex < stateCount; stateIndex++) {
                    int64_t residency = IOReportStateGetResidency(item, stateIndex);
                    totalTime += residency;

                    char stateName[64] = {0};
                    MMGetCString(IOReportStateGetNameForIndex(item, stateIndex), stateName, sizeof(stateName));
                    if (strcmp(stateName, "OFF") != 0 &&
                        strcmp(stateName, "IDLE") != 0 &&
                        strcmp(stateName, "DOWN") != 0) {
                        activeTime += residency;
                        if (gpuFrequencyCount > 0 && activeStateIndex < gpuFrequencyCount) {
                            weightedFrequency += (double)gpuFrequencies[activeStateIndex] * (double)residency;
                        }
                        activeStateIndex++;
                    }
                }

                if (totalTime > 0) {
                    sample.gpuUsagePercent = MIN(100.0, MAX(0.0, ((double)activeTime / (double)totalTime) * 100.0));
                    foundAnyMetric = YES;
                }
                if (activeTime > 0 && gpuFrequencyCount > 0) {
                    sample.gpuFrequencyMHz = (NSInteger)llround(weightedFrequency / (double)activeTime);
                }
            }
        }
    }

    CFRelease(delta);
    sample.available = foundAnyMetric;
    return sample;
}

@end
