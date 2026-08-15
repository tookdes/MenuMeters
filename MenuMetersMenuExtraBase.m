//
//  NSMenuExtraBase.m
//  MenuMeters
//
//  Created by Yuji on 2015/08/01.
//
//

#import "MenuMetersMenuExtraBase.h"
#import "MenuMeterWorkarounds.h"

#import "MenuMeterCPUExtra.h"
#import "MenuMeterDiskExtra.h"
#import "MenuMeterGPUExtra.h"
#import "MenuMeterMemExtra.h"
#import "MenuMeterNetExtra.h"
#import "MenuMeterDefaults.h"
#import "MenuMeters.h"
#import "EMCLoginItem.h"
#import <math.h>

#define kAppleInterfaceThemeChangedNotification        @"AppleInterfaceThemeChangedNotification"

@implementation MenuMetersMenuExtraBase
- (void)dealloc
{
    [updateTimer invalidate];
    [self removeStatusItemObservers];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    @try {
        [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"tintPercentage"];
    } @catch (NSException *exception) {
    }
}

- (void)removeStatusItemObservers
{
    if (!statusItem) {
        return;
    }
    if (statusItem.button) {
        @try {
            [statusItem.button removeObserver:self forKeyPath:@"effectiveAppearance"];
        } @catch (NSException *exception) {
        }
    }
}

-(NSColor*)colorByAdjustingForLightDark:(NSColor*)c
{
    NSAppearance *previousAppearance = [NSAppearance currentAppearance];
    [self setupAppearance];
    CGFloat tint = [[NSUserDefaults standardUserDefaults] floatForKey:@"tintPercentage"] / 100.0;
    if (!isfinite(tint)) tint = 0.0;
    tint = MIN(1.0, MAX(0.0, tint));
    NSColor *result = [c blendedColorWithFraction:tint
                                          ofColor:self.isDark ?
        [[NSColor whiteColor] colorWithAlphaComponent:[c alphaComponent]] :
        [[NSColor blackColor] colorWithAlphaComponent:[c alphaComponent]]];
    [NSAppearance setCurrentAppearance:previousAppearance];
    return result;
}
-(instancetype)initWithBundleID:(NSString*)bundleID
{
    self=[super init];
    self.bundleID=bundleID;
    // Register for pref changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(configFromPrefs:)
                                                            name:self.bundleID
                                                          object:kPrefChangeNotification];
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"tintPercentage" options:NSKeyValueObservingOptionNew context:nil];
    if(@available(macOS 10.14,*)){
    }else{
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                            selector:@selector(setupColor:)
                                                                name:kAppleInterfaceThemeChangedNotification
                                                              object:nil];
    }
    return self;
}
-(void)configFromPrefs:(NSNotification *)notification
{
    NSLog(@"shouldn't happen");
    abort();
}
-(NSMenu*)menu
{
    NSLog(@"shouldn't happen");
    abort();
}
-(void)setupColor:(NSNotification*)notification
{
    NSLog(@"shouldn't happen");
    abort();
}
-(CGFloat)imageHeight
{
    return self.height-1;
}
-(NSImage*)image
{
    CGFloat padding = [[MenuMeterDefaults sharedMenuMeterDefaults] menuBarHorizontalPadding];
    NSSize imageSize=NSMakeSize(menuWidth + 2.0 * padding,self.imageHeight);
    return [NSImage imageWithSize:imageSize
                          flipped:NO
                   drawingHandler:^BOOL(NSRect dstRect) {
        NSAppearance *previousAppearance = [NSAppearance currentAppearance];
        [self setupAppearance];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:padding yBy:0.0];
        [transform concat];
        BOOL rendered = [self renderImage];
        [NSAppearance setCurrentAppearance:previousAppearance];
        return rendered;
    }];
}
-(BOOL)renderImage
{
    NSLog(@"shouldn't happen");
    abort();
}
-(void)timerFired:(id)notused
{
    [self updateStatusItemImage];
	/*    NSImage*image=self.image;
    NSImage*canvas=[NSImage imageWithSize:image.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [[[NSColor systemGrayColor] colorWithAlphaComponent:.3] setFill];
        [NSBezierPath fillRect:(CGRect) {.size = image.size}];
        [image drawAtPoint:CGPointZero fromRect:(CGRect) {.size = image.size} operation:NSCompositeSourceOver fraction:1.0];
        return YES;
    }];
    statusItem.button.image=canvas;*/
}
/*
-(void)timerXired:(id)notused
{
    NSImage *oldCanvas = statusItem.button.image;
    NSImage *canvas = oldCanvas;
    NSImage *image = self.image;
    NSSize imageSize = image.size;
    NSSize oldImageSize = canvas.size;
    if (imageSize.width != oldImageSize.width || imageSize.height != oldImageSize.height) {
        canvas = [[NSImage alloc] initWithSize:imageSize];
    }
    
    [canvas lockFocus];
    [image drawAtPoint:CGPointZero fromRect:(CGRect) {.size = image.size} operation:NSCompositeCopy fraction:1.0];
    [canvas unlockFocus];
    
    if (canvas != oldCanvas) {
        statusItem.button.image = canvas;
    } else {
        [statusItem.button displayRectIgnoringOpacity:statusItem.button.bounds];
    }
}
*/
- (NSString *)statusItemImageSignature
{
    return nil;
}

- (void)invalidateStatusItemImageSignature
{
    lastStatusItemImageSignature = nil;
}

- (NSString *)statusItemTooltip
{
    if ([self.bundleID isEqualToString:kCPUMenuBundleID]) return @"CPU";
    if ([self.bundleID isEqualToString:kGPUMenuBundleID]) return @"GPU";
    if ([self.bundleID isEqualToString:kDiskMenuBundleID]) return NSLocalizedString(@"Disk", @"Disk");
    if ([self.bundleID isEqualToString:kMemMenuBundleID]) return NSLocalizedString(@"Memory", @"Memory");
    if ([self.bundleID isEqualToString:kNetMenuBundleID]) return NSLocalizedString(@"Network", @"Network");
    return @"MenuMeters";
}

- (void)updateStatusItemImage
{
    NSString *signature = [self statusItemImageSignature];
    if (signature.length &&
        lastStatusItemImageSignature &&
        [signature isEqualToString:lastStatusItemImageSignature] &&
        statusItem.button.image != nil) {
        return;
    }

    NSImage *image = self.image;
    if (image) {
        statusItem.length = image.size.width;
        statusItem.button.image = image;
        lastStatusItemImageSignature = [signature copy];
    }
}
- (void)configDisplay:(NSString*)bundleID fromPrefs:(MenuMeterDefaults*)ourPrefs withTimerInterval:(NSTimeInterval)interval
{
    if([ourPrefs loadBoolPref:bundleID defaultValue:YES]){
        if(!statusItem){
            statusItem=[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101600)
            if(@available(macOS 11,*)){
                // 11.0.1 does not keep the position unless autosaveName is explicitly set,
                // see https://github.com/feedback-assistant/reports/issues/151 .
                // This is done here in order not to lose positions on pre-macOS 11 systems.
                statusItem.autosaveName=self.bundleID;
            }
#endif
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101200)
            if(@available(macOS 10.12,*)){
                statusItem.behavior=NSStatusItemBehaviorRemovalAllowed;
            }
#endif
            statusItem.menu = self.menu;
            statusItem.menu.delegate = self;
            NSString *tooltip = [self statusItemTooltip];
            statusItem.button.toolTip = tooltip;
            statusItem.button.accessibilityLabel = tooltip;
            /*
             Observing effectiveAppearance has a serious drawback when the Mac has two moniters, one with a light menubar and another with a dard menubar, which can happen since Big Sur depending on the chosen desktop pictures.
             In such cases statusItem.button.effectiveAppearance changes each time the system redraws the statusItem.button on two menubars, making configFromPrefs: called every time.
             Honestly, the way a single NSStatusItem behaves differently on two menubars with different appearances is undocumented, especially with a dynamically-drawn block-based image attached on a button...
            */
            [statusItem.button addObserver:self forKeyPath:@"effectiveAppearance" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
        }
        [updateTimer invalidate];
        updateTimer=[NSTimer timerWithTimeInterval:interval target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
        [updateTimer setTolerance:.2*interval];
        [[NSRunLoop currentRunLoop] addTimer:updateTimer forMode:NSRunLoopCommonModes];
    }else if(![ourPrefs loadBoolPref:bundleID defaultValue:YES] && statusItem){
        [self removeStatusItem];
    }
}
-(void)removeStatusItem
{
    [updateTimer invalidate];
    [self removeStatusItemObservers];
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    statusItem=nil;
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"menuExtraUnloaded" object:self.bundleID]];
}
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if(object==statusItem.button && [keyPath isEqualToString:@"effectiveAppearance"]){
        NSAppearance*old=change[NSKeyValueChangeOldKey];
        NSAppearance*new=change[NSKeyValueChangeNewKey];
        if(![old isKindOfClass:[NSAppearance class]] ||
           ![new isKindOfClass:[NSAppearance class]] ||
           ![old.name isEqualToString:new.name]){
            [self setupColor:nil];
        }
        return;
    }

    if([keyPath isEqualToString:@"tintPercentage"]){
        [self setupColor:nil];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)openMenuMetersPref:(id)sender
{
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"openPref" object:self]];
}
- (void)openActivityMonitor:(id)sender {

    if (![[NSWorkspace sharedWorkspace] launchApplication:@"Activity Monitor.app"]) {
        NSLog(@"MenuMeter unable to launch the Activity Monitor.");
    }
    BOOL x=[[NSUserDefaults standardUserDefaults] boolForKey:@"activityMonitorOpenSpecificPanes"];
    if(!x)
        return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(),^{
//        if(@available(macOS 10.15,*)){
            int tab=1;
            if([self isKindOfClass:[MenuMeterCPUExtra class]]){
                tab=1;
            }
            if([self isKindOfClass:[MenuMeterGPUExtra class]]){
                tab=2;
            }
            // on some Mac's there is a "GPU" tab at the 2nd position.
            // So the rest needs to be addressed from the last
            if([self isKindOfClass:[MenuMeterDiskExtra class]]){
                tab=-2;
            }
            if([self isKindOfClass:[MenuMeterMemExtra class]]){
                tab=-4;
            }
            if([self isKindOfClass:[MenuMeterNetExtra class]]){
                tab=-1;
            }
            NSString*source=[NSString stringWithFormat:@"tell application \"System Events\" to tell process \"Activity Monitor\" to click radio button %@ of radio group 1 of group 2 of toolbar of window 1", @(tab)];
            NSAppleScript*script=[[NSAppleScript alloc] initWithSource:source];
            NSDictionary* errorDict=nil;
            [script executeAndReturnError:&errorDict];
            if(errorDict){
                NSLog(@"%@",errorDict);
            }
//        }
    });
} // openActivityMonitor
- (void)toggleLaunchAtLogin:(id)sender
{
    EMCLoginItem *loginItem = [EMCLoginItem loginItemWithBundle:[NSBundle mainBundle]];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:kMenuMetersLoginItemsMigratedPref];
    if ([loginItem isLoginItem]) {
        [loginItem removeLoginItem];
        if ([sender respondsToSelector:@selector(setState:)]) {
            [sender setState:NSOffState];
        }
    } else {
        [loginItem addLoginItem];
        if ([sender respondsToSelector:@selector(setState:)]) {
            [sender setState:NSOnState];
        }
    }
}
- (void)quitMenuMeters:(id)sender
{
    [NSApp terminate:sender];
}
- (void)updateLaunchAtLoginMenuItemInMenu:(NSMenu *)menu
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(toggleLaunchAtLogin:)) {
            [item setState:[[EMCLoginItem loginItemWithBundle:[NSBundle mainBundle]] isLoginItem] ? NSOnState : NSOffState];
            return;
        }
    }
}
- (void)addStandardMenuEntriesTo:(NSMenu*)extraMenu
{
    NSMenuItem *menuItem = (NSMenuItem *)[extraMenu addItemWithTitle:NSLocalizedString(kOpenActivityMonitorTitle, kOpenActivityMonitorTitle)
                                                              action:@selector(openActivityMonitor:)
                                                       keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = (NSMenuItem *)[extraMenu addItemWithTitle:NSLocalizedString(kOpenMenuMetersPref, kOpenMenuMetersPref)
                                                  action:@selector(openMenuMetersPref:)
                                           keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = (NSMenuItem *)[extraMenu addItemWithTitle:NSLocalizedString(kLaunchAtLoginTitle, kLaunchAtLoginTitle)
                                                  action:@selector(toggleLaunchAtLogin:)
                                           keyEquivalent:@""];
    [menuItem setTarget:self];
    [extraMenu addItem:[NSMenuItem separatorItem]];
    menuItem = (NSMenuItem *)[extraMenu addItemWithTitle:NSLocalizedString(kQuitMenuMetersTitle, kQuitMenuMetersTitle)
                                                  action:@selector(quitMenuMeters:)
                                           keyEquivalent:@""];
    [menuItem setTarget:self];
}
-(BOOL)isDark
{
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101400)
    if(@available(macOS 10.14,*)){
        // https://github.com/ruiaureliano/macOS-Appearance/blob/master/Appearance/Source/AppDelegate.swift
        return [statusItem.button.effectiveAppearance.name containsString:@"ark"];
    }
#endif
    // https://stackoverflow.com/questions/25207077/how-to-detect-if-os-x-is-in-dark-mode
    // On 10.10 there is no documented API for theme, so we'll guess a couple of different ways.
    BOOL isDark = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
    NSString *interfaceStyle = [defaults stringForKey:@"AppleInterfaceStyle"];
    if (interfaceStyle && [interfaceStyle isEqualToString:@"Dark"]) {
        isDark = YES;
    }
    return isDark;
}
-(NSColor*)menuBarTextColor
{
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101400)
    if(@available(macOS 10.14,*)){
        return [NSColor labelColor];
    }
#endif
    if (self.isDark){
        return [NSColor whiteColor];
    }
    return [NSColor blackColor];
}
-(CGFloat)height
{
    CGFloat height=statusItem.button.frame.size.height;
    // height is sometimes zero here, which causes a lot of headaches if untreated...
    if(height<10){
        height=22; // the value before Big Sur.
    }
    return height;
}
- (void)setupAppearance {
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101400)
    if(@available(macOS 10.14,*)){
        NSAppearance *appearance = statusItem.button.effectiveAppearance;
        if (appearance) [NSAppearance setCurrentAppearance:appearance];
    }
#endif
}
#pragma mark NSMenuDelegate
- (void)menuNeedsUpdate:(NSMenu*)menu {
    statusItem.menu = self.menu;
    statusItem.menu.delegate = self;
}
- (void)menuWillOpen:(NSMenu*)menu {
    [self updateLaunchAtLoginMenuItemInMenu:menu];
    _isMenuVisible = YES;
}
- (void)menuDidClose:(NSMenu*)menu {
    _isMenuVisible = NO;
}

@end
