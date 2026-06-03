//
//  MenuMeterDiskExtra.m
//
//	Disk meter with throughput display support
//

#import "MenuMeterDiskExtra.h"

///////////////////////////////////////////////////////////////
//
//	Private methods
//
///////////////////////////////////////////////////////////////

@interface MenuMeterDiskExtra (PrivateMethods)
- (NSArray *)diskSpaceMenuItemImages:(NSArray *)driveDetails;
- (void)openOrEjectVolume:(id)sender;
- (void)configFromPrefs:(NSNotification *)notification;
- (void)renderThroughput;
- (void)updateMenuWidth;
@end

///////////////////////////////////////////////////////////////
//
//	Helpers
//
///////////////////////////////////////////////////////////////

static NSString *MMDiskSpeedString(double bytesPerSec) {
    if (bytesPerSec < 0) bytesPerSec = 0;
    if (bytesPerSec < 1024.0) {
        return [NSString stringWithFormat:@"%.0f B/s", bytesPerSec];
    } else if (bytesPerSec < 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f KB/s", bytesPerSec / 1024.0];
    } else if (bytesPerSec < 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSec / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.2f GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0)];
    }
}

///////////////////////////////////////////////////////////////
//
//	init
//
///////////////////////////////////////////////////////////////

@implementation MenuMeterDiskExtra

- (instancetype)init {
    self = [super initWithBundleID:kDiskMenuBundleID];
    if (!self) return nil;

    ourPrefs = [MenuMeterDefaults sharedMenuMeterDefaults];
    if (!ourPrefs) {
        NSLog(@"MenuMeterDisk unable to connect to preferences. Abort.");
        return nil;
    }

    diskIOMonitor = [[MenuMeterDiskIO alloc] init];
    diskSpaceMonitor = [[MenuMeterDiskSpace alloc] init];
    if (!(diskIOMonitor && diskSpaceMonitor)) {
        NSLog(@"MenuMeterDisk unable to load data gatherers. Abort.");
        return nil;
    }

    if (![ourPrefs diskSpaceForceBaseTwo]) {
        [diskSpaceMonitor setBaseTen:YES];
    }

    extraMenu = [[NSMenu alloc] initWithTitle:@""];
    if (!extraMenu) return nil;
    [extraMenu setAutoenablesItems:NO];

    throughputFont = [NSFont monospacedDigitSystemFontOfSize:9.5f weight:NSFontWeightRegular];

    [self configFromPrefs:nil];
    displayedActivity = kDiskActivityIdle;

    NSLog(@"MenuMeterDisk loaded.");
    return self;
}

///////////////////////////////////////////////////////////////
//
//  NSMenuExtra view callbacks
//
///////////////////////////////////////////////////////////////

- (BOOL)renderImage {
    [self setupAppearance];
    int mode = [ourPrefs diskDisplayMode];

    if (mode & kDiskDisplayArrows) {
        // Draw the arrow icon at x=0
        NSImage *arrowIcon = nil;
        BOOL isDark = self.isDark;
        switch (displayedActivity) {
            case kDiskActivityIdle:
                arrowIcon = isDark ? idleImageDark : idleImageLight; break;
            case kDiskActivityRead:
                arrowIcon = isDark ? readImageDark : readImageLight; break;
            case kDiskActivityWrite:
                arrowIcon = isDark ? writeImageDark : writeImageLight; break;
            case kDiskActivityReadWrite:
                arrowIcon = isDark ? readwriteImageDark : readwriteImageLight; break;
            default: break;
        }
        if (arrowIcon) {
            CGFloat iconY = floor((self.imageHeight - arrowIcon.size.height) / 2.0);
            [arrowIcon drawAtPoint:NSMakePoint(0, iconY) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        }
    }
    if (mode & kDiskDisplayThroughput) {
        [self renderThroughput];
    }
    return YES;
}

- (void)updateMenuWidth {
    int mode = [ourPrefs diskDisplayMode];
    CGFloat width = 0.0;

    if (mode & kDiskDisplayArrows) {
        width += kDiskViewWidth + 4;
    }
    if (mode & kDiskDisplayThroughput) {
        // Estimate throughput text width: max of "R: 999.9 MB/s" and "W: 999.9 MB/s"
        NSDictionary *attrs = @{NSFontAttributeName: throughputFont};
        NSAttributedString *sampleR = [[NSAttributedString alloc] initWithString:@"R: 999.9 MB/s" attributes:attrs];
        NSAttributedString *sampleW = [[NSAttributedString alloc] initWithString:@"W: 999.9 MB/s" attributes:attrs];
        CGFloat textWidth = MAX(ceil(sampleR.size.width), ceil(sampleW.size.width));
        if ([ourPrefs diskThroughputLabel]) {
            NSDictionary *labelAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:8.0f]};
            NSAttributedString *rLabel = [[NSAttributedString alloc] initWithString:@"R:" attributes:labelAttrs];
            width += ceil(rLabel.size.width) + 2;
        }
        width += textWidth;
    }
    if (width < 18.0) width = 18.0;
    menuWidth = width;
}

- (void)renderThroughput {
    [self setupAppearance];

    // Get speed samples for selected disks
    NSArray *selectedBSDs = [ourPrefs diskSelectedPhysicalDisks];
    NSArray *allSamples = [diskIOMonitor diskSpeedSamples];

    double totalRead = 0, totalWrite = 0;
    // If no disks selected, sum all internal ones (or all if none marked internal)
    BOOL foundSelected = [selectedBSDs count] > 0;
    BOOL foundInternal = NO;

    for (MenuMeterDiskIOSample *sample in allSamples) {
        if (sample.isInternal) foundInternal = YES;
    }

    for (MenuMeterDiskIOSample *sample in allSamples) {
        if (foundSelected) {
            if ([selectedBSDs containsObject:sample.bsdName]) {
                totalRead += sample.readBytesPerSec;
                totalWrite += sample.writeBytesPerSec;
            }
        } else if (foundInternal) {
            if (sample.isInternal) {
                totalRead += sample.readBytesPerSec;
                totalWrite += sample.writeBytesPerSec;
            }
        } else {
            totalRead += sample.readBytesPerSec;
            totalWrite += sample.writeBytesPerSec;
        }
    }

    NSString *readStr = MMDiskSpeedString(totalRead);
    NSString *writeStr = MMDiskSpeedString(totalWrite);

    NSAttributedString *renderRead = [[NSAttributedString alloc]
        initWithString:readStr
        attributes:@{
            NSFontAttributeName: throughputFont,
            NSForegroundColorAttributeName: readColor
        }];
    NSAttributedString *renderWrite = [[NSAttributedString alloc]
        initWithString:writeStr
        attributes:@{
            NSFontAttributeName: throughputFont,
            NSForegroundColorAttributeName: writeColor
        }];

    CGFloat labelOffset = 0;
    if ([ourPrefs diskThroughputLabel]) {
        if ([ourPrefs diskDisplayMode] & kDiskDisplayArrows) {
            labelOffset += kDiskViewWidth + 4;
        }
        NSDictionary *labelAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:8.0f], NSForegroundColorAttributeName: readColor};
        NSAttributedString *rLabel = [[NSAttributedString alloc] initWithString:@"R:" attributes:labelAttrs];
        NSDictionary *wLabelAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:8.0f], NSForegroundColorAttributeName: writeColor};
        NSAttributedString *wLabel = [[NSAttributedString alloc] initWithString:@"W:" attributes:wLabelAttrs];
        [rLabel drawAtPoint:NSMakePoint(labelOffset, floorf(self.height / 2) - 2)];
        [wLabel drawAtPoint:NSMakePoint(labelOffset, -1)];
    }

    [renderRead drawAtPoint:NSMakePoint(ceil(menuWidth - renderRead.size.width), floor(self.imageHeight / 2) - 1)];
    [renderWrite drawAtPoint:NSMakePoint(ceil(menuWidth - renderWrite.size.width), -1)];
}

///////////////////////////////////////////////////////////////
//
//  Dropdown menu
//
///////////////////////////////////////////////////////////////

- (NSMenu *)menu {
    while ([extraMenu numberOfItems]) {
        [extraMenu removeItemAtIndex:0];
    }

    // Throughput section: show per-disk speed
    NSArray *allSamples = [diskIOMonitor diskSpeedSamples];
    if ([allSamples count]) {
        BOOL hasSelected = [[ourPrefs diskSelectedPhysicalDisks] count] > 0;
        for (MenuMeterDiskIOSample *sample in allSamples) {
            // Only show selected disks (or all if none selected)
            if (hasSelected && ![[ourPrefs diskSelectedPhysicalDisks] containsObject:sample.bsdName]) continue;

            NSString *intExt = sample.isInternal ? @"Int" : @"Ext";
            NSString *title = [NSString stringWithFormat:@"%@ (%@) %@",
                               sample.displayName, sample.bsdName, intExt];
            NSMenuItem *item = [extraMenu addItemWithTitle:title action:nil keyEquivalent:@""];
            [item setEnabled:NO];

            NSString *rStr = [NSString stringWithFormat:@"  R: %@", MMDiskSpeedString(sample.readBytesPerSec)];
            NSString *wStr = [NSString stringWithFormat:@"  W: %@", MMDiskSpeedString(sample.writeBytesPerSec)];
            NSMenuItem *rItem = [extraMenu addItemWithTitle:rStr action:nil keyEquivalent:@""];
            [rItem setEnabled:NO];
            [rItem setIndentationLevel:1];
            NSMenuItem *wItem = [extraMenu addItemWithTitle:wStr action:nil keyEquivalent:@""];
            [wItem setEnabled:NO];
            [wItem setIndentationLevel:1];
        }
        [extraMenu addItem:[NSMenuItem separatorItem]];
    }

    // Disk space section
    NSArray *diskSpaceData = [diskSpaceMonitor diskSpaceData];
    if (diskSpaceData && [diskSpaceData count]) {
        NSArray *itemImages = [self diskSpaceMenuItemImages:diskSpaceData];
        if ([itemImages count] == [diskSpaceData count]) {
            for (int i = 0; i < [itemImages count]; i++) {
                NSMenuItem *item = [extraMenu addItemWithTitle:@""
                                                       action:@selector(openOrEjectVolume:)
                                                keyEquivalent:@""];
                [item setImage:itemImages[i]];
                [item setRepresentedObject:[diskSpaceData[i] objectForKey:@"path"]];
                [item setTarget:self];
            }
        }
    }
    [extraMenu addItem:[NSMenuItem separatorItem]];
    [self addStandardMenuEntriesTo:extraMenu];

    return extraMenu;
}

///////////////////////////////////////////////////////////////
//
//  Disk space menu item rendering
//
///////////////////////////////////////////////////////////////

- (NSArray *)diskSpaceMenuItemImages:(NSArray *)driveDetails {
    NSMutableArray *itemImages = [NSMutableArray array];
    NSDictionary *stringAttributes = @{
        NSForegroundColorAttributeName: fgMenuThemeColor,
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0f weight:NSFontWeightRegular]
    };

    NSMutableArray *nameStrings = [NSMutableArray array];
    NSMutableArray *detailStrings = [NSMutableArray array];
    NSMutableArray *freeStrings = [NSMutableArray array];
    NSMutableArray *usedStrings = [NSMutableArray array];
    NSMutableArray *totalStrings = [NSMutableArray array];
    double widestNameText = 0, widestDetailsText = 0;
    double widestFreeSpaceText = 0, widestUsedSpaceText = 0, widestTotalSpaceText = 0;

    for (NSDictionary *driveDetail in driveDetails) {
        NSMutableAttributedString *renderString = [[NSMutableAttributedString alloc]
            initWithString:[driveDetail objectForKey:@"name"]];
        [renderString addAttributes:stringAttributes range:NSMakeRange(0, [renderString length])];
        [nameStrings addObject:renderString];
        if ([renderString size].width > widestNameText) widestNameText = [renderString size].width;

        renderString = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"(%@, %@)",
                            [driveDetail objectForKey:@"device"],
                            [driveDetail objectForKey:@"fstype"]]];
        [renderString addAttributes:stringAttributes range:NSMakeRange(0, [renderString length])];
        [detailStrings addObject:renderString];
        if ([renderString size].width > widestDetailsText) widestDetailsText = [renderString size].width;

        renderString = [[NSMutableAttributedString alloc]
            initWithString:[driveDetail objectForKey:@"free"]];
        [renderString addAttributes:stringAttributes range:NSMakeRange(0, [renderString length])];
        [freeStrings addObject:renderString];
        if ([renderString size].width > widestFreeSpaceText) widestFreeSpaceText = [renderString size].width;

        renderString = [[NSMutableAttributedString alloc]
            initWithString:[driveDetail objectForKey:@"used"]];
        [renderString addAttributes:stringAttributes range:NSMakeRange(0, [renderString length])];
        [usedStrings addObject:renderString];
        if ([renderString size].width > widestUsedSpaceText) widestUsedSpaceText = [renderString size].width;

        renderString = [[NSMutableAttributedString alloc]
            initWithString:[driveDetail objectForKey:@"total"]];
        [renderString addAttributes:stringAttributes range:NSMakeRange(0, [renderString length])];
        [totalStrings addObject:renderString];
        if ([renderString size].width > widestTotalSpaceText) widestTotalSpaceText = [renderString size].width;
    }

    widestNameText = ceil(widestNameText);
    widestDetailsText = ceil(widestDetailsText);
    widestFreeSpaceText = ceil(widestFreeSpaceText);
    widestUsedSpaceText = ceil(widestUsedSpaceText);
    widestTotalSpaceText = ceil(widestTotalSpaceText);

    double finalTextWidth = widestNameText + widestDetailsText + 25;
    if ((widestFreeSpaceText + widestUsedSpaceText + widestTotalSpaceText + 30) > finalTextWidth) {
        finalTextWidth = widestFreeSpaceText + widestUsedSpaceText + widestTotalSpaceText + 30;
    }

    for (int i = 0; i < [driveDetails count]; i++) {
        NSImage *volIcon = [driveDetails[i] objectForKey:@"icon"];
        if (!volIcon) volIcon = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];

        NSImage *menuItemImage = [NSImage imageWithSize:NSMakeSize([volIcon size].width + 10 + (float)finalTextWidth,
                                                                    [volIcon size].height)
                                                flipped:NO
                                         drawingHandler:^BOOL(NSRect dstRect) {
            [volIcon compositeToPoint:NSMakePoint(0, 0) operation:NSCompositeSourceOver];
            [(NSAttributedString *)nameStrings[i]
                drawAtPoint:NSMakePoint(ceilf((float)[volIcon size].width) + 10,
                                        ceilf((float)[volIcon size].height / 2))];
            [(NSAttributedString *)detailStrings[i]
                drawAtPoint:NSMakePoint(ceilf((float)[volIcon size].width) + 10 + (float)widestNameText + 15,
                                        ceilf((float)[volIcon size].height / 2))];
            [(NSAttributedString *)usedStrings[i]
                drawAtPoint:NSMakePoint(ceilf((float)[volIcon size].width) + 10, 1)];
            [(NSAttributedString *)freeStrings[i]
                drawAtPoint:NSMakePoint(ceilf((float)[volIcon size].width) + 10 + (float)widestUsedSpaceText + 10, 1)];
            [(NSAttributedString *)totalStrings[i]
                drawAtPoint:NSMakePoint(ceilf((float)[volIcon size].width) + 10 + (float)widestUsedSpaceText + 10 + (float)widestFreeSpaceText + 10, 1)];
            return YES;
        }];
        [itemImages addObject:menuItemImage];
    }
    return itemImages;
}

///////////////////////////////////////////////////////////////
//
//  Timer callback
//
///////////////////////////////////////////////////////////////

- (void)timerFired:(NSTimer *)timer {
    // Legacy arrow activity
    DiskIOActivityType activity = [diskIOMonitor diskIOActivity];
    if (activity != displayedActivity) {
        displayedActivity = activity;
    }
    [self updateMenuWidth];
    [super timerFired:timer];
}

///////////////////////////////////////////////////////////////
//
//  Menu actions
//
///////////////////////////////////////////////////////////////

- (void)openOrEjectVolume:(id)sender {
    UInt32 modKeys = GetCurrentKeyModifiers();
    BOOL eject = ([ourPrefs diskSelectMode] == kDiskSelectModeEject);
    if (modKeys & optionKey) eject = !eject;

    if (eject) {
        BOOL removable = NO;
        if (![[NSWorkspace sharedWorkspace] getFileSystemInfoForPath:[sender representedObject]
                                                         isRemovable:&removable
                                                          isWritable:NULL
                                                       isUnmountable:NULL
                                                            description:NULL
                                                                type:NULL]) {
            NSLog(@"MenuMeterDisk unable to get filesystem info for \"%@\".", [sender representedObject]);
        }
        NS_DURING
            if (removable) {
                [[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/diskutil"
                                         arguments:@[@"eject", [sender representedObject]]] waitUntilExit];
            } else {
                [[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/diskutil"
                                         arguments:@[@"unmount", [sender representedObject]]] waitUntilExit];
            }
        NS_HANDLER
            NSLog(@"MenuMeterDisk unable to eject/unmount \"%@\".", [sender representedObject]);
        NS_ENDHANDLER
    } else {
        [[NSWorkspace sharedWorkspace] openFile:[sender representedObject]];
    }
}

///////////////////////////////////////////////////////////////
//
//  Prefs / appearance
//
///////////////////////////////////////////////////////////////

- (void)setupColor:(NSNotification *)notification {
    fgMenuThemeColor = self.menuBarTextColor;
    readColor = [self colorByAdjustingForLightDark:[ourPrefs diskReadColor]];
    writeColor = [self colorByAdjustingForLightDark:[ourPrefs diskWriteColor]];
    inactiveColor = [self colorByAdjustingForLightDark:[ourPrefs diskInactiveColor]];
}

- (void)configFromPrefs:(NSNotification *)notification {
    [self setupColor:nil];

#ifdef ELCAPITAN
    [super configDisplay:kDiskMenuBundleID fromPrefs:ourPrefs withTimerInterval:[ourPrefs diskInterval]];
#endif

    int mode = [ourPrefs diskDisplayMode];

    // Only load arrow images if arrows mode is active
    if (mode & kDiskDisplayArrows) {
        NSImage *bootDiskIcon = [[NSWorkspace sharedWorkspace] iconForFile:@"/"];
        [bootDiskIcon setScalesWhenResized:YES];
        [bootDiskIcon setSize:NSMakeSize(kDiskViewWidth, kDiskViewWidth)];
        NSBundle *bundle = [NSBundle mainBundle];
        float menubarHeight = self.height;

        for (int isDark = 0; isDark <= 1; isDark++) {
            NSString *imageSetNamePrefix = isDark ?
                [kDiskDarkImageSets objectAtIndex:[ourPrefs diskImageset]] :
                [kDiskImageSets objectAtIndex:[ourPrefs diskImageset]];

            NSImage *idleImage, *readImage, *writeImage, *readwriteImage;
            if ([ourPrefs diskImageset] == kDiskArrowsImageSet) {
                idleImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [idleImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [idleImage unlockFocus];
                readImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [readImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [[bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"Read"]] compositeToPoint:NSMakePoint(0, 0) operation:NSCompositeSourceOver];
                [readImage unlockFocus];
                writeImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [writeImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [[bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"Write"]] compositeToPoint:NSMakePoint(0, 0) operation:NSCompositeSourceOver];
                [writeImage unlockFocus];
                readwriteImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [readwriteImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [[bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"ReadWrite"]] compositeToPoint:NSMakePoint(0, 0) operation:NSCompositeSourceOver];
                [readwriteImage unlockFocus];
            } else if ([ourPrefs diskImageset] == kDiskArrowsLargeImageSet) {
                readImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [readImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                NSBezierPath *readArrowPath = [NSBezierPath bezierPath];
                [readArrowPath moveToPoint:NSMakePoint(0, (menubarHeight / 2) + 1)];
                [readArrowPath lineToPoint:NSMakePoint(kDiskViewWidth, (menubarHeight / 2) + 1)];
                [readArrowPath lineToPoint:NSMakePoint(kDiskViewWidth / 2, (menubarHeight / 2) + 9)];
                [readArrowPath closePath];
                [[NSColor greenColor] set];
                [readArrowPath fill];
                [readImage unlockFocus];
                writeImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [writeImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                NSBezierPath *writeArrowPath = [NSBezierPath bezierPath];
                [writeArrowPath moveToPoint:NSMakePoint(0, (menubarHeight / 2) - 1)];
                [writeArrowPath lineToPoint:NSMakePoint(kDiskViewWidth, (menubarHeight / 2) - 1)];
                [writeArrowPath lineToPoint:NSMakePoint(kDiskViewWidth / 2, (menubarHeight / 2) - 9)];
                [writeArrowPath closePath];
                [[NSColor redColor] set];
                [writeArrowPath fill];
                [writeImage unlockFocus];
                idleImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [idleImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [idleImage unlockFocus];
                readwriteImage = [[NSImage alloc] initWithSize:NSMakeSize(kDiskViewWidth, menubarHeight)];
                [readwriteImage lockFocus];
                [bootDiskIcon compositeToPoint:NSMakePoint(0, (menubarHeight - kDiskViewWidth) / 2) operation:NSCompositeSourceOver];
                [[NSColor greenColor] set];
                [readArrowPath fill];
                [[NSColor redColor] set];
                [writeArrowPath fill];
                [readwriteImage unlockFocus];
            } else {
                idleImage = [bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"Idle"]];
                readImage = [bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"Read"]];
                writeImage = [bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"Write"]];
                readwriteImage = [bundle imageForResource:[imageSetNamePrefix stringByAppendingString:@"ReadWrite"]];
            }
            if (isDark) {
                idleImageDark = idleImage;
                readImageDark = readImage;
                writeImageDark = writeImage;
                readwriteImageDark = readwriteImage;
            } else {
                idleImageLight = idleImage;
                readImageLight = readImage;
                writeImageLight = writeImage;
                readwriteImageLight = readwriteImage;
            }
        }
    }

    [self updateMenuWidth];
    [self updateStatusItemImage];
}

@end
