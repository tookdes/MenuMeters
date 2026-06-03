//
//  MenuMeterDiskIO.m
//
//  Reader for disk IO statistics with per-disk speed tracking
//

#import "MenuMeterDiskIO.h"
#import <mach/mach_port.h>

@implementation MenuMeterDiskIOSample
@end

@interface MenuMeterDiskIO (PrivateMethods)
-(void)blockDeviceChanged:(io_iterator_t)iterator;
@end

static void BlockDeviceChanged(void *ref, io_iterator_t iterator) {
    if (ref) [(__bridge MenuMeterDiskIO *)ref blockDeviceChanged:iterator];
}

static BOOL MMIsExternalDrive(io_registry_entry_t entry) {
    io_registry_entry_t parent = 0;
    kern_return_t kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
    while (kr == KERN_SUCCESS && parent) {
        io_name_t className;
        IOObjectGetClass(parent, className);
        NSString *cls = [NSString stringWithUTF8String:className];
        if ([cls containsString:@"USB"] || [cls containsString:@"Thunderbolt"] ||
            [cls containsString:@"MassStorage"]) {
            IOObjectRelease(parent);
            return YES;
        }
        io_registry_entry_t grandparent;
        kr = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &grandparent);
        IOObjectRelease(parent);
        parent = grandparent;
    }
    return NO;
}

static NSString *MMBSDNameForEntry(io_registry_entry_t entry) {
    CFTypeRef bsd = IORegistryEntrySearchCFProperty(entry, kIOServicePlane,
        CFSTR("BSD Name"), kCFAllocatorDefault, kIORegistryIterateRecursively);
    NSString *name = nil;
    if (bsd && CFGetTypeID(bsd) == CFStringGetTypeID()) {
        name = (__bridge_transfer NSString *)bsd;
    } else if (bsd) {
        CFRelease(bsd);
    }
    return name;
}

static NSString *MMDisplayNameForEntry(io_registry_entry_t entry) {
    CFTypeRef prod = IORegistryEntrySearchCFProperty(entry, kIOServicePlane,
        CFSTR("Product"), kCFAllocatorDefault, 0);
    if (!prod) {
        prod = IORegistryEntrySearchCFProperty(entry, kIOServicePlane,
            CFSTR("Product Name"), kCFAllocatorDefault, 0);
    }
    NSString *name = nil;
    if (prod && CFGetTypeID(prod) == CFStringGetTypeID()) {
        name = [NSString stringWithString:(__bridge NSString *)prod];
    }
    if (prod) CFRelease(prod);
    return name;
}

@implementation MenuMeterDiskIO

- (void)cleanupIOKitResources {
    if (blockDeviceIterator) { IOObjectRelease(blockDeviceIterator); blockDeviceIterator = MACH_PORT_NULL; }
    if (blockDevicePublishedIterator) { IOObjectRelease(blockDevicePublishedIterator); blockDevicePublishedIterator = MACH_PORT_NULL; }
    if (blockDeviceTerminatedIterator) { IOObjectRelease(blockDeviceTerminatedIterator); blockDeviceTerminatedIterator = MACH_PORT_NULL; }
    if (notifyRunSource) { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), notifyRunSource, kCFRunLoopDefaultMode); notifyRunSource = NULL; }
    if (notifyPort) { IONotificationPortDestroy(notifyPort); notifyPort = NULL; }
    if (masterPort) { mach_port_deallocate(mach_task_self(), masterPort); masterPort = MACH_PORT_NULL; }
}

- (id)init {
    self = [super init];
    if (!self) return nil;

    diskTracking = [NSMutableDictionary dictionary];

    kern_return_t err = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if ((err != KERN_SUCCESS) || !masterPort) { [self cleanupIOKitResources]; return nil; }
    notifyPort = IONotificationPortCreate(masterPort);
    if (!notifyPort) { [self cleanupIOKitResources]; return nil; }
    notifyRunSource = IONotificationPortGetRunLoopSource(notifyPort);
    if (!notifyRunSource) { [self cleanupIOKitResources]; return nil; }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), notifyRunSource, kCFRunLoopDefaultMode);

    err = IOServiceAddMatchingNotification(notifyPort, kIOPublishNotification,
        IOServiceMatching(kIOBlockStorageDriverClass),
        BlockDeviceChanged, (__bridge void *)(self), &blockDevicePublishedIterator);
    if (err != KERN_SUCCESS) { [self cleanupIOKitResources]; return nil; }
    err = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification,
        IOServiceMatching(kIOBlockStorageDriverClass),
        BlockDeviceChanged, (__bridge void *)(self), &blockDeviceTerminatedIterator);
    if (err != KERN_SUCCESS) { [self cleanupIOKitResources]; return nil; }

    BlockDeviceChanged((__bridge void *)(self), blockDevicePublishedIterator);
    BlockDeviceChanged((__bridge void *)(self), blockDeviceTerminatedIterator);

    // Seed data
    [self diskIOActivity];
    [self diskSpeedSamples];

    return self;
}

- (void)dealloc {
    [self cleanupIOKitResources];
}

///////////////////////////////////////////////////////////////
//
//  Legacy disk activity (arrow display)
//
///////////////////////////////////////////////////////////////

- (DiskIOActivityType)diskIOActivity {
    if (!blockDeviceIterator) {
        kern_return_t err = IOServiceGetMatchingServices(masterPort,
            IOServiceMatching(kIOBlockStorageDriverClass), &blockDeviceIterator);
        if (err != KERN_SUCCESS) return kDiskActivityIdle;
    }

    io_registry_entry_t driveEntry = MACH_PORT_NULL;
    uint64_t totalRead = 0, totalWrite = 0;
    while ((driveEntry = IOIteratorNext(blockDeviceIterator))) {
        NSDictionary *statistics = CFBridgingRelease(IORegistryEntryCreateCFProperty(driveEntry,
            CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, kNilOptions));
        if (statistics) {
            NSNumber *rn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey)];
            if (rn) totalRead += [rn unsignedLongLongValue];
            NSNumber *wn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey)];
            if (wn) totalWrite += [wn unsignedLongLongValue];
        }
        IOObjectRelease(driveEntry);
    }
    IOIteratorReset(blockDeviceIterator);

    DiskIOActivityType activity = kDiskActivityIdle;
    if ((totalRead != previousTotalRead) && (totalWrite != previousTotalWrite)) {
        activity = kDiskActivityReadWrite;
    } else if (totalRead != previousTotalRead) {
        activity = kDiskActivityRead;
    } else if (totalWrite != previousTotalWrite) {
        activity = kDiskActivityWrite;
    }
    previousTotalRead = totalRead;
    previousTotalWrite = totalWrite;
    return activity;
}

///////////////////////////////////////////////////////////////
//
//  Per-disk speed samples
//
///////////////////////////////////////////////////////////////

- (NSArray *)diskSpeedSamples {
    if (!blockDeviceIterator) {
        kern_return_t err = IOServiceGetMatchingServices(masterPort,
            IOServiceMatching(kIOBlockStorageDriverClass), &blockDeviceIterator);
        if (err != KERN_SUCCESS) return @[];
    }

    NSDate *now = [NSDate date];
    NSMutableArray *samples = [NSMutableArray array];
    io_registry_entry_t driveEntry = MACH_PORT_NULL;

    while ((driveEntry = IOIteratorNext(blockDeviceIterator))) {
        NSString *bsdName = MMBSDNameForEntry(driveEntry);
        if (!bsdName) { IOObjectRelease(driveEntry); continue; }

        NSDictionary *statistics = CFBridgingRelease(IORegistryEntryCreateCFProperty(driveEntry,
            CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, kNilOptions));
        if (!statistics) { IOObjectRelease(driveEntry); continue; }

        NSNumber *rn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey)];
        NSNumber *wn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey)];
        uint64_t curRead = rn ? [rn unsignedLongLongValue] : 0;
        uint64_t curWrite = wn ? [wn unsignedLongLongValue] : 0;

        NSDictionary *prev = diskTracking[bsdName];
        double readBps = 0, writeBps = 0;

        if (prev) {
            NSTimeInterval elapsed = [now timeIntervalSinceDate:prev[@"time"]];
            if (elapsed > 0) {
                uint64_t prevRead = [prev[@"read"] unsignedLongLongValue];
                uint64_t prevWrite = [prev[@"write"] unsignedLongLongValue];
                if (curRead >= prevRead) readBps = (double)(curRead - prevRead) / elapsed;
                if (curWrite >= prevWrite) writeBps = (double)(curWrite - prevWrite) / elapsed;
            }
        }

        // Update tracking
        diskTracking[bsdName] = @{@"read": @(curRead), @"write": @(curWrite), @"time": now};

        // Build sample
        MenuMeterDiskIOSample *sample = [[MenuMeterDiskIOSample alloc] init];
        sample.bsdName = bsdName;
        sample.displayName = MMDisplayNameForEntry(driveEntry) ?: bsdName;
        sample.isInternal = !MMIsExternalDrive(driveEntry);
        sample.readBytesPerSec = readBps;
        sample.writeBytesPerSec = writeBps;
        [samples addObject:sample];

        IOObjectRelease(driveEntry);
    }
    IOIteratorReset(blockDeviceIterator);

    // Clean up tracking for disks that no longer exist
    NSMutableSet *currentBSDNames = [NSMutableSet set];
    for (MenuMeterDiskIOSample *s in samples) {
        [currentBSDNames addObject:s.bsdName];
    }
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSString *key in diskTracking) {
        if (![currentBSDNames containsObject:key]) [toRemove addObject:key];
    }
    [diskTracking removeObjectsForKeys:toRemove];

    return samples;
}

///////////////////////////////////////////////////////////////
//
//  Physical disk list (for preferences)
//
///////////////////////////////////////////////////////////////

- (NSArray *)physicalDiskList {
    NSMutableArray *disks = [NSMutableArray array];
    io_iterator_t iter = 0;
    kern_return_t err = IOServiceGetMatchingServices(kIOMasterPortDefault,
        IOServiceMatching(kIOBlockStorageDriverClass), &iter);
    if (err != KERN_SUCCESS) return disks;

    io_registry_entry_t entry;
    NSMutableSet *seenBSD = [NSMutableSet set];
    while ((entry = IOIteratorNext(iter))) {
        NSString *bsdName = MMBSDNameForEntry(entry);
        if (!bsdName || [seenBSD containsObject:bsdName]) {
            IOObjectRelease(entry);
            continue;
        }
        [seenBSD addObject:bsdName];

        NSString *displayName = MMDisplayNameForEntry(entry) ?: bsdName;
        BOOL isExternal = MMIsExternalDrive(entry);

        [disks addObject:@{
            @"bsdName": bsdName,
            @"displayName": displayName,
            @"isInternal": @(!isExternal)
        }];
        IOObjectRelease(entry);
    }
    IOObjectRelease(iter);
    return disks;
}

///////////////////////////////////////////////////////////////
//
//  Device state changes
//
///////////////////////////////////////////////////////////////

-(void)blockDeviceChanged:(io_iterator_t)iterator {
    if (blockDeviceIterator) IOObjectRelease(blockDeviceIterator);
    blockDeviceIterator = MACH_PORT_NULL;

    io_service_t someDevice = IOIteratorNext(iterator);
    while (someDevice) {
        IOObjectRelease(someDevice);
        someDevice = IOIteratorNext(iterator);
    }
}

@end
