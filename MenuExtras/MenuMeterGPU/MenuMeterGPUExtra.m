//
//  MenuMeterGPUExtra.m
//  MenuMeters
//

#import "MenuMeterGPUExtra.h"

#define kGPUTitle                  @"GPU:"
#define kGPUUsageTitle             @"GPU Usage:"
#define kGPUFrequencyTitle         @"GPU Frequency:"
#define kGPUPowerTitle             @"GPU Power:"
#define kGPUANEPowerTitle          @"ANE Power:"
#define kGPUBandwidthTitle         @"Memory Bandwidth:"
#define kGPUMediaTitle             @"Media Engine:"
#define kGPUMemoryTitle            @"GPU Memory:"
#define kGPUUnavailable            @"Unavailable"

@interface MenuMeterGPUExtra ()
- (void)updateMenuContent;
- (void)updateMenuWhenDown;
- (void)appendTextBlockWithLabel:(NSString *)label value:(NSString *)value atX:(CGFloat *)x;
- (void)renderGraphAtX:(CGFloat)x;
- (void)updateMenuWidth;
- (void)addInterBlockGapAtX:(CGFloat *)x;
- (NSString *)percentString:(double)value;
- (NSString *)wattsString:(double)value;
- (NSString *)bandwidthString:(double)value;
- (NSString *)memoryString:(uint64_t)bytes;
- (double)gpuTotalPowerWatts;
- (CGFloat)textBlockWidthForLabel:(NSString *)label sampleValue:(NSString *)value;
@end

@implementation MenuMeterGPUExtra

- (instancetype)init
{
    self = [super initWithBundleID:kGPUMenuBundleID];
    if (!self) {
        return nil;
    }

    ourPrefs = [MenuMeterDefaults sharedMenuMeterDefaults];
    if (!ourPrefs) {
        NSLog(@"MenuMeterGPU unable to connect to preferences. Abort.");
        return nil;
    }

    performanceReader = [AppleSiliconPerformanceReader sharedReader];
    gpuHistory = [NSMutableArray array];
    currentSample = [[AppleSiliconPerformanceSample alloc] init];

    extraMenu = [[NSMenu alloc] initWithTitle:@""];
    [extraMenu setAutoenablesItems:NO];

    NSBundle *bundle = [NSBundle mainBundle];
    NSMenuItem *menuItem = [extraMenu addItemWithTitle:[bundle localizedStringForKey:kGPUTitle value:nil table:nil]
                                                action:nil
                                         keyEquivalent:@""];
    [menuItem setEnabled:NO];

    for (NSString *titleKey in @[
        kGPUUsageTitle,
        kGPUFrequencyTitle,
        kGPUPowerTitle,
        kGPUANEPowerTitle,
        kGPUBandwidthTitle,
        kGPUMediaTitle,
        kGPUMemoryTitle
    ]) {
        menuItem = [extraMenu addItemWithTitle:[bundle localizedStringForKey:titleKey value:nil table:nil]
                                        action:nil
                                 keyEquivalent:@""];
        menuItem.indentationLevel = 1;
        [menuItem setEnabled:NO];
    }

    [extraMenu addItem:[NSMenuItem separatorItem]];
    [self addStandardMenuEntriesTo:extraMenu];

    percentFormatter = [[NSNumberFormatter alloc] init];
    percentFormatter.minimumFractionDigits = 0;
    percentFormatter.maximumFractionDigits = 0;
    percentFormatter.positiveSuffix = @"%";
    percentFormatter.negativeSuffix = @"%";

    wattsFormatter = [[NSNumberFormatter alloc] init];
    wattsFormatter.minimumFractionDigits = 1;
    wattsFormatter.maximumFractionDigits = 1;
    wattsFormatter.positiveSuffix = @"W";
    wattsFormatter.negativeSuffix = @"W";

    [self configFromPrefs:nil];
    NSLog(@"MenuMeterGPU loaded.");
    return self;
}

- (NSMenu *)menu
{
    currentSample = [performanceReader currentSample];
    [self updateMenuContent];
    return extraMenu;
}

- (void)timerFired:(NSTimer *)timer
{
    currentSample = [performanceReader currentSample];
    if (currentSample.available && currentSample.gpuUsagePercent >= 0.0) {
        if ([gpuHistory count] >= [ourPrefs gpuGraphLength]) {
            [gpuHistory removeObjectsInRange:NSMakeRange(0, [gpuHistory count] - [ourPrefs gpuGraphLength] + 1)];
        }
        [gpuHistory addObject:@(currentSample.gpuUsagePercent)];
    }
    [self updateMenuWidth];

    if (self.isMenuVisible) {
        [self updateMenuWhenDown];
    }
    [super timerFired:timer];
}

- (void)updateMenuContent
{
    NSString *unavailable = [[NSBundle mainBundle] localizedStringForKey:kGPUUnavailable value:nil table:nil];
    NSString *usage = currentSample.gpuUsagePercent >= 0.0 ? [self percentString:currentSample.gpuUsagePercent] : unavailable;
    NSString *frequency = currentSample.gpuFrequencyMHz > 0 ? [NSString stringWithFormat:@"%ld MHz", (long)currentSample.gpuFrequencyMHz] : unavailable;
    NSString *gpuWatts = [self gpuTotalPowerWatts] >= 0.0 ? [self wattsString:[self gpuTotalPowerWatts]] : unavailable;
    NSString *aneWatts = currentSample.anePowerWatts >= 0.0 ? [self wattsString:currentSample.anePowerWatts] : unavailable;
    NSString *bw = currentSample.bandwidthTotalGBs >= 0.0 ? [self bandwidthString:currentSample.bandwidthTotalGBs] : unavailable;
    NSString *media = currentSample.bandwidthMediaGBs >= 0.0 ? [self bandwidthString:currentSample.bandwidthMediaGBs] : unavailable;
    NSString *mem = (currentSample.gpuMemoryInUseBytes > 0 || currentSample.gpuMemoryAllocBytes > 0)
        ? [self memoryString:currentSample.gpuMemoryInUseBytes > 0 ? currentSample.gpuMemoryInUseBytes : currentSample.gpuMemoryAllocBytes]
        : unavailable;

    LiveUpdateMenuItemTitle(extraMenu, kGPUUsageInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUUsageTitle value:nil table:nil], usage]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUFrequencyInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUFrequencyTitle value:nil table:nil], frequency]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUPowerInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUPowerTitle value:nil table:nil], gpuWatts]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUANEPowerInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUANEPowerTitle value:nil table:nil], aneWatts]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUBandwidthInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUBandwidthTitle value:nil table:nil], bw]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUMediaInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUMediaTitle value:nil table:nil], media]);
    LiveUpdateMenuItemTitle(extraMenu, kGPUMemoryInfoMenuIndex, [NSString stringWithFormat:@"%@ %@", [[NSBundle mainBundle] localizedStringForKey:kGPUMemoryTitle value:nil table:nil], mem]);
}

- (void)updateMenuWhenDown
{
    [self updateMenuContent];
    LiveUpdateMenu(extraMenu);
}

- (BOOL)renderImage
{
    [self setupAppearance];
    int mode = [ourPrefs gpuDisplayMode];
    CGFloat x = 0.0;

    if (mode & kGPUDisplayGraph) {
        [self addInterBlockGapAtX:&x];
        [self renderGraphAtX:x];
        x += [ourPrefs gpuGraphLength];
    }
    if (mode & kGPUDisplayPercent) {
        [self addInterBlockGapAtX:&x];
        [self appendTextBlockWithLabel:@"GPU" value:[self percentString:currentSample.gpuUsagePercent] atX:&x];
    }
    if (mode & kGPUDisplayFrequency) {
        [self addInterBlockGapAtX:&x];
        NSString *value = currentSample.gpuFrequencyMHz > 0 ? [NSString stringWithFormat:@"%ld", (long)currentSample.gpuFrequencyMHz] : @"---";
        [self appendTextBlockWithLabel:@"MHz" value:value atX:&x];
    }
    if (mode & kGPUDisplayPower) {
        [self addInterBlockGapAtX:&x];
        [self appendTextBlockWithLabel:@"GPU" value:[self wattsString:[self gpuTotalPowerWatts]] atX:&x];
    }
    if (mode & kGPUDisplayANEPower) {
        [self addInterBlockGapAtX:&x];
        [self appendTextBlockWithLabel:@"ANE" value:[self wattsString:currentSample.anePowerWatts] atX:&x];
    }
    if (mode & kGPUDisplayBandwidth) {
        [self addInterBlockGapAtX:&x];
        [self appendTextBlockWithLabel:@"BW" value:[self bandwidthString:currentSample.bandwidthTotalGBs] atX:&x];
    }
    if (mode & kGPUDisplayMedia) {
        [self addInterBlockGapAtX:&x];
        [self appendTextBlockWithLabel:@"MED" value:[self bandwidthString:currentSample.bandwidthMediaGBs] atX:&x];
    }
    if (mode & kGPUDisplayMemory) {
        [self addInterBlockGapAtX:&x];
        uint64_t bytes = currentSample.gpuMemoryInUseBytes > 0 ? currentSample.gpuMemoryInUseBytes : currentSample.gpuMemoryAllocBytes;
        [self appendTextBlockWithLabel:@"MEM" value:[self memoryString:bytes] atX:&x];
    }

    return YES;
}

- (NSString *)statusItemImageSignature
{
    int mode = [ourPrefs gpuDisplayMode];
    // Quantize like SiliconScope: skip sub-pixel / sub-display noise.
    int usageQ = currentSample.gpuUsagePercent >= 0 ? (int)llround(MIN(100.0, currentSample.gpuUsagePercent)) : -1;
    int freqQ = (int)(currentSample.gpuFrequencyMHz / 10); // 10 MHz buckets
    int powerQ = [self gpuTotalPowerWatts] >= 0 ? (int)llround([self gpuTotalPowerWatts] * 10.0) : -1;
    int aneQ = currentSample.anePowerWatts >= 0 ? (int)llround(currentSample.anePowerWatts * 10.0) : -1;
    int bwQ = currentSample.bandwidthTotalGBs >= 0 ? (int)llround(currentSample.bandwidthTotalGBs * 10.0) : -1;
    int mediaQ = currentSample.bandwidthMediaGBs >= 0 ? (int)llround(currentSample.bandwidthMediaGBs * 10.0) : -1;
    int memQ = (int)((currentSample.gpuMemoryInUseBytes > 0 ? currentSample.gpuMemoryInUseBytes : currentSample.gpuMemoryAllocBytes) / (16ull << 20));
    int histTail = 0;
    if (gpuHistory.count) {
        histTail = (int)llround(MIN(100.0, [gpuHistory.lastObject doubleValue]));
    }
    return [NSString stringWithFormat:@"g|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%@",
            mode, usageQ, freqQ, powerQ, aneQ, bwQ, mediaQ, memQ, histTail,
            [ourPrefs gpuGraphLength], self.isDark ? @"d" : @"l"];
}

- (void)renderGraphAtX:(CGFloat)x
{
    CGFloat height = self.imageHeight;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x, 0)];

    NSInteger width = [ourPrefs gpuGraphLength];
    for (NSInteger index = 0; index < width; index++) {
        NSInteger historyIndex = [gpuHistory count] - width + index;
        double value = historyIndex >= 0 ? [gpuHistory[historyIndex] doubleValue] : 0.0;
        value = MIN(100.0, MAX(0.0, value));
        [path lineToPoint:NSMakePoint(x + index, (CGFloat)(value / 100.0) * height)];
    }

    [path lineToPoint:NSMakePoint(x + width - 1, 0)];
    [gpuColor set];
    [path fill];
}

- (void)appendTextBlockWithLabel:(NSString *)label value:(NSString *)value atX:(CGFloat *)x
{
    NSColor *textColor = ([label isEqualToString:@"ANE"] || [label isEqualToString:@"MED"]) ? aneColor : gpuTextColor;
    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.5f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: textColor
    };
    NSDictionary *valueAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.5f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: textColor
    };

    NSAttributedString *labelString = [[NSAttributedString alloc] initWithString:label attributes:labelAttributes];
    NSAttributedString *valueString = [[NSAttributedString alloc] initWithString:value attributes:valueAttributes];
    CGFloat width = MAX(ceil(labelString.size.width), ceil(valueString.size.width));
    [labelString drawAtPoint:NSMakePoint(*x + round(width - labelString.size.width), floor(self.imageHeight / 2.0) - 1.0)];
    [valueString drawAtPoint:NSMakePoint(*x + round(width - valueString.size.width), -1.0)];
    *x += width;
}

- (void)addInterBlockGapAtX:(CGFloat *)x
{
    if (*x > 0.0) {
        *x += 4.0;
    }
}

- (NSString *)percentString:(double)value
{
    if (value < 0.0) {
        return @"--%";
    }
    return [percentFormatter stringFromNumber:@(MIN(100.0, MAX(0.0, value)))];
}

- (NSString *)wattsString:(double)value
{
    if (value < 0.0) {
        return @"--W";
    }
    return [wattsFormatter stringFromNumber:@(MAX(0.0, value))];
}

- (NSString *)bandwidthString:(double)value
{
    if (value < 0.0) {
        return @"--";
    }
    if (value < 10.0) {
        return [NSString stringWithFormat:@"%.1fG", value];
    }
    return [NSString stringWithFormat:@"%.0fG", value];
}

- (NSString *)memoryString:(uint64_t)bytes
{
    if (bytes == 0) {
        return @"--";
    }
    double gb = (double)bytes / (1024.0 * 1024.0 * 1024.0);
    if (gb < 1.0) {
        double mb = (double)bytes / (1024.0 * 1024.0);
        return [NSString stringWithFormat:@"%.0fM", mb];
    }
    if (gb < 10.0) {
        return [NSString stringWithFormat:@"%.1fG", gb];
    }
    return [NSString stringWithFormat:@"%.0fG", gb];
}

- (double)gpuTotalPowerWatts
{
    if (currentSample.gpuPowerWatts < 0.0) {
        return -1.0;
    }
    return currentSample.gpuPowerWatts + MAX(0.0, currentSample.gpuSRAMPowerWatts);
}

- (CGFloat)textBlockWidthForLabel:(NSString *)label sampleValue:(NSString *)value
{
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.5f weight:NSFontWeightRegular]
    };
    NSAttributedString *labelString = [[NSAttributedString alloc] initWithString:label attributes:attributes];
    NSAttributedString *valueString = [[NSAttributedString alloc] initWithString:value attributes:attributes];
    return MAX(ceil(labelString.size.width), ceil(valueString.size.width));
}

- (void)setupColor:(NSNotification *)notification
{
    fgMenuThemeColor = self.menuBarTextColor;
    gpuColor = [self colorByAdjustingForLightDark:[ourPrefs gpuColor]];
    gpuTextColor = [self colorByAdjustingForLightDark:[ourPrefs gpuTextColor]];
    aneColor = [self colorByAdjustingForLightDark:[ourPrefs gpuANEColor]];
    [self invalidateStatusItemImageSignature];
}

- (void)updateMenuWidth
{
    int mode = [ourPrefs gpuDisplayMode];
    CGFloat width = 0.0;
    if (mode & kGPUDisplayGraph) {
        [self addInterBlockGapAtX:&width];
        width += [ourPrefs gpuGraphLength];
    }
    if (mode & kGPUDisplayPercent) {
        [self addInterBlockGapAtX:&width];
        width += [self textBlockWidthForLabel:@"GPU" sampleValue:[self percentString:currentSample.gpuUsagePercent]];
    }
    if (mode & kGPUDisplayFrequency) {
        [self addInterBlockGapAtX:&width];
        NSString *value = currentSample.gpuFrequencyMHz > 0 ? [NSString stringWithFormat:@"%ld", (long)currentSample.gpuFrequencyMHz] : @"---";
        width += [self textBlockWidthForLabel:@"MHz" sampleValue:value];
    }
    if (mode & kGPUDisplayPower) {
        [self addInterBlockGapAtX:&width];
        width += [self textBlockWidthForLabel:@"GPU" sampleValue:[self wattsString:[self gpuTotalPowerWatts]]];
    }
    if (mode & kGPUDisplayANEPower) {
        [self addInterBlockGapAtX:&width];
        width += [self textBlockWidthForLabel:@"ANE" sampleValue:[self wattsString:currentSample.anePowerWatts]];
    }
    if (mode & kGPUDisplayBandwidth) {
        [self addInterBlockGapAtX:&width];
        width += [self textBlockWidthForLabel:@"BW" sampleValue:[self bandwidthString:currentSample.bandwidthTotalGBs]];
    }
    if (mode & kGPUDisplayMedia) {
        [self addInterBlockGapAtX:&width];
        width += [self textBlockWidthForLabel:@"MED" sampleValue:[self bandwidthString:currentSample.bandwidthMediaGBs]];
    }
    if (mode & kGPUDisplayMemory) {
        [self addInterBlockGapAtX:&width];
        uint64_t bytes = currentSample.gpuMemoryInUseBytes > 0 ? currentSample.gpuMemoryInUseBytes : currentSample.gpuMemoryAllocBytes;
        width += [self textBlockWidthForLabel:@"MEM" sampleValue:[self memoryString:bytes]];
    }
    if (width < 18.0) {
        width = 18.0;
    }
    if (fabs(menuWidth - width) > 0.5) {
        [self invalidateStatusItemImageSignature];
    }
    menuWidth = width;
}

- (void)configFromPrefs:(NSNotification *)notification
{
#ifdef ELCAPITAN
    [super configDisplay:kGPUMenuBundleID fromPrefs:ourPrefs withTimerInterval:[ourPrefs gpuInterval]];
#endif
    [self setupColor:nil];
    [self updateMenuWidth];
    [self invalidateStatusItemImageSignature];
    [self updateStatusItemImage];
}

@end
