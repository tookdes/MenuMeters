//
//  AppleSiliconPerformanceReader.m
//  MenuMeters
//
//  IOReport-based GPU / power / memory-bandwidth sampling for Apple Silicon.
//  Channel strategies reimplemented from public reverse-engineering patterns
//  (Energy Model + PMP Energy Counters, AMC Stats / PMP DCS BW fallback).
//

#import "AppleSiliconPerformanceReader.h"
#import "smc_reader.h"
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <math.h>
#include <string.h>
#include <string.h>
#include <sys/sysctl.h>

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
extern int IOReportChannelGetFormat(CFDictionaryRef item);
extern int32_t IOReportStateGetCount(CFDictionaryRef item);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef item, int32_t idx);
extern int64_t IOReportStateGetResidency(CFDictionaryRef item, int32_t idx);

enum {
    kMMIOReportFormatSimple = 1,
    kMMIOReportFormatState = 2,
};

typedef NS_ENUM(NSInteger, MMBWRequestor) {
    MMBWRequestorTotal = 0,
    MMBWRequestorCPU,
    MMBWRequestorGPU,
    MMBWRequestorMedia,
    MMBWRequestorOther,
};

typedef NS_ENUM(NSInteger, MMBWMode) {
    MMBWModeNone = 0,
    MMBWModeAMCStats,
    MMBWModePMPHistogram,
};

@implementation AppleSiliconPerformanceSample
@end

@implementation AppleSiliconPerformanceReader {
    BOOL initialized;
    BOOL available;
    BOOL isA18Like;

    IOReportSubscriptionRef subscription;
    CFMutableDictionaryRef channels;
    CFDictionaryRef previousSample;
    NSTimeInterval previousSampleTime;

    MMBWMode bandwidthMode;
    IOReportSubscriptionRef bandwidthSubscription;
    CFMutableDictionaryRef bandwidthChannels;
    CFDictionaryRef previousBandwidthSample;
    NSTimeInterval previousBandwidthSampleTime;

    io_service_t acceleratorService;

    AppleSiliconPerformanceSample *cachedSample;
    NSTimeInterval cachedSampleTime;
    NSTimeInterval lastInitializationAttempt;
    uint32_t gpuFrequencies[64];
    int gpuFrequencyCount;
}

+ (instancetype)sharedReader
{
    static AppleSiliconPerformanceReader *reader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reader = [[AppleSiliconPerformanceReader alloc] init];
        [reader runSelfCheck];
    });
    return reader;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        acceleratorService = 0;
        bandwidthMode = MMBWModeNone;
        isA18Like = [self.class brandLooksLikeA18];
    }
    return self;
}

- (void)dealloc
{
    if (previousSample) CFRelease(previousSample);
    if (subscription) CFRelease(subscription);
    if (channels) CFRelease(channels);
    if (previousBandwidthSample) CFRelease(previousBandwidthSample);
    if (bandwidthSubscription) CFRelease(bandwidthSubscription);
    if (bandwidthChannels) CFRelease(bandwidthChannels);
    if (acceleratorService) IOObjectRelease(acceleratorService);
}

#pragma mark - helpers

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
        return 0.0;
    }

    double rate = (double)energy / elapsedSeconds;
    if (!unitRef) {
        return rate / 1000.0; // Energy Model defaults to mJ when unlabeled
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
    if (strcmp(unit, "J") == 0) {
        return rate;
    }
    // unlabeled Energy Model counters are mJ in practice
    return rate / 1000.0;
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

static BOOL MMChannelNameEquals(const char *channel, const char *name)
{
    return channel && name && strcmp(channel, name) == 0;
}

static BOOL MMIsType(CFTypeRef value, CFTypeID typeID)
{
    return value && CFGetTypeID(value) == typeID;
}

static void MMMergeChannels(CFMutableDictionaryRef *destination, CFDictionaryRef source)
{
    if (!source) {
        return;
    }
    if (!*destination) {
        *destination = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(source), source);
    } else {
        IOReportMergeChannels(*destination, source, NULL);
    }
}

static BOOL MMHasPrefix(const char *s, const char *prefix)
{
    return s && prefix && strncmp(s, prefix, strlen(prefix)) == 0;
}

static void MMUppercaseInPlace(char *s)
{
    if (!s) return;
    for (; *s; s++) {
        if (*s >= 'a' && *s <= 'z') {
            *s = (char)(*s - 'a' + 'A');
        }
    }
}

// ponytail: pure helpers unit-tested via runSelfCheck
static const char *const kMMRWSuffixes[] = {
    " RD/WR + RD/WR",
    " RD/WR/RDWR",
    " RD/WR",
    " RD",
    " WR",
    NULL
};

static BOOL MMHasReadWriteToken(const char *upperName)
{
    if (!upperName) return NO;
    size_t len = strlen(upperName);
    for (int i = 0; kMMRWSuffixes[i]; i++) {
        size_t sl = strlen(kMMRWSuffixes[i]);
        if (len >= sl && strcmp(upperName + len - sl, kMMRWSuffixes[i]) == 0) {
            return YES;
        }
    }
    return NO;
}

static void MMStripReadWriteSuffix(const char *upperName, char *out, size_t outSize)
{
    if (!out || outSize == 0) return;
    out[0] = 0;
    if (!upperName) return;
    size_t len = strlen(upperName);
    for (int i = 0; kMMRWSuffixes[i]; i++) {
        size_t sl = strlen(kMMRWSuffixes[i]);
        if (len >= sl && strcmp(upperName + len - sl, kMMRWSuffixes[i]) == 0) {
            size_t copy = len - sl;
            if (copy >= outSize) copy = outSize - 1;
            memcpy(out, upperName, copy);
            out[copy] = 0;
            return;
        }
    }
    strncpy(out, upperName, outSize - 1);
    out[outSize - 1] = 0;
}

static BOOL MMContainsUnitPrefix(const char *requestor, const char *unitPrefix)
{
    if (!requestor || !unitPrefix) return NO;
    if (MMHasPrefix(requestor, unitPrefix)) return YES;
    char needle[64];
    snprintf(needle, sizeof(needle), " %s", unitPrefix);
    return strstr(requestor, needle) != NULL;
}

static MMBWRequestor MMClassifyAMCRequestor(const char *requestor)
{
    if (!requestor) return MMBWRequestorOther;
    if (strcmp(requestor, "DCS") == 0) return MMBWRequestorTotal;
    if (MMContainsUnitPrefix(requestor, "ECPU") || MMContainsUnitPrefix(requestor, "PCPU")) {
        return MMBWRequestorCPU;
    }
    if (MMContainsUnitPrefix(requestor, "GFX")) return MMBWRequestorGPU;
    if (MMContainsUnitPrefix(requestor, "VENC") || MMContainsUnitPrefix(requestor, "VDEC") ||
        MMContainsUnitPrefix(requestor, "ISP") || MMContainsUnitPrefix(requestor, "JPG") ||
        MMContainsUnitPrefix(requestor, "JPEG") || strstr(requestor, "PRORES") ||
        strstr(requestor, "CODEC")) {
        return MMBWRequestorMedia;
    }
    return MMBWRequestorOther;
}

static MMBWRequestor MMClassifyPMPRequestor(const char *name)
{
    if (!name) return MMBWRequestorOther;
    char upper[256];
    strncpy(upper, name, sizeof(upper) - 1);
    upper[sizeof(upper) - 1] = 0;
    MMUppercaseInPlace(upper);
    if (MMHasPrefix(upper, "EACC") || MMHasPrefix(upper, "PACC")) return MMBWRequestorCPU;
    if (MMHasPrefix(upper, "AGX")) return MMBWRequestorGPU;
    if (MMHasPrefix(upper, "ISP") || MMHasPrefix(upper, "JPEG") || MMHasPrefix(upper, "PRORES") ||
        MMHasPrefix(upper, "SCODEC") || MMHasPrefix(upper, "AVE") || MMHasPrefix(upper, "AVD")) {
        return MMBWRequestorMedia;
    }
    return MMBWRequestorOther;
}

static double MMParseHistogramBucketGBs(const char *stateName)
{
    if (!stateName) return -1.0;
    // "   1GB/s" / "  32GB/s"
    while (*stateName == ' ' || *stateName == '\t') stateName++;
    char buf[64];
    strncpy(buf, stateName, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = 0;
    MMUppercaseInPlace(buf);
    size_t len = strlen(buf);
    if (len < 5 || strcmp(buf + len - 4, "GB/S") != 0) return -1.0;
    buf[len - 4] = 0;
    while (len > 0 && buf[strlen(buf) - 1] == ' ') {
        buf[strlen(buf) - 1] = 0;
    }
    char *end = NULL;
    double v = strtod(buf, &end);
    if (end == buf) return -1.0;
    return v;
}

+ (BOOL)brandLooksLikeA18
{
    char brand[256] = {0};
    size_t size = sizeof(brand);
    if (sysctlbyname("machdep.cpu.brand_string", brand, &size, NULL, 0) != 0) {
        return NO;
    }
    // MacBook Neo / A18-class SoCs show up with A18 in the brand string when present.
    return strstr(brand, "A18") != NULL || strstr(brand, "a18") != NULL;
}

- (void)runSelfCheck
{
    // Keep pure classifiers honest without a test harness.
    NSCAssert(MMHasReadWriteToken("ECPU DCS RD"), @"rw token");
    NSCAssert(MMHasReadWriteToken("DIE0 ECPU0 DCS RD/WR + RD/WR"), @"rw combined");
    NSCAssert(!MMHasReadWriteToken("ECPU DCS CYCLES"), @"non-rw");
    char stripped[128];
    MMStripReadWriteSuffix("DIE0 ECPU0 DCS RD/WR", stripped, sizeof(stripped));
    NSCAssert(strcmp(stripped, "DIE0 ECPU0 DCS") == 0, @"strip");
    NSCAssert(MMClassifyAMCRequestor("DCS") == MMBWRequestorTotal, @"total");
    NSCAssert(MMClassifyAMCRequestor("DIE0 ECPU0 DCS") == MMBWRequestorCPU, @"cpu prefix");
    NSCAssert(MMClassifyAMCRequestor("GFX DCS") == MMBWRequestorGPU, @"gpu");
    NSCAssert(MMClassifyAMCRequestor("VENC DCS") == MMBWRequestorMedia, @"media");
    NSCAssert(MMClassifyPMPRequestor("EACC0") == MMBWRequestorCPU, @"pmp cpu");
    NSCAssert(MMClassifyPMPRequestor("AGX") == MMBWRequestorGPU, @"pmp gpu");
    NSCAssert(fabs(MMParseHistogramBucketGBs("  12GB/s") - 12.0) < 0.001, @"bucket");
}

#pragma mark - topology / GPU clock table

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
                        if (MMIsType(key, CFStringGetTypeID()) && MMStringStartsWith(key, "voltage-states")) {
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

- (void)findAcceleratorService
{
    if (acceleratorService) {
        return;
    }
    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOAccelerator"), &iter) != KERN_SUCCESS) {
        return;
    }
    io_service_t svc;
    while ((svc = IOIteratorNext(iter)) != 0) {
        CFTypeRef perf = IORegistryEntryCreateCFProperty(svc, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (perf && CFGetTypeID(perf) == CFDictionaryGetTypeID()) {
            if (CFDictionaryGetValue((CFDictionaryRef)perf, CFSTR("In use system memory"))) {
                acceleratorService = svc;
                CFRelease(perf);
                break;
            }
        }
        if (perf) CFRelease(perf);
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
}

- (void)readGPUMemoryIntoSample:(AppleSiliconPerformanceSample *)sample
{
    [self findAcceleratorService];
    if (!acceleratorService) {
        return;
    }
    // Single-property fetch is much cheaper than copying the full property table.
    CFTypeRef perf = IORegistryEntryCreateCFProperty(acceleratorService,
                                                     CFSTR("PerformanceStatistics"),
                                                     kCFAllocatorDefault,
                                                     0);
    if (!perf || CFGetTypeID(perf) != CFDictionaryGetTypeID()) {
        if (perf) CFRelease(perf);
        return;
    }
    CFDictionaryRef dict = (CFDictionaryRef)perf;
    CFNumberRef inUse = CFDictionaryGetValue(dict, CFSTR("In use system memory"));
    CFNumberRef alloc = CFDictionaryGetValue(dict, CFSTR("Alloc system memory"));
    int64_t v = 0;
    if (inUse && CFNumberGetValue(inUse, kCFNumberSInt64Type, &v) && v > 0) {
        sample.gpuMemoryInUseBytes = (uint64_t)v;
    }
    if (alloc && CFNumberGetValue(alloc, kCFNumberSInt64Type, &v) && v > 0) {
        sample.gpuMemoryAllocBytes = (uint64_t)v;
    }
    CFRelease(perf);
}

static double MMSMCReadDouble(const char *key)
{
    if (!key) return -1.0;
    if (SMCOpen() != kIOReturnSuccess) return -1.0;
    SMCKeyValue val = {};
    kern_return_t rc = SMCReadKey(toSMCCode(key), &val);
    double result = -1.0;
    if (rc == kIOReturnSuccess) {
        if (val.info.dataType.type == SMC_DATATYPE_FLT.type) {
            float f = 0;
            memcpy(&f, val.bytes, sizeof(float));
            result = f;
        } else if (val.info.dataType.type == SMC_DATATYPE_SP78.type) {
            result = SP78_TO_CELSIUS(val.bytes);
        } else if (val.info.dataType.type == SMC_DATATYPE_FPE2.type) {
            result = FPE2_TO_UINT32(val.bytes);
        } else if (val.info.dataType.type == SMC_DATATYPE_UINT16.type) {
            result = UI16_TO_UINT32(val.bytes);
        } else if (val.info.dataType.type == SMC_DATATYPE_UINT32.type) {
            result = UI32_TO_UINT32(val.bytes);
        } else if (val.info.dataType.type == SMC_DATATYPE_UINT8.type) {
            result = UI8_TO_UINT32(val.bytes);
        }
    }
    SMCClose();
    return result;
}

#pragma mark - init subscriptions

- (BOOL)initializeBandwidthIfNeeded
{
    if (bandwidthMode != MMBWModeNone) {
        return bandwidthSubscription != NULL;
    }

    // Classic M-series path.
    CFDictionaryRef amc = IOReportCopyChannelsInGroup(CFSTR("AMC Stats"), NULL, 0, 0, 0);
    if (amc) {
        CFMutableDictionaryRef owned = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(amc), amc);
        CFRelease(amc);
        CFMutableDictionaryRef subbed = NULL;
        IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, owned, &subbed, 0, NULL);
        if (subbed) CFRelease(subbed);
        if (sub) {
            bandwidthChannels = owned;
            bandwidthSubscription = sub;
            bandwidthMode = MMBWModeAMCStats;
            previousBandwidthSample = IOReportCreateSamples(bandwidthSubscription, bandwidthChannels, NULL);
            previousBandwidthSampleTime = [NSProcessInfo processInfo].systemUptime;
            return YES;
        }
        CFRelease(owned);
    }

    // Fallback: PMP DCS BW residency histogram (some OS/chip combos block AMC Stats subscription).
    CFDictionaryRef pmp = IOReportCopyChannelsInGroup(CFSTR("PMP"), CFSTR("DCS BW"), 0, 0, 0);
    if (pmp) {
        CFMutableDictionaryRef owned = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(pmp), pmp);
        CFRelease(pmp);
        CFMutableDictionaryRef subbed = NULL;
        IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, owned, &subbed, 0, NULL);
        if (subbed) CFRelease(subbed);
        if (sub) {
            bandwidthChannels = owned;
            bandwidthSubscription = sub;
            bandwidthMode = MMBWModePMPHistogram;
            previousBandwidthSample = IOReportCreateSamples(bandwidthSubscription, bandwidthChannels, NULL);
            previousBandwidthSampleTime = [NSProcessInfo processInfo].systemUptime;
            return YES;
        }
        CFRelease(owned);
    }

    bandwidthMode = MMBWModeNone;
    return NO;
}

- (BOOL)initializeIfNeeded
{
    if (initialized) {
        return available;
    }

    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    if (lastInitializationAttempt > 0.0 && now - lastInitializationAttempt < 1.0) {
        return NO;
    }
    lastInitializationAttempt = now;

    if (previousSample) {
        CFRelease(previousSample);
        previousSample = NULL;
    }
    if (subscription) {
        CFRelease(subscription);
        subscription = NULL;
    }
    if (channels) {
        CFRelease(channels);
        channels = NULL;
    }

    CFDictionaryRef energyChannels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    MMMergeChannels(&channels, energyChannels);
    if (energyChannels) CFRelease(energyChannels);

    // Top-level "Energy Counters" group (some chips).
    CFDictionaryRef energyCounterChannels = IOReportCopyChannelsInGroup(CFSTR("Energy Counters"), NULL, 0, 0, 0);
    MMMergeChannels(&channels, energyCounterChannels);
    if (energyCounterChannels) CFRelease(energyCounterChannels);

    // Only the PMP energy subgroup — avoid subscribing the whole PMP tree (BW noise / cost).
    CFDictionaryRef pmpEnergy = IOReportCopyChannelsInGroup(CFSTR("PMP"), CFSTR("Energy Counters"), 0, 0, 0);
    MMMergeChannels(&channels, pmpEnergy);
    if (pmpEnergy) CFRelease(pmpEnergy);

    CFDictionaryRef gpuChannels = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), NULL, 0, 0, 0);
    MMMergeChannels(&channels, gpuChannels);
    if (gpuChannels) CFRelease(gpuChannels);

    if (!channels) {
        available = NO;
        return NO;
    }

    CFMutableDictionaryRef subscribedChannels = NULL;
    subscription = IOReportCreateSubscription(NULL, channels, &subscribedChannels, 0, NULL);
    if (subscribedChannels) CFRelease(subscribedChannels);
    if (!subscription) {
        available = NO;
        CFRelease(channels);
        channels = NULL;
        return NO;
    }

    [self loadGPUFrequencies];
    [self findAcceleratorService];
    [self initializeBandwidthIfNeeded];

    previousSample = IOReportCreateSamples(subscription, channels, NULL);
    previousSampleTime = now;
    available = previousSample != NULL;
    initialized = available;
    if (!available) {
        CFRelease(subscription);
        subscription = NULL;
        CFRelease(channels);
        channels = NULL;
    }
    return available;
}

- (BOOL)isAvailable
{
    return [self initializeIfNeeded];
}

#pragma mark - sampling

- (void)parsePowerAndGPUFromDelta:(CFDictionaryRef)delta
                          elapsed:(NSTimeInterval)elapsed
                         intoSample:(AppleSiliconPerformanceSample *)sample
{
    CFArrayRef reportChannels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    CFIndex count = MMIsType(reportChannels, CFArrayGetTypeID()) ? CFArrayGetCount(reportChannels) : 0;

    BOOL foundAnyMetric = NO;
    BOOL hasModelCPUTotal = NO;
    BOOL hasModelCPUTyped = NO;
    BOOL hasModelGPUCore = NO;     // GPU0 / GPU (not GPU Energy)
    BOOL hasModelGPUEnergy = NO;   // GPU Energy — last resort (often nJ)
    BOOL hasModelGPUSRAM = NO;
    BOOL hasModelANE = NO;
    BOOL hasPMPGPUCore = NO;
    BOOL hasPMPGPUSRAM = NO;
    BOOL hasPMPANE = NO;
    BOOL hasPMPECPU = NO;
    BOOL hasPMPPCPU = NO;

    double modelCPUTotalWatts = 0.0;
    double modelCPUTypedWatts = 0.0;
    double modelGPUCoreWatts = 0.0;
    double modelGPUEnergyWatts = 0.0;
    double modelGPUSRAMWatts = 0.0;
    double modelANEWatts = 0.0;
    double pmpGPUCoreWatts = 0.0;
    double pmpGPUSRAMWatts = 0.0;
    double pmpANEWatts = 0.0;
    double pmpECPUWatts = 0.0;
    double pmpPCPUWatts = 0.0;

    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef item = (CFDictionaryRef)CFArrayGetValueAtIndex(reportChannels, i);
        if (!MMIsType(item, CFDictionaryGetTypeID())) {
            continue;
        }

        char group[64] = {0};
        char channel[256] = {0};
        char subgroup[128] = {0};
        MMGetCString(IOReportChannelGetGroup(item), group, sizeof(group));
        MMGetCString(IOReportChannelGetChannelName(item), channel, sizeof(channel));
        MMGetCString(IOReportChannelGetSubGroup(item), subgroup, sizeof(subgroup));

        if (strcmp(group, "Energy Model") == 0 || strcmp(group, "Energy Counters") == 0) {
            int64_t energy = IOReportSimpleGetIntegerValue(item, 0);
            double watts = MAX(0.0, MMEnergyToWatts(energy, IOReportChannelGetUnitLabel(item), elapsed));

            BOOL typedCPU = MMChannelNameEquals(channel, "ECPU") || MMChannelNameEquals(channel, "PCPU") ||
                strstr(channel, "ECPU Energy") || strstr(channel, "PCPU Energy") ||
                strstr(channel, "MCPU Energy") || strstr(channel, "eCPUs Energy") ||
                strstr(channel, "pCPUs Energy") || strstr(channel, "mCPUs Energy") ||
                (strstr(channel, "_CPU") && (MMHasPrefix(channel, "EACC") || MMHasPrefix(channel, "PACC")));

            if (typedCPU) {
                modelCPUTypedWatts += watts;
                hasModelCPUTyped = YES;
            } else if (strstr(channel, "CPU Energy")) {
                modelCPUTotalWatts += watts;
                hasModelCPUTotal = YES;
            } else if (MMChannelNameEquals(channel, "GPU Energy")) {
                // Different unit family on some chips — keep as last-resort only.
                modelGPUEnergyWatts += watts;
                hasModelGPUEnergy = YES;
            } else if (MMHasPrefix(channel, "GPU SRAM") || MMHasPrefix(channel, "AGX SRAM")) {
                modelGPUSRAMWatts += watts;
                hasModelGPUSRAM = YES;
            } else if (MMHasPrefix(channel, "GPU") || MMChannelNameEquals(channel, "GPU") ||
                       MMChannelNameEquals(channel, "AGX")) {
                // GPU0, GPU, etc. — preferred over "GPU Energy"
                modelGPUCoreWatts += watts;
                hasModelGPUCore = YES;
            } else if (MMHasPrefix(channel, "ANE") || strstr(channel, "NPU") ||
                       strstr(channel, "Neural") || strstr(channel, "ane")) {
                modelANEWatts += watts;
                hasModelANE = YES;
            }
        } else if (strcmp(group, "PMP") == 0) {
            if (strcmp(subgroup, "Energy Counters") != 0 && strcmp(subgroup, "Energy") != 0) {
                continue;
            }
            int64_t energy = IOReportSimpleGetIntegerValue(item, 0);
            double watts = MAX(0.0, MMEnergyToWatts(energy, IOReportChannelGetUnitLabel(item), elapsed));
            if (MMHasPrefix(channel, "ANE") || strstr(channel, "NPU")) {
                pmpANEWatts += watts;
                hasPMPANE = YES;
            } else if (MMHasPrefix(channel, "GPU SRAM") || MMHasPrefix(channel, "AGX SRAM")) {
                pmpGPUSRAMWatts += watts;
                hasPMPGPUSRAM = YES;
            } else if (MMChannelNameEquals(channel, "GPU") || MMChannelNameEquals(channel, "AGX")) {
                pmpGPUCoreWatts += watts;
                hasPMPGPUCore = YES;
            } else if (MMChannelNameEquals(channel, "ECPU")) {
                pmpECPUWatts += watts;
                hasPMPECPU = YES;
            } else if (MMChannelNameEquals(channel, "PCPU")) {
                pmpPCPUWatts += watts;
                hasPMPPCPU = YES;
            }
        } else if (strcmp(group, "GPU Stats") == 0) {
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

    // CPU power
    if (hasModelCPUTotal) {
        sample.cpuPowerWatts = modelCPUTotalWatts;
        foundAnyMetric = YES;
    } else if (hasModelCPUTyped) {
        sample.cpuPowerWatts = modelCPUTypedWatts;
        foundAnyMetric = YES;
    } else if (hasPMPECPU || hasPMPPCPU) {
        sample.cpuPowerWatts = pmpECPUWatts + pmpPCPUWatts;
        foundAnyMetric = YES;
    }

    // GPU core power — prefer real GPU rails; never prefer GPU Energy over them.
    if (hasModelGPUCore) {
        sample.gpuPowerWatts = modelGPUCoreWatts;
        foundAnyMetric = YES;
    } else if (hasPMPGPUCore) {
        sample.gpuPowerWatts = pmpGPUCoreWatts;
        foundAnyMetric = YES;
    } else if (hasModelGPUEnergy) {
        sample.gpuPowerWatts = modelGPUEnergyWatts;
        foundAnyMetric = YES;
    }

    if (hasModelGPUSRAM) {
        sample.gpuSRAMPowerWatts = modelGPUSRAMWatts;
        foundAnyMetric = YES;
    } else if (hasPMPGPUSRAM) {
        sample.gpuSRAMPowerWatts = pmpGPUSRAMWatts;
        foundAnyMetric = YES;
    }

    // ANE: Energy Model first; if absent (base M1 pattern), adopt PMP.
    if (hasModelANE) {
        sample.anePowerWatts = modelANEWatts;
        foundAnyMetric = YES;
    } else if (hasPMPANE) {
        sample.anePowerWatts = pmpANEWatts;
        foundAnyMetric = YES;
        // On base M1, Energy Model often lacks GPU/ANE rails entirely — fill GPU too if empty.
        if (sample.gpuPowerWatts < 0.0 && hasPMPGPUCore) {
            sample.gpuPowerWatts = pmpGPUCoreWatts;
        }
        if (sample.gpuSRAMPowerWatts <= 0.0 && hasPMPGPUSRAM) {
            sample.gpuSRAMPowerWatts = pmpGPUSRAMWatts;
        }
        if (sample.cpuPowerWatts < 0.0 && (hasPMPECPU || hasPMPPCPU)) {
            sample.cpuPowerWatts = pmpECPUWatts + pmpPCPUWatts;
        }
    }

    // A18: Energy Model can be GPU-only; SMC PSTR/PZC0 hold usable totals.
    if (isA18Like) {
        double pzc0 = MMSMCReadDouble("PZC0");
        if (pzc0 >= 0.0) {
            sample.cpuPowerWatts = pzc0;
            foundAnyMetric = YES;
        }
        // PSTR is system total — only use as CPU stand-in if still missing.
        if (sample.cpuPowerWatts < 0.0) {
            double pstr = MMSMCReadDouble("PSTR");
            if (pstr >= 0.0) {
                sample.cpuPowerWatts = pstr;
                foundAnyMetric = YES;
            }
        }
    }

    sample.available = foundAnyMetric || sample.gpuUsagePercent >= 0.0;
}

- (void)parseBandwidthFromDelta:(CFDictionaryRef)delta
                        elapsed:(NSTimeInterval)elapsed
                     intoSample:(AppleSiliconPerformanceSample *)sample
{
    if (!delta || elapsed <= 0.0) {
        return;
    }

    CFArrayRef reportChannels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    CFIndex count = MMIsType(reportChannels, CFArrayGetTypeID()) ? CFArrayGetCount(reportChannels) : 0;
    if (count == 0) {
        return;
    }

    if (bandwidthMode == MMBWModeAMCStats) {
        double cpu = 0, gpu = 0, media = 0, total = 0;
        BOOL any = NO;
        for (CFIndex i = 0; i < count; i++) {
            CFDictionaryRef item = (CFDictionaryRef)CFArrayGetValueAtIndex(reportChannels, i);
            if (!MMIsType(item, CFDictionaryGetTypeID())) continue;
            if (IOReportChannelGetFormat(item) != kMMIOReportFormatSimple) continue;

            char subgroup[128] = {0};
            char channel[256] = {0};
            MMGetCString(IOReportChannelGetSubGroup(item), subgroup, sizeof(subgroup));
            MMGetCString(IOReportChannelGetChannelName(item), channel, sizeof(channel));
            if (strcmp(subgroup, "Perf Counters") != 0) continue;

            char upper[256];
            strncpy(upper, channel, sizeof(upper) - 1);
            upper[sizeof(upper) - 1] = 0;
            MMUppercaseInPlace(upper);
            if (!strstr(upper, "DCS") || !MMHasReadWriteToken(upper)) continue;

            char requestor[256];
            MMStripReadWriteSuffix(upper, requestor, sizeof(requestor));
            int64_t raw = IOReportSimpleGetIntegerValue(item, 0);
            if (raw == INT64_MIN) continue;
            double gbs = ((double)raw / elapsed) / 1000000000.0;
            any = YES;
            switch (MMClassifyAMCRequestor(requestor)) {
                case MMBWRequestorTotal: total += gbs; break;
                case MMBWRequestorCPU:   cpu += gbs; break;
                case MMBWRequestorGPU:   gpu += gbs; break;
                case MMBWRequestorMedia: media += gbs; break;
                default: break;
            }
        }
        if (any) {
            if (total > 0) {
                sample.bandwidthTotalGBs = total;
            } else {
                sample.bandwidthTotalGBs = cpu + gpu + media;
            }
            sample.bandwidthMediaGBs = media;
            sample.available = YES;
        }
        return;
    }

    if (bandwidthMode == MMBWModePMPHistogram) {
        double cpu = 0, gpu = 0, media = 0, other = 0;
        BOOL any = NO;
        for (CFIndex i = 0; i < count; i++) {
            CFDictionaryRef item = (CFDictionaryRef)CFArrayGetValueAtIndex(reportChannels, i);
            if (!MMIsType(item, CFDictionaryGetTypeID())) continue;
            if (IOReportChannelGetFormat(item) != kMMIOReportFormatState) continue;

            char subgroup[128] = {0};
            char channel[256] = {0};
            MMGetCString(IOReportChannelGetSubGroup(item), subgroup, sizeof(subgroup));
            MMGetCString(IOReportChannelGetChannelName(item), channel, sizeof(channel));
            if (strcmp(subgroup, "DCS BW") != 0) continue;

            char upper[256];
            strncpy(upper, channel, sizeof(upper) - 1);
            upper[sizeof(upper) - 1] = 0;
            MMUppercaseInPlace(upper);
            size_t ulen = strlen(upper);
            if (ulen < 6 || strcmp(upper + ulen - 6, " RD+WR") != 0) continue;
            char requestor[256];
            size_t rlen = ulen - 6;
            if (rlen >= sizeof(requestor)) rlen = sizeof(requestor) - 1;
            memcpy(requestor, channel, rlen); // keep original case for classify (prefix based)
            requestor[rlen] = 0;

            int32_t stateCount = IOReportStateGetCount(item);
            double weighted = 0.0;
            double totalRes = 0.0;
            for (int32_t s = 0; s < stateCount; s++) {
                char stateName[64] = {0};
                MMGetCString(IOReportStateGetNameForIndex(item, s), stateName, sizeof(stateName));
                double bucket = MMParseHistogramBucketGBs(stateName);
                if (bucket < 0) continue;
                double res = (double)IOReportStateGetResidency(item, s);
                weighted += res * bucket;
                totalRes += res;
            }
            if (totalRes <= 0) continue;
            double value = weighted / totalRes;
            any = YES;
            switch (MMClassifyPMPRequestor(requestor)) {
                case MMBWRequestorCPU:   cpu += value; break;
                case MMBWRequestorGPU:   gpu += value; break;
                case MMBWRequestorMedia: media += value; break;
                default: other += value; break;
            }
        }
        if (any) {
            sample.bandwidthTotalGBs = cpu + gpu + media + other;
            sample.bandwidthMediaGBs = media;
            sample.available = YES;
        }
    }
}

- (AppleSiliconPerformanceSample *)currentSample
{
    AppleSiliconPerformanceSample *sample = [[AppleSiliconPerformanceSample alloc] init];
    sample.gpuUsagePercent = -1.0;
    sample.gpuFrequencyMHz = 0;
    sample.cpuPowerWatts = -1.0;
    sample.gpuPowerWatts = -1.0;
    sample.gpuSRAMPowerWatts = 0.0;
    sample.anePowerWatts = -1.0;
    sample.bandwidthTotalGBs = -1.0;
    sample.bandwidthMediaGBs = -1.0;
    sample.gpuMemoryInUseBytes = 0;
    sample.gpuMemoryAllocBytes = 0;

    NSTimeInterval requestTime = [NSProcessInfo processInfo].systemUptime;
    if (cachedSample && cachedSampleTime > 0.0 && requestTime - cachedSampleTime < 0.2) {
        return cachedSample;
    }

    if (![self initializeIfNeeded]) {
        return sample;
    }

    CFDictionaryRef current = IOReportCreateSamples(subscription, channels, NULL);
    NSTimeInterval currentTime = requestTime;
    if (!current) {
        cachedSample = sample;
        cachedSampleTime = currentTime;
        return sample;
    }

    if (!previousSample || previousSampleTime <= 0.0) {
        if (previousSample) CFRelease(previousSample);
        previousSample = current;
        previousSampleTime = currentTime;
        cachedSample = sample;
        cachedSampleTime = currentTime;
        return sample;
    }

    NSTimeInterval elapsed = currentTime - previousSampleTime;
    CFDictionaryRef delta = IOReportCreateSamplesDelta(previousSample, current, NULL);
    CFRelease(previousSample);
    previousSample = current;
    previousSampleTime = currentTime;

    if (delta) {
        [self parsePowerAndGPUFromDelta:delta elapsed:elapsed intoSample:sample];
        CFRelease(delta);
    }

    // Bandwidth on its own subscription (may fail independently of power/GPU).
    if (bandwidthSubscription && bandwidthChannels) {
        CFDictionaryRef bwCurrent = IOReportCreateSamples(bandwidthSubscription, bandwidthChannels, NULL);
        if (bwCurrent) {
            if (previousBandwidthSample && previousBandwidthSampleTime > 0.0) {
                NSTimeInterval bwElapsed = currentTime - previousBandwidthSampleTime;
                CFDictionaryRef bwDelta = IOReportCreateSamplesDelta(previousBandwidthSample, bwCurrent, NULL);
                if (bwDelta) {
                    [self parseBandwidthFromDelta:bwDelta elapsed:bwElapsed intoSample:sample];
                    CFRelease(bwDelta);
                }
                CFRelease(previousBandwidthSample);
            }
            previousBandwidthSample = bwCurrent;
            previousBandwidthSampleTime = currentTime;
        }
    }

    [self readGPUMemoryIntoSample:sample];
    if (sample.gpuMemoryInUseBytes > 0 || sample.gpuMemoryAllocBytes > 0) {
        sample.available = YES;
    }

    cachedSample = sample;
    cachedSampleTime = currentTime;
    return sample;
}

@end
