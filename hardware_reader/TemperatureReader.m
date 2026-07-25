//
//  TemperatureReader.m
//  MenuMeters
//
//  Created by Yuji on 1/31/21.
//

#import "TemperatureReader.h"
#import "smc_reader.h"
#if TARGET_CPU_ARM64
#import "applesilicon_hardware_reader.h"
#include <sys/sysctl.h>
#include <string.h>
#endif

@implementation TemperatureReader

#if TARGET_CPU_ARM64

typedef struct {
    const char *key;
    const char *label;
} MMCuratedSensor;

// Compact per-generation curated SMC keys (E/P/GPU/memory). Only keys that actually
// read on the machine are listed in sensorNames.
static NSArray *MMCuratedSensorsForBrand(NSString *brand)
{
    static MMCuratedSensor m1[] = {
        {"Tp0V", "E-Core 1"}, {"Tp1V", "E-Core 2"}, {"Tp0b", "E-Core 3"}, {"Tp1b", "E-Core 4"},
        {"Tp0X", "P-Core 1"}, {"Tp1X", "P-Core 2"}, {"Tp0T", "P-Core 3"}, {"Tp1T", "P-Core 4"},
        {"Tp0S", "P-Core 5"}, {"Tp1S", "P-Core 6"}, {"Tp0W", "P-Core 7"}, {"Tp1W", "P-Core 8"},
        {"Tg0H", "GPU 1"}, {"Tg0J", "GPU 2"}, {"Tg0K", "GPU 3"}, {"Tg0L", "GPU 4"},
        {"Tm0P", "Memory 1"}, {"Tm1P", "Memory 2"}, {NULL, NULL}
    };
    static MMCuratedSensor m2[] = {
        {"Tp1h", "E-Core 1"}, {"Tp1t", "E-Core 2"}, {"Tp1p", "E-Core 3"}, {"Tp1l", "E-Core 4"},
        {"Tp01", "P-Core 1"}, {"Tp05", "P-Core 2"}, {"Tp09", "P-Core 3"}, {"Tp0D", "P-Core 4"},
        {"Tp0X", "P-Core 5"}, {"Tp0b", "P-Core 6"}, {"Tp0f", "P-Core 7"}, {"Tp0j", "P-Core 8"},
        {"Tg0f", "GPU 1"}, {"Tg0j", "GPU 2"}, {NULL, NULL}
    };
    static MMCuratedSensor m3[] = {
        {"Te05", "E-Core 1"}, {"Te0L", "E-Core 2"}, {"Te0P", "E-Core 3"}, {"Te0S", "E-Core 4"},
        {"Tf04", "P-Core 1"}, {"Tf09", "P-Core 2"}, {"Tf0A", "P-Core 3"}, {"Tf0B", "P-Core 4"},
        {"Tf0D", "P-Core 5"}, {"Tf0E", "P-Core 6"}, {"Tf44", "P-Core 7"}, {"Tf49", "P-Core 8"},
        {"Tf14", "GPU 1"}, {"Tf18", "GPU 2"}, {"Tf19", "GPU 3"}, {"Tf1A", "GPU 4"}, {NULL, NULL}
    };
    static MMCuratedSensor m4[] = {
        {"Te05", "E-Core 1"}, {"Te0S", "E-Core 2"}, {"Te09", "E-Core 3"}, {"Te0H", "E-Core 4"},
        {"Tp01", "P-Core 1"}, {"Tp05", "P-Core 2"}, {"Tp09", "P-Core 3"}, {"Tp0D", "P-Core 4"},
        {"Tp0V", "P-Core 5"}, {"Tp0Y", "P-Core 6"}, {"Tp0b", "P-Core 7"}, {"Tp0e", "P-Core 8"},
        {"Tg0G", "GPU 1"}, {"Tg0H", "GPU 2"}, {"Tg1U", "GPU 1"}, {"Tg1k", "GPU 2"},
        {"Tm0p", "Memory 1"}, {"Tm1p", "Memory 2"}, {"Tm2p", "Memory 3"}, {NULL, NULL}
    };
    static MMCuratedSensor m5[] = {
        {"Tp00", "Super 1"}, {"Tp04", "Super 2"}, {"Tp08", "Super 3"},
        {"Tp0O", "P-Core 1"}, {"Tp0R", "P-Core 2"}, {"Tp0U", "P-Core 3"}, {"Tp0X", "P-Core 4"},
        {"Tg0U", "GPU 1"}, {"Tg0X", "GPU 2"}, {"Tg0d", "GPU 3"}, {"Tg0g", "GPU 4"}, {NULL, NULL}
    };

    NSString *b = brand.lowercaseString ?: @"";
    MMCuratedSensor *table = NULL;
    if ([b containsString:@"m5"]) table = m5;
    else if ([b containsString:@"m4"]) table = m4;
    else if ([b containsString:@"m3"]) table = m3;
    else if ([b containsString:@"m2"]) table = m2;
    else if ([b containsString:@"m1"]) table = m1;
    if (!table) return @[];

    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; table[i].key; i++) {
        [out addObject:@{@"key": @(table[i].key), @"label": @(table[i].label)}];
    }
    return out;
}

static NSString *MMCPUBrandString(void)
{
    char brand[256] = {0};
    size_t size = sizeof(brand);
    if (sysctlbyname("machdep.cpu.brand_string", brand, &size, NULL, 0) != 0) {
        return @"";
    }
    return [NSString stringWithUTF8String:brand] ?: @"";
}

static float MMReadSMCCelsius(const char *key)
{
    if (!key || strlen(key) < 4) return -273.15F;
    if (SMCOpen() != kIOReturnSuccess) return -273.15F;
    SMCKeyValue val = {};
    float celsius = -273.15F;
    if (SMCReadKey(toSMCCode(key), &val) == kIOReturnSuccess) {
        if (val.info.dataType.type == SMC_DATATYPE_FLT.type) {
            float f = 0;
            memcpy(&f, val.bytes, sizeof(float));
            celsius = f;
        } else if (val.info.dataType.type == SMC_DATATYPE_SP78.type) {
            celsius = SP78_TO_CELSIUS(val.bytes);
        }
    }
    SMCClose();
    return celsius;
}

static BOOL MMValidTemp(float c)
{
    return c > 5.0F && c < 130.0F;
}

static NSString *MMFriendlyHIDName(NSString *raw)
{
    if (!raw.length) return raw;
    NSString *n = raw.lowercaseString;
    // Strip trailing digits for unit id, keep them in label when useful.
    NSString *digits = @"";
    NSCharacterSet *nums = [NSCharacterSet decimalDigitCharacterSet];
    NSInteger i = (NSInteger)raw.length - 1;
    while (i >= 0 && [nums characterIsMember:[raw characterAtIndex:i]]) {
        digits = [[raw substringWithRange:NSMakeRange(i, 1)] stringByAppendingString:digits];
        i--;
    }
    NSString *suffix = digits.length ? [@" " stringByAppendingString:digits] : @"";

    if ([n containsString:@"battery"] || [n containsString:@"gas gauge"]) return @"Battery";
    if ([n hasPrefix:@"eacc"]) return [@"E-Core" stringByAppendingString:suffix];
    if ([n hasPrefix:@"pacc"]) return [@"P-Core" stringByAppendingString:suffix];
    if ([n hasPrefix:@"gpu"]) return [@"GPU" stringByAppendingString:suffix];
    if ([n hasPrefix:@"ane"]) return [@"ANE" stringByAppendingString:suffix];
    if ([n containsString:@"soc"] && [n containsString:@"die"]) return [@"SoC die" stringByAppendingString:suffix];
    if ([n containsString:@"soc"]) return [@"SoC" stringByAppendingString:suffix];
    if ([n containsString:@"nand"] || [n containsString:@"ssd"]) return [@"NAND" stringByAppendingString:suffix];
    if ([n containsString:@"dram"] || [n containsString:@"ddr"] || [n containsString:@"memory"]) {
        return [@"Memory" stringByAppendingString:suffix];
    }
    return raw;
}

static NSDictionary *MMARMDisplayNames(void)
{
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in MMCuratedSensorsForBrand(MMCPUBrandString())) {
            m[entry[@"key"]] = [NSString stringWithFormat:@"%@ (%@)", entry[@"label"], entry[@"key"]];
        }
        for (NSString *hid in AppleSiliconTemperatureSensorNames()) {
            m[hid] = MMFriendlyHIDName(hid);
        }
        map = m;
    });
    return map;
}

#endif // TARGET_CPU_ARM64

+(NSArray*)sensorNames
{
    static dispatch_once_t once;
    static NSArray*sensorNames;
    dispatch_once(&once, ^{
#if TARGET_CPU_X86_64
	    if (kIOReturnSuccess == SMCOpen()) {
	        UInt32 count = 0;
	        NSMutableArray*a=[NSMutableArray array];
	        if (SMCReadKeysCount(&count) != kIOReturnSuccess) {
	            SMCClose();
	            sensorNames=a;
	            return;
	        }
	        for(int i=0;i<count;i++){
	            SMCKeyValue val = {};
	            if (SMCReadKeyAtIndex(i, &val) != kIOReturnSuccess) {
	                continue;
	            }
            SMCCode key=val.key;
            char s[5]={key.code[3],key.code[2],key.code[1],key.code[0],0};
            NSString*name=[NSString stringWithUTF8String:s];
            if([name hasPrefix:@"T"]&&val.info.dataType.type ==SMC_DATATYPE_SP78.type){
                [a addObject:name];
            }
        }
        SMCClose();
        sensorNames=a;
    }else{
        sensorNames=nil;
    }
#elif TARGET_CPU_ARM64
    NSMutableArray *a = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    // Prefer curated SMC keys that actually read on this chip.
    for (NSDictionary *entry in MMCuratedSensorsForBrand(MMCPUBrandString())) {
        const char *key = [entry[@"key"] UTF8String];
        float t = MMReadSMCCelsius(key);
        if (MMValidTemp(t) && ![seen containsObject:entry[@"key"]]) {
            [a addObject:entry[@"key"]];
            [seen addObject:entry[@"key"]];
        }
    }
    // HID sensors fill gaps / unknown chips.
    for (NSString *hid in [AppleSiliconTemperatureSensorNames() sortedArrayUsingSelector:@selector(compare:)]) {
        if (![seen containsObject:hid]) {
            [a addObject:hid];
            [seen addObject:hid];
        }
    }
    sensorNames = a;
#endif
    });
    return sensorNames;
}
+(NSString*)defaultSensor
{
    static NSString*foo=nil;
    if(!foo){
        foo=[self defaultSensorRealWork];
    }
    return foo;
}
+(NSString*)defaultSensorRealWork
{
    NSString* candidate=
#if TARGET_CPU_X86_64
    @"TC0P";
#elif TARGET_CPU_ARM64
    @"Tp0X"; // common P-core / first curated; falls through if absent
#endif
	    if(![self sensorNames])
	        return candidate;
	    if([[self sensorNames] containsObject:candidate])
	        return candidate;
#if TARGET_CPU_ARM64
    // Prefer a P-core / E-core curated key, then any GPU, then first HID.
    for (NSString *sensor in [self sensorNames]) {
        NSString *display = [self displayNameForSensor:sensor];
        if ([display hasPrefix:@"P-Core"] || [display hasPrefix:@"Super"]) return sensor;
    }
    for (NSString *sensor in [self sensorNames]) {
        NSString *display = [self displayNameForSensor:sensor];
        if ([display hasPrefix:@"E-Core"]) return sensor;
    }
    for (NSString *sensor in [self sensorNames]) {
        if ([sensor hasPrefix:@"T"]) return sensor; // any SMC fourcc
    }
#endif
	    for(NSString*sensor in [self sensorNames]){
	        if([sensor hasPrefix:@"TC"])
	            return sensor;
	    }
	    if([[self sensorNames] count]==0)
	        return candidate;
	    return [self sensorNames][0];
}
+(NSString*)displayNameForSensor:(NSString*)name
{
    if(!name)
        return @"";
#if TARGET_CPU_X86_64
    static NSMutableDictionary*dict=nil;
    if(!dict){
        dict=[NSMutableDictionary dictionary];
        NSDictionary*rawDict=SMCHumanReadableDescriptions();
        for(NSString*key in [self sensorNames]){
            NSString*s=rawDict[key];
            if(s){
                s=[s stringByReplacingOccurrencesOfString:@"(DegC)" withString:@""];
                s=[s stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"(%@)",key] withString:@""];
                dict[key]=[NSString stringWithFormat:@"%@: %@",key,s];
            }else{
                dict[key]=key;
            }
        }
    }
    return dict[name] ?: name;
#elif TARGET_CPU_ARM64
    return MMARMDisplayNames()[name] ?: MMFriendlyHIDName(name);
#endif
}
+(float)temperatureOfSensorWithName:(NSString*)name
{
    if (!name) return -273.15F;
#if TARGET_CPU_X86_64
	    float_t celsius = -273.15F;
	    if (kIOReturnSuccess == SMCOpen()) {
        SMCKeyValue value;
        if (kIOReturnSuccess == SMCReadKey(toSMCCode([name UTF8String]), &value)) {
            celsius = SP78_TO_CELSIUS(value.bytes);
        }
        SMCClose();
    }
    return celsius;
#elif TARGET_CPU_ARM64
    // Four-character SMC keys vs HID product names.
    if (name.length == 4) {
        float smc = MMReadSMCCelsius([name UTF8String]);
        if (MMValidTemp(smc)) return smc;
    }
    return AppleSiliconTemperatureForName(name);
#endif
}
@end
