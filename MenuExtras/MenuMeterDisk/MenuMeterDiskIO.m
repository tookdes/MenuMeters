//
//  MenuMeterDiskIO.m
//
//  Reader for disk IO statistics with per-disk speed tracking
//

#import "MenuMeterDiskIO.h"
#import <mach/mach_port.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/storage/IOMedia.h>

@implementation MenuMeterDiskIOSample
@end

@interface MenuMeterDiskIO (PrivateMethods)
-(void)blockDeviceChanged:(io_iterator_t)iterator;
@end

static void BlockDeviceChanged(void *ref, io_iterator_t iterator) {
    if (ref) [(__bridge MenuMeterDiskIO *)ref blockDeviceChanged:iterator];
}

static NSString *MMStringFromCName(const char *name) {
    if (!name || !name[0]) return nil;
    return [NSString stringWithUTF8String:name];
}

static NSString *MMCleanHardwareName(NSString *raw) {
    if (!raw) return nil;
    NSString *name = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name hasSuffix:@" Media"]) {
        name = [[name substringToIndex:name.length - 6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } else if ([name hasSuffix:@" media"]) {
        name = [[name substringToIndex:name.length - 6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return name.length ? name : nil;
}

static BOOL MMRegistryHintsContainDiskImage(io_registry_entry_t entry) {
    io_registry_entry_t current = entry;
    BOOL releaseCurrent = NO;
    for (int depth = 0; depth < 8 && current; depth++) {
        io_name_t className = {0};
        if (IOObjectGetClass(current, className) == KERN_SUCCESS) {
            NSString *cls = MMStringFromCName(className).lowercaseString;
            if ([cls containsString:@"diskimage"] || [cls containsString:@"applediskimage"]) {
                if (releaseCurrent) IOObjectRelease(current);
                return YES;
            }
        }
        io_name_t entryName = {0};
        if (IORegistryEntryGetName(current, entryName) == KERN_SUCCESS) {
            NSString *nm = MMStringFromCName(entryName).lowercaseString;
            if ([nm containsString:@"disk image"] || [nm containsString:@"diskimage"]) {
                if (releaseCurrent) IOObjectRelease(current);
                return YES;
            }
        }
        CFTypeRef product = IORegistryEntryCreateCFProperty(current, CFSTR("Product"), kCFAllocatorDefault, 0);
        if (!product) {
            product = IORegistryEntryCreateCFProperty(current, CFSTR("Product Name"), kCFAllocatorDefault, 0);
        }
        if (product) {
            if (CFGetTypeID(product) == CFStringGetTypeID()) {
                NSString *p = [(__bridge NSString *)product lowercaseString];
                if ([p containsString:@"disk image"]) {
                    CFRelease(product);
                    if (releaseCurrent) IOObjectRelease(current);
                    return YES;
                }
            }
            CFRelease(product);
        }
        io_registry_entry_t parent = 0;
        kern_return_t kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        if (releaseCurrent) IOObjectRelease(current);
        if (kr != KERN_SUCCESS || !parent) {
            return NO;
        }
        current = parent;
        releaseCurrent = YES;
    }
    if (releaseCurrent && current) IOObjectRelease(current);
    return NO;
}

static BOOL MMIsAPFSSyntheticMedia(io_registry_entry_t media) {
    io_name_t className = {0};
    if (IOObjectGetClass(media, className) == KERN_SUCCESS) {
        NSString *cls = MMStringFromCName(className).lowercaseString;
        if ([cls containsString:@"appleapfsmedia"]) return YES;
    }
    io_name_t entryName = {0};
    if (IORegistryEntryGetName(media, entryName) == KERN_SUCCESS) {
        NSString *nm = MMStringFromCName(entryName).lowercaseString;
        if ([nm isEqualToString:@"appleapfsmedia"] || [nm containsString:@"appleapfsmedia"]) return YES;
    }
    return NO;
}

static BOOL MMIsExternalDrive(io_registry_entry_t entry) {
    io_registry_entry_t parent = 0;
    kern_return_t kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
    while (kr == KERN_SUCCESS && parent) {
        io_name_t className = {0};
        if (IOObjectGetClass(parent, className) == KERN_SUCCESS) {
            NSString *cls = MMStringFromCName(className);
            if ([cls containsString:@"USB"] || [cls containsString:@"Thunderbolt"] ||
                [cls containsString:@"MassStorage"] || [cls containsString:@"FireWire"]) {
                IOObjectRelease(parent);
                return YES;
            }
        }
        io_registry_entry_t grandparent = 0;
        kr = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &grandparent);
        IOObjectRelease(parent);
        parent = grandparent;
    }
    return NO;
}

/// Prefer the whole-disk IOMedia child (physical), not partitions/volumes.
static io_registry_entry_t MMWholeMediaChild(io_registry_entry_t service) {
    io_iterator_t iterator = 0;
    if (IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) != KERN_SUCCESS) {
        return 0;
    }
    io_registry_entry_t child;
    while ((child = IOIteratorNext(iterator))) {
        CFTypeRef whole = IORegistryEntryCreateCFProperty(child, CFSTR("Whole"), kCFAllocatorDefault, 0);
        CFTypeRef bsd = IORegistryEntryCreateCFProperty(child, CFSTR("BSD Name"), kCFAllocatorDefault, 0);
        BOOL isWhole = NO;
        if (whole && CFGetTypeID(whole) == CFBooleanGetTypeID()) {
            isWhole = CFBooleanGetValue((CFBooleanRef)whole);
        }
        if (whole) CFRelease(whole);
        BOOL hasBSD = (bsd && CFGetTypeID(bsd) == CFStringGetTypeID() && CFStringGetLength((CFStringRef)bsd) > 0);
        if (bsd) CFRelease(bsd);
        if (isWhole && hasBSD) {
            IOObjectRelease(iterator);
            return child; // caller owns
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return 0;
}

static NSString *MMBSDNameForMedia(io_registry_entry_t media) {
    CFTypeRef bsd = IORegistryEntryCreateCFProperty(media, CFSTR("BSD Name"), kCFAllocatorDefault, 0);
    if (!bsd) return nil;
    NSString *name = nil;
    if (CFGetTypeID(bsd) == CFStringGetTypeID()) {
        name = [NSString stringWithString:(__bridge NSString *)bsd];
    }
    CFRelease(bsd);
    return name;
}

static NSString *MMIdentifierForMedia(io_registry_entry_t media, NSString *bsdName) {
    CFTypeRef uuid = IORegistryEntryCreateCFProperty(media, CFSTR(kIOMediaUUIDKey), kCFAllocatorDefault, 0);
    NSString *identifier = nil;
    if (uuid && CFGetTypeID(uuid) == CFStringGetTypeID()) {
        identifier = [NSString stringWithString:(__bridge NSString *)uuid];
    }
    if (uuid) CFRelease(uuid);
    return identifier.length ? identifier : bsdName;
}

static NSString *MMProductFromParents(io_registry_entry_t entry) {
    io_registry_entry_t current = entry;
    BOOL releaseCurrent = NO;
    for (int depth = 0; depth < 6 && current; depth++) {
        for (NSString *key in @[@"Product Name", @"Product", @"Model Number", @"device-model", @"MediaName"]) {
            CFTypeRef val = IORegistryEntryCreateCFProperty(current, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
            if (val && CFGetTypeID(val) == CFStringGetTypeID()) {
                NSString *cleaned = MMCleanHardwareName((__bridge NSString *)val);
                CFRelease(val);
                if (cleaned.length &&
                    ![[cleaned lowercaseString] isEqualToString:@"disk image"] &&
                    ![[cleaned lowercaseString] isEqualToString:@"media"]) {
                    if (releaseCurrent) IOObjectRelease(current);
                    return cleaned;
                }
            } else if (val) {
                CFRelease(val);
            }
        }
        io_registry_entry_t parent = 0;
        kern_return_t kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        if (releaseCurrent) IOObjectRelease(current);
        if (kr != KERN_SUCCESS || !parent) return nil;
        current = parent;
        releaseCurrent = YES;
    }
    if (releaseCurrent && current) IOObjectRelease(current);
    return nil;
}

static NSString *MMDisplayNameForMedia(io_registry_entry_t media, io_registry_entry_t service, NSString *bsdName) {
    CFTypeRef mediaName = IORegistryEntryCreateCFProperty(media, CFSTR("MediaName"), kCFAllocatorDefault, 0);
    if (mediaName && CFGetTypeID(mediaName) == CFStringGetTypeID()) {
        NSString *cleaned = MMCleanHardwareName((__bridge NSString *)mediaName);
        CFRelease(mediaName);
        if (cleaned.length && ![[cleaned lowercaseString] isEqualToString:@"disk image"]) {
            return cleaned;
        }
    } else if (mediaName) {
        CFRelease(mediaName);
    }

    NSString *fromParents = MMProductFromParents(service);
    if (fromParents.length) return fromParents;
    fromParents = MMProductFromParents(media);
    if (fromParents.length) return fromParents;

    io_name_t entryName = {0};
    if (IORegistryEntryGetName(media, entryName) == KERN_SUCCESS) {
        NSString *cleaned = MMCleanHardwareName(MMStringFromCName(entryName));
        if (cleaned.length &&
            ![[cleaned lowercaseString] isEqualToString:@"appleapfsmedia"] &&
            ![[cleaned lowercaseString] isEqualToString:@"disk image"]) {
            return cleaned;
        }
    }
    return bsdName ?: @"Disk";
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
        io_registry_entry_t media = MMWholeMediaChild(driveEntry);
        if (media) {
            if (!MMIsAPFSSyntheticMedia(media) && !MMRegistryHintsContainDiskImage(driveEntry) && !MMRegistryHintsContainDiskImage(media)) {
                NSDictionary *statistics = CFBridgingRelease(IORegistryEntryCreateCFProperty(driveEntry,
                    CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, kNilOptions));
                if (statistics) {
                    NSNumber *rn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey)];
                    if (rn) totalRead += [rn unsignedLongLongValue];
                    NSNumber *wn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey)];
                    if (wn) totalWrite += [wn unsignedLongLongValue];
                }
            }
            IOObjectRelease(media);
        }
        IOObjectRelease(driveEntry);
    }
    IOIteratorReset(blockDeviceIterator);

    DiskIOActivityType activity = kDiskActivityIdle;
    if ((totalRead > previousTotalRead) && (totalWrite > previousTotalWrite)) {
        activity = kDiskActivityReadWrite;
    } else if (totalRead > previousTotalRead) {
        activity = kDiskActivityRead;
    } else if (totalWrite > previousTotalWrite) {
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

    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSMutableArray *samples = [NSMutableArray array];
    io_registry_entry_t driveEntry = MACH_PORT_NULL;
    NSMutableSet *seenBSD = [NSMutableSet set];

    while ((driveEntry = IOIteratorNext(blockDeviceIterator))) {
        io_registry_entry_t media = MMWholeMediaChild(driveEntry);
        if (!media) {
            IOObjectRelease(driveEntry);
            continue;
        }

        // Parity with MacOS-TSKMGR: hide disk images and APFS synthetic whole-disks.
        if (MMIsAPFSSyntheticMedia(media) ||
            MMRegistryHintsContainDiskImage(driveEntry) ||
            MMRegistryHintsContainDiskImage(media)) {
            IOObjectRelease(media);
            IOObjectRelease(driveEntry);
            continue;
        }

        NSString *bsdName = MMBSDNameForMedia(media);
        if (!bsdName || [seenBSD containsObject:bsdName]) {
            IOObjectRelease(media);
            IOObjectRelease(driveEntry);
            continue;
        }
        [seenBSD addObject:bsdName];
        NSString *identifier = MMIdentifierForMedia(media, bsdName);

        NSDictionary *statistics = CFBridgingRelease(IORegistryEntryCreateCFProperty(driveEntry,
            CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, kNilOptions));
        if (!statistics) {
            IOObjectRelease(media);
            IOObjectRelease(driveEntry);
            continue;
        }

        NSNumber *rn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey)];
        NSNumber *wn = statistics[(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey)];
        uint64_t curRead = rn ? [rn unsignedLongLongValue] : 0;
        uint64_t curWrite = wn ? [wn unsignedLongLongValue] : 0;

        NSDictionary *prev = diskTracking[identifier];
        double readBps = 0, writeBps = 0;

        if (prev) {
            NSTimeInterval elapsed = now - [prev[@"time"] doubleValue];
            if (elapsed > 0) {
                uint64_t prevRead = [prev[@"read"] unsignedLongLongValue];
                uint64_t prevWrite = [prev[@"write"] unsignedLongLongValue];
                if (curRead >= prevRead) readBps = (double)(curRead - prevRead) / elapsed;
                if (curWrite >= prevWrite) writeBps = (double)(curWrite - prevWrite) / elapsed;
            }
        }

        diskTracking[identifier] = @{@"read": @(curRead), @"write": @(curWrite), @"time": @(now)};

        MenuMeterDiskIOSample *sample = [[MenuMeterDiskIOSample alloc] init];
        sample.bsdName = bsdName;
        sample.identifier = identifier;
        sample.displayName = MMDisplayNameForMedia(media, driveEntry, bsdName);
        sample.isInternal = !MMIsExternalDrive(driveEntry);
        sample.readBytesPerSec = readBps;
        sample.writeBytesPerSec = writeBps;
        [samples addObject:sample];

        IOObjectRelease(media);
        IOObjectRelease(driveEntry);
    }
    IOIteratorReset(blockDeviceIterator);

    NSMutableSet *currentIdentifiers = [NSMutableSet set];
    for (MenuMeterDiskIOSample *s in samples) {
        [currentIdentifiers addObject:s.identifier];
    }
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSString *key in diskTracking) {
        if (![currentIdentifiers containsObject:key]) [toRemove addObject:key];
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
        io_registry_entry_t media = MMWholeMediaChild(entry);
        if (!media) {
            IOObjectRelease(entry);
            continue;
        }
        if (MMIsAPFSSyntheticMedia(media) ||
            MMRegistryHintsContainDiskImage(entry) ||
            MMRegistryHintsContainDiskImage(media)) {
            IOObjectRelease(media);
            IOObjectRelease(entry);
            continue;
        }

        NSString *bsdName = MMBSDNameForMedia(media);
        if (!bsdName || [seenBSD containsObject:bsdName]) {
            IOObjectRelease(media);
            IOObjectRelease(entry);
            continue;
        }
        [seenBSD addObject:bsdName];
        NSString *identifier = MMIdentifierForMedia(media, bsdName);

        NSString *displayName = MMDisplayNameForMedia(media, entry, bsdName);
        BOOL isExternal = MMIsExternalDrive(entry);

        [disks addObject:@{
            @"bsdName": bsdName,
            @"identifier": identifier,
            @"displayName": displayName,
            @"isInternal": @(!isExternal)
        }];
        IOObjectRelease(media);
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
