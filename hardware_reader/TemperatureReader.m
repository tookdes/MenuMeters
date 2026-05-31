//
//  TemperatureReader.m
//  MenuMeters
//
//  Created by Yuji on 1/31/21.
//

#import "TemperatureReader.h"
#if TARGET_CPU_X86_64
#import "smc_reader.h"
#elif TARGET_CPU_ARM64
#import "applesilicon_hardware_reader.h"
#endif

@implementation TemperatureReader
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
    sensorNames=[AppleSiliconTemperatureSensorNames() sortedArrayUsingSelector:@selector(compare:)];
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
    @"SOC MTR Temp Sensor0";
#endif
	    if(![self sensorNames])
	        return candidate;
	    if([[self sensorNames] containsObject:candidate])
	        return candidate;
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
    return name;
#endif
}
+(float)temperatureOfSensorWithName:(NSString*)name
{
	#if TARGET_CPU_X86_64
	    float_t celsius = -273.15F;
	    if(!name)
	        return celsius;
	    if (kIOReturnSuccess == SMCOpen()) {
        SMCKeyValue value;
        //use harcoded value for a while
        //TODO: implement SMC tab to allow setup smc gauges in toolbar
        if (kIOReturnSuccess == SMCReadKey(toSMCCode([name UTF8String]), &value)) {
            celsius = SP78_TO_CELSIUS(value.bytes);
        }
        SMCClose();
    }
    return celsius;
#elif TARGET_CPU_ARM64
	return AppleSiliconTemperatureForName(name);
#endif
}
@end
