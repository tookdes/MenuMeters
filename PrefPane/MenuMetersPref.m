//
//  MenuMetersPrefPane.m
//
//	MenuMeters pref panel
//
//	Copyright (c) 2002-2014 Alex Harper
//
// 	This file is part of MenuMeters.
//
// 	MenuMeters is free software; you can redistribute it and/or modify
// 	it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
// 	MenuMeters is distributed in the hope that it will be useful,
// 	but WITHOUT ANY WARRANTY; without even the implied warranty of
// 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// 	GNU General Public License for more details.
//
// 	You should have received a copy of the GNU General Public License
// 	along with MenuMeters; if not, write to the Free Software
// 	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "MenuMetersPref.h"
#import "EMCLoginItem.h"
#import "MenuMeterCPUExtra.h"
#import "MenuMeterDiskExtra.h"
#import "MenuMeterGPUExtra.h"
#import "MenuMeterMemExtra.h"
#import "MenuMeterNetExtra.h"
#import "TemperatureReader.h"
///////////////////////////////////////////////////////////////
//
//	Private methods and constants
//
///////////////////////////////////////////////////////////////

@interface MenuMetersPref (PrivateMethods)
// Notifications
- (void)menuExtraUnloaded:(NSNotification *)notification;
- (void)menuExtraChangedPrefs:(NSNotification *)notification;

// Menu extra manipulations
- (void)loadExtraAtURL:(NSURL *)extraURL withID:(NSString *)bundleID;
- (BOOL)isExtraWithBundleIDLoaded:(NSString *)bundleID;
- (void)removeExtraWithBundleID:(NSString *)bundleID;
- (void)showMenuExtraErrorSheet;

// Net configuration update
- (void)updateNetInterfaceMenu;

// CPU info
- (BOOL)isMultiProcessor;

// GPU pane
- (void)setupGPUPaneWithFormatter:(NSNumberFormatter *)intervalFormatter;
- (void)setupCPUPageHardwareControls;
- (void)setupDiskPane;
- (void)notifyAllMenuExtrasOfLayoutChange;
- (NSString *)toolbarImageNameForItemIdentifier:(NSString *)identifier;

// System config framework
- (void)connectSystemConfig;
- (void)disconnectSystemConfig;
- (NSDictionary *)sysconfigValueForKey:(NSString *)key;

@end

// MenuCracker
#define kMenuCrackerURL				[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuCracker" ofType:@"menu" inDirectory:@""]]

// Paths to the menu extras
#ifdef ELCAPITAN
#define kCPUMenuURL nil
#define kDiskMenuURL nil
#define kMemMenuURL nil
#define kNetMenuURL nil
#else
#define kCPUMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterCPU" ofType:@"menu" inDirectory:@""]]
#define kDiskMenuURL				[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterDisk" ofType:@"menu" inDirectory:@""]]
#define kMemMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterMem" ofType:@"menu" inDirectory:@""]]
#define kNetMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterNet" ofType:@"menu" inDirectory:@""]]
#endif

// How long to wait for Extras to add once CoreMenuExtraAddMenuExtra returns?
#define kWaitForExtraLoadMicroSec		10000000
#define kWaitForExtraLoadStepMicroSec	250000

// Mem panel hidden tabs for color controls
enum {
	kMemActiveWiredInactiveColorTab = 0,
	kMemUsedFreeColorTab
};

///////////////////////////////////////////////////////////////
//
//	SystemConfiguration notification callbacks
//
///////////////////////////////////////////////////////////////

static void scChangeCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info) {

	if (info) [(__bridge MenuMetersPref *)info updateNetInterfaceMenu];

} // scChangeCallback

@implementation MenuMetersPref
{
    NSButton *gpuMeterToggle;
    NSButton *gpuPercentageToggle;
    NSButton *gpuGraphToggle;
    NSButton *gpuFrequencyToggle;
    NSButton *gpuPowerToggle;
    NSButton *gpuANEPowerToggle;
    NSButton *cpuPaneANEPowerToggle;
    NSSlider *gpuInterval;
    NSTextField *gpuIntervalDisplay;
    NSSlider *gpuGraphWidth;
    NSTextField *gpuGraphWidthLabel;
    NSSlider *menuBarPadding;
    NSTextField *menuBarPaddingLabel;
    NSColorWell *gpuColor;
    NSColorWell *gpuTextColor;
    NSColorWell *gpuANEColor;
}
-(IBAction)showAlertConcerningSystemEventsEtc:(id)sender
{
    NSButton*b=sender;
    if([b state]==NSOnState){
        NSAlert*alert=[[NSAlert alloc] init];
        alert.messageText=@"Using this feature for the first time will bring up two alerts by the system";
        [alert addButtonWithTitle:@"OK"];
        alert.informativeText=@"This feature uses AppleScript and System Events to simulate a click to switch to a specific pane of the Activity Monitor. This requires 1. one confirmation dialog to allow MenuMeters to use AppleScript, and 2. a trip to the Security & Privacy pane of the System Preferences to allow MenuMeters to use Accesibility features.";
        [alert runModal];
    }
}
-(IBAction)openAbout:(id)sender
{
    [prefTabs selectTabViewItemWithIdentifier:@"info.circle"];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
}
-(void)openPrefPane:(NSNotification*)notification
{
    id obj=notification.object;
    if([obj isKindOfClass:[MenuMeterCPUExtra class]]){
        [prefTabs selectTabViewItemWithIdentifier:@"cpu"];
    }
    if([obj isKindOfClass:[MenuMeterGPUExtra class]]){
        [prefTabs selectTabViewItemWithIdentifier:@"gpu"];
    }
    if([obj isKindOfClass:[MenuMeterDiskExtra class]]){
        [prefTabs selectTabViewItemWithIdentifier:@"internaldrive"];
    }
    if([obj isKindOfClass:[MenuMeterMemExtra class]]){
        [prefTabs selectTabViewItemWithIdentifier:@"memorychip"];
    }
    if([obj isKindOfClass:[MenuMeterNetExtra class]]){
        [prefTabs selectTabViewItemWithIdentifier:@"network"];
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
}
-(BOOL)noMenuMeterLoaded
{
    return ![self isExtraWithBundleIDLoaded:kCPUMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kGPUMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kDiskMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kMemMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kNetMenuBundleID];
}
-(void)setupAboutTab:(NSString*)about
{
    NSString*pathToRTF=[[NSBundle mainBundle] pathForResource:about ofType:@"rtf"];
    NSMutableAttributedString*x=[[NSMutableAttributedString alloc] initWithURL:[NSURL fileURLWithPath:pathToRTF] options:@{} documentAttributes:nil error:nil];
    [x addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:NSMakeRange(0, x.length)];
    [aboutView.textStorage appendAttributedString:x];
	aboutView.textContainerInset = NSMakeSize(12, 8);
}
-(void)initCommon:(NSString*)about
{
    [self loadWindow];
    [self mainViewDidLoad];
    [self willSelect];
    [self setupAboutTab:about];
    if([self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [self.window makeKeyAndOrderFront:self];
    }
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101600)
	if (@available(macOS 10.16, *)) {
		NSToolbar *toolbar = [NSToolbar new];
		toolbar.delegate = self;
		self.window.toolbar = toolbar;
		self.window.toolbarStyle = NSWindowToolbarStylePreference;

		prefTabs.tabViewType = NSNoTabsNoBorder;
		NSString *selectedIdentifier = prefTabs.selectedTabViewItem.identifier;
		[self.window.toolbar setSelectedItemIdentifier:selectedIdentifier];
		prefTabs.delegate = self;
	}
#endif
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
	NSMutableArray *items = [NSMutableArray new];
	for (NSTabViewItem *tabItem in prefTabs.tabViewItems) {
		NSString *identifier = tabItem.identifier;
		[items addObject:identifier];
	}
	return items;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted {
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdent];
	NSUInteger tabIdx = [prefTabs indexOfTabViewItemWithIdentifier:itemIdent];
	NSTabViewItem *tabItem = [prefTabs tabViewItemAtIndex:tabIdx];
	item.paletteLabel = tabItem.label;
	item.label = tabItem.label;
	item.target = self;
	item.action = @selector(toolbarSelection:);
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101600)
	if (@available(macOS 10.16, *)) {
		item.image = [NSImage imageWithSystemSymbolName:[self toolbarImageNameForItemIdentifier:itemIdent] accessibilityDescription:@""];
	}
#endif
	return item;
}

- (NSString *)toolbarImageNameForItemIdentifier:(NSString *)identifier
{
	if ([identifier isEqualToString:@"gpu"]) {
		return @"rectangle.3.group";
	}
	return identifier;
}

- (IBAction)toolbarSelection:(id)sender {
	NSString *itemIdent = [(NSToolbarItem*)sender itemIdentifier];
	NSUInteger tabIdx = [prefTabs indexOfTabViewItemWithIdentifier:itemIdent];
	NSTabViewItem *tabItem = [prefTabs tabViewItemAtIndex:tabIdx];
	[prefTabs selectTabViewItem:tabItem];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	NSString *itemIdent = [tabViewItem identifier];
	[self.window.toolbar setSelectedItemIdentifier:itemIdent];
}
-(void)hiddenBySystem:(NSNotification*)notification
{
    // ponytail: disabled; menu-bar hidden detection is too noisy to alert on.
}
-(instancetype)initWithAboutFileName:(NSString*)about
{
    self=[super initWithWindowNibName:@"MenuMetersPref"];
    [self initCommon:about];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openPrefPane:) name:@"openPref" object:nil];
    return self;
}

-(NSView*)mainView{
    return self.window.contentView;
}
-(NSBundle*)bundle{
    return [NSBundle mainBundle];
}
-(void)windowWillClose:(NSNotification *)notification
{
    if(![self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}
///////////////////////////////////////////////////////////////
//
//    Pref pane standard methods
//
///////////////////////////////////////////////////////////////
- (void)mainViewDidLoad {
	// On first load switch to the first tab
	[prefTabs selectFirstTabViewItem:self];

	// On first load populate the image set menu
	NSEnumerator *diskImageSetEnum = [kDiskImageSets objectEnumerator];
	[diskImageSet removeAllItems];
	NSString *imageSetName = nil;
	while ((imageSetName = [diskImageSetEnum nextObject])) {
		[diskImageSet addItemWithTitle:[[NSBundle bundleForClass:[self class]]
										   localizedStringForKey:imageSetName
														   value:nil
														   table:@"DiskImageSet"]];
	}

	// Set up a NSFormatter for use printing timers
	NSNumberFormatter *intervalFormatter = [[NSNumberFormatter alloc] init];
	[intervalFormatter setLocalizesFormat:YES];
	[intervalFormatter setFormat:@"###0.0\u2009s"];
	// Go through an archive/unarchive cycle to work around a bug on pre-10.2.2 systems
	// see http://cocoa.mamasam.com/COCOADEV/2001/12/2/21029.php
	intervalFormatter = [NSUnarchiver unarchiveObjectWithData:[NSArchiver archivedDataWithRootObject:intervalFormatter]];
	// Now set the formatters
	[cpuIntervalDisplay setFormatter:intervalFormatter];
	[diskIntervalDisplay setFormatter:intervalFormatter];
	[netIntervalDisplay setFormatter:intervalFormatter];
    [self setupGPUPaneWithFormatter:intervalFormatter];
    [self setupCPUPageHardwareControls];
    [self setupDiskPane];

	// The scale menu used to have images but they have been long gone
    // when the app is moved outside of System Preferences
    // because I forgot to include the image files in the new target.
    // Now they are eliminated from the code too ...
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:kMenuMetersLoginItemsMigratedPref]) {
        [defaults setBool:YES forKey:kMenuMetersLoginItemsMigratedPref];
        {
            NSString*oldAppPath=[@"~/Library/PreferencePanes/MenuMeters.prefPane/Contents/Resources/MenuMetersApp.app" stringByExpandingTildeInPath];
            EMCLoginItem*oldItem=[EMCLoginItem loginItemWithPath:oldAppPath];
            if(oldItem.isLoginItem){
                [oldItem removeLoginItem];
            }
        }
        {
            NSString*oldAppPath=@"/Library/PreferencePanes/MenuMeters.prefPane/Contents/Resources/MenuMetersApp.app";
            EMCLoginItem*oldItem=[EMCLoginItem loginItemWithPath:oldAppPath];
            if(oldItem.isLoginItem){
                [oldItem removeLoginItem];
            }
        }
        system("killall MenuMetersApp");
        {
            EMCLoginItem*thisItem=[EMCLoginItem loginItemWithBundle:[NSBundle mainBundle]];
            if(!thisItem.isLoginItem){
                [thisItem addLoginItem];
            }
        }
	}
	} // mainViewDidLoad

- (NSString *)localizedPreferenceString:(NSString *)key
{
    return [[NSBundle mainBundle] localizedStringForKey:key value:key table:nil];
}

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = title;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.textColor = [NSColor controlTextColor];
    label.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.buttonType = NSSwitchButton;
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (NSSlider *)sliderWithFrame:(NSRect)frame min:(double)min max:(double)max ticks:(NSInteger)ticks action:(SEL)action
{
    NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
    slider.minValue = min;
    slider.maxValue = max;
    slider.numberOfTickMarks = ticks;
    slider.allowsTickMarkValuesOnly = YES;
    slider.continuous = YES;
    slider.target = self;
    slider.action = action;
    return slider;
}

- (NSColorWell *)colorWellWithFrame:(NSRect)frame action:(SEL)action
{
    NSColorWell *well = [[NSColorWell alloc] initWithFrame:frame];
    well.target = self;
    well.action = action;
    return well;
}

- (void)addSectionTitle:(NSString *)title toView:(NSView *)view y:(CGFloat)y
{
    [view addSubview:[self labelWithTitle:title frame:NSMakeRect(18, y, 180, 18)]];
    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(155, y + 5, 375, 5)];
    line.boxType = NSBoxSeparator;
    [view addSubview:line];
}

- (void)setupGPUPaneWithFormatter:(NSNumberFormatter *)intervalFormatter
{
    if ([prefTabs tabViewItemAtIndex:MIN(1, prefTabs.numberOfTabViewItems - 1)].identifier &&
        [prefTabs indexOfTabViewItemWithIdentifier:@"gpu"] != NSNotFound) {
        return;
    }

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 548, 606)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTabViewItem *gpuTab = [[NSTabViewItem alloc] initWithIdentifier:@"gpu"];
    gpuTab.label = @"GPU";
    gpuTab.view = view;
    [prefTabs insertTabViewItem:gpuTab atIndex:1];

    gpuMeterToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"Display GPU Menu Meter"]
                                       frame:NSMakeRect(19, 571, 240, 24)
                                      action:@selector(gpuPrefChange:)];
    [view addSubview:gpuMeterToggle];

    [self addSectionTitle:[self localizedPreferenceString:@"GPU Display"] toView:view y:525];
    gpuPercentageToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"Percentage"]
                                            frame:NSMakeRect(50, 490, 150, 22)
                                           action:@selector(gpuPrefChange:)];
    gpuGraphToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"Graph"]
                                       frame:NSMakeRect(50, 462, 150, 22)
                                      action:@selector(gpuPrefChange:)];
    gpuFrequencyToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"GPU Frequency"]
                                           frame:NSMakeRect(290, 490, 210, 22)
                                          action:@selector(gpuPrefChange:)];
    gpuPowerToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"GPU Power"]
                                       frame:NSMakeRect(290, 462, 210, 22)
                                      action:@selector(gpuPrefChange:)];
    [view addSubview:gpuPercentageToggle];
    [view addSubview:gpuGraphToggle];
    [view addSubview:gpuFrequencyToggle];
    [view addSubview:gpuPowerToggle];

    [self addSectionTitle:[self localizedPreferenceString:@"Timing and Width"] toView:view y:380];
    [view addSubview:[self labelWithTitle:[self localizedPreferenceString:@"Update interval (seconds):"]
                                    frame:NSMakeRect(50, 346, 185, 18)]];
    gpuIntervalDisplay = [self labelWithTitle:@"x" frame:NSMakeRect(220, 346, 54, 18)];
    gpuIntervalDisplay.alignment = NSTextAlignmentCenter;
    gpuIntervalDisplay.formatter = intervalFormatter;
    [view addSubview:gpuIntervalDisplay];
    gpuInterval = [self sliderWithFrame:NSMakeRect(285, 339, 245, 24)
                                    min:kGPUUpdateIntervalMin
                                    max:kGPUUpdateIntervalMax
                                  ticks:20
                                 action:@selector(liveUpdateInterval:)];
    [view addSubview:gpuInterval];

    [view addSubview:[self labelWithTitle:[self localizedPreferenceString:@"Graph width:"]
                                    frame:NSMakeRect(50, 310, 160, 18)]];
    gpuGraphWidthLabel = [self labelWithTitle:@"" frame:NSMakeRect(220, 310, 54, 18)];
    gpuGraphWidthLabel.alignment = NSTextAlignmentCenter;
    [view addSubview:gpuGraphWidthLabel];
    gpuGraphWidth = [self sliderWithFrame:NSMakeRect(285, 303, 245, 24)
                                      min:kGPUGraphWidthMin
                                      max:kGPUGraphWidthMax
                                    ticks:8
                                   action:@selector(gpuPrefChange:)];
    [view addSubview:gpuGraphWidth];

    [view addSubview:[self labelWithTitle:[self localizedPreferenceString:@"Menu bar horizontal padding:"]
                                    frame:NSMakeRect(50, 274, 210, 18)]];
    menuBarPaddingLabel = [self labelWithTitle:@"" frame:NSMakeRect(250, 274, 35, 18)];
    menuBarPaddingLabel.alignment = NSTextAlignmentCenter;
    [view addSubview:menuBarPaddingLabel];
    menuBarPadding = [self sliderWithFrame:NSMakeRect(285, 267, 245, 24)
                                       min:kMenuBarHorizontalPaddingMin
                                       max:kMenuBarHorizontalPaddingMax
                                     ticks:kMenuBarHorizontalPaddingMax + 1
                                    action:@selector(gpuPrefChange:)];
    [view addSubview:menuBarPadding];

    [view addSubview:[self labelWithTitle:@"GPU" frame:NSMakeRect(70, 170, 85, 18)]];
    gpuColor = [self colorWellWithFrame:NSMakeRect(70, 132, 53, 30) action:@selector(gpuPrefChange:)];
    [view addSubview:gpuColor];
    [view addSubview:[self labelWithTitle:[self localizedPreferenceString:@"Text"] frame:NSMakeRect(210, 170, 85, 18)]];
    gpuTextColor = [self colorWellWithFrame:NSMakeRect(210, 132, 53, 30) action:@selector(gpuPrefChange:)];
    [view addSubview:gpuTextColor];
    [view addSubview:[self labelWithTitle:@"ANE" frame:NSMakeRect(350, 170, 85, 18)]];
    gpuANEColor = [self colorWellWithFrame:NSMakeRect(350, 132, 53, 30) action:@selector(gpuPrefChange:)];
    [view addSubview:gpuANEColor];
}

- (void)setupCPUPageHardwareControls
{
    NSView *cpuView = cpuMeterToggle.superview;
    if (!cpuView) {
        return;
    }

    cpuTemperatureToggle.frame = NSMakeRect(19, 540, 185, 22);
    cpuTemperatureUnit.frame = NSMakeRect(205, 534, 68, 26);
    cpuTemperatureSensor.frame = NSMakeRect(112, 505, 161, 26);
    cpuPercentage.frame = NSMakeRect(305, 571, 95, 22);
    cpuGraph.frame = NSMakeRect(305, 546, 95, 22);
    cpuThermometer.frame = NSMakeRect(412, 571, 125, 22);
    cpuHorizontalThermometer.frame = NSMakeRect(412, 546, 125, 22);

    for (NSView *subview in cpuView.subviews) {
        if ([subview isKindOfClass:[NSTextField class]]) {
            NSTextField *field = (NSTextField *)subview;
            if (fabs(field.frame.origin.y - 489.0) < 8.0 && field.frame.origin.x > 240.0) {
                field.frame = NSMakeRect(42, 510, 72, 18);
                break;
            }
        }
    }

#if TARGET_CPU_ARM64
    cpuPowerToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"CPU Power"]
                                       frame:NSMakeRect(305, 521, 95, 22)
                                      action:@selector(cpuPrefChange:)];
    [cpuView addSubview:cpuPowerToggle];
#endif

    cpuPaneANEPowerToggle = [self checkboxWithTitle:[self localizedPreferenceString:@"ANE Power"]
                                              frame:NSMakeRect(412, 521, 125, 22)
                                             action:@selector(gpuPrefChange:)];
    [cpuView addSubview:cpuPaneANEPowerToggle];
}


- (void)setupDiskPane {
    NSView *diskView = diskMeterToggle.superview;
    if (!diskView) return;

    // Hide the old image set popup from XIB and replace with display mode popup
    [diskImageSet setHidden:YES];

    diskDisplayMode = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(273, 516, 262, 26) pullsDown:NO];
    [diskDisplayMode removeAllItems];
    [diskDisplayMode addItemWithTitle:[self localizedPreferenceString:@"Arrows"]];
    [diskDisplayMode addItemWithTitle:[self localizedPreferenceString:@"Throughput"]];
    [diskDisplayMode addItemWithTitle:[self localizedPreferenceString:@"Arrows and Throughput"]];
    [diskDisplayMode setTarget:self];
    [diskDisplayMode setAction:@selector(diskPrefChange:)];
    [diskView addSubview:diskDisplayMode];

    // Move existing select mode controls down to make room for throughput section
    diskSelectMode.frame = NSMakeRect(284, 370, 241, 26);
    for (NSView *sub in diskView.subviews) {
        if ([sub isKindOfClass:[NSTextField class]]) {
            NSTextField *tf = (NSTextField *)sub;
            if ([tf.stringValue containsString:@"Option"] || [tf.stringValue containsString:@"Selecting"]) {
                if (tf.frame.origin.y > 380) {
                    tf.frame = NSMakeRect(tf.frame.origin.x, tf.frame.origin.y - 44, tf.frame.size.width, tf.frame.size.height);
                }
            }
        }
    }

    // Throughput Display section
    [self addSectionTitle:[self localizedPreferenceString:@"Throughput Display"] toView:diskView y:310];


    diskPhysicalDiskSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(50, 280, 400, 26) pullsDown:NO];
    [diskPhysicalDiskSelector setAutoenablesItems:NO];
    [diskView addSubview:diskPhysicalDiskSelector];



}

- (void)updateDiskPhysicalDiskSelector {
    MenuMeterDiskIO *io = [[MenuMeterDiskIO alloc] init];
    NSArray *disks = [io physicalDiskList];
    NSArray *selected = [ourPrefs diskSelectedPhysicalDisks];
    [diskPhysicalDiskSelector removeAllItems];
    [diskPhysicalDiskSelector addItemWithTitle:[self localizedPreferenceString:@"All Internal Disks (default)"]];
    [[diskPhysicalDiskSelector lastItem] setToolTip:@"internal-default"];
    for (NSDictionary *disk in disks) {
        NSString *bsd = disk[@"bsdName"];
        NSString *name = disk[@"displayName"];
        BOOL isInternal = [disk[@"isInternal"] boolValue];
        NSString *diskLabel = [NSString stringWithFormat:@"%@ (%@) %@",
                           name, bsd, isInternal ? @"Internal" : @"External"];
        [diskPhysicalDiskSelector addItemWithTitle:diskLabel];
        NSMenuItem *item = [diskPhysicalDiskSelector lastItem];
        [item setToolTip:bsd];
        [item setState:[selected containsObject:bsd] ? NSOnState : NSOffState];
    }
    [diskDisplayMode selectItemAtIndex:-1];
    [diskDisplayMode selectItemAtIndex:[ourPrefs diskDisplayMode] - 1];

    BOOL throughputEnabled = ([ourPrefs diskDisplayMode] & kDiskDisplayThroughput) ? YES : NO;
    [diskPhysicalDiskSelector setEnabled:throughputEnabled];
}

- (void)updateTemperatureSensors
{
    NSArray*sensorNames=[TemperatureReader sensorNames];
    if(!sensorNames || sensorNames.count==0){
        cpuTemperatureSensor.enabled=NO;
        return;
    }
    NSMenu*menu=[cpuTemperatureSensor menu];
    for(NSString*name in sensorNames){
        NSString*displayName=[TemperatureReader displayNameForSensor:name];
        NSMenuItem*item=[menu addItemWithTitle:displayName action:nil keyEquivalent:@""];
        item.toolTip=name;
    }
    NSString*sensor=[ourPrefs cpuTemperatureSensor];
    if([sensor isEqualTo:kCPUTemperatureSensorDefault]){
        sensor=[TemperatureReader defaultSensor];
    }
    NSMenuItem*item=[menu itemWithTitle:[TemperatureReader displayNameForSensor:sensor]];
    if(!item){
        // This means that it is the first launch after migrating to a new Mac with a different set of sensors.
        [ourPrefs saveCpuTemperatureSensor:kCPUTemperatureSensorDefault];
        sensor=[TemperatureReader defaultSensor];
        item=[menu itemWithTitle:[TemperatureReader displayNameForSensor:sensor]];
    }
    [cpuTemperatureSensor selectItem:item];
}
- (void)willSelect {

	// Reread prefs on each load
	ourPrefs = [[MenuMeterDefaults alloc] init];

	// On machines without powermate disable the controls
	if ([MenuMeterPowerMate powermateAttached]) {
		[cpuPowerMate setEnabled:YES];
		[cpuPowerMateMode setEnabled:YES];
	} else {
		[cpuPowerMate setEnabled:NO];
		[cpuPowerMateMode setEnabled:NO];
	}

	// Hook up to SystemConfig Framework
	[self connectSystemConfig];

	// Set the switches on each menu toggle
	[cpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kCPUMenuBundleID] ? NSOnState : NSOffState)];
    [gpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kGPUMenuBundleID] ? NSOnState : NSOffState)];
	[diskMeterToggle setState:([self isExtraWithBundleIDLoaded:kDiskMenuBundleID] ? NSOnState : NSOffState)];
	[memMeterToggle setState:([self isExtraWithBundleIDLoaded:kMemMenuBundleID] ? NSOnState : NSOffState)];
	[netMeterToggle setState:([self isExtraWithBundleIDLoaded:kNetMenuBundleID] ? NSOnState : NSOffState)];

	// Build the preferred interface menu and select (this actually updates the net prefs too)
	[self updateNetInterfaceMenu];
    
    [self updateTemperatureSensors];
	// Reset the controls to match the prefs
	[self menuExtraChangedPrefs:nil];

	// Register for pref change notifications from the extras
	[[NSNotificationCenter defaultCenter] addObserver:self
														selector:@selector(menuExtraChangedPrefs:)
															name:kPrefPaneBundleID
														  object:kPrefChangeNotification];

	// Register for notifications from the extras when they unload
	[[NSNotificationCenter defaultCenter] addObserver:self
														selector:@selector(menuExtraUnloaded:)
															name:@"menuExtraUnloaded"
														  object:nil];
[self updateDiskPhysicalDiskSelector];
} // willSelect

- (void)didUnselect {

	// Unregister all notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];

	// Unhook from SystemConfig Framework
	[self disconnectSystemConfig];

	// Release prefs so it can reconnect next load
	ourPrefs = nil;

} // didUnselect

///////////////////////////////////////////////////////////////
//
//	Notifications
//
///////////////////////////////////////////////////////////////

- (void)menuExtraUnloaded:(NSNotification *)notification {

	NSString *bundleID = [notification object];
	if (bundleID) {
		if ([bundleID isEqualToString:kCPUMenuBundleID]) {
			[cpuMeterToggle setState:NSOffState];
        } else if ([bundleID isEqualToString:kGPUMenuBundleID]) {
            [gpuMeterToggle setState:NSOffState];
		} else if ([bundleID isEqualToString:kDiskMenuBundleID]) {
			[diskMeterToggle setState:NSOffState];
		} else if ([bundleID isEqualToString:kMemMenuBundleID]) {
			[memMeterToggle setState:NSOffState];
		} else if ([bundleID isEqualToString:kNetMenuBundleID]) {
			[netMeterToggle setState:NSOffState];
		}
	}
    [self removeExtraWithBundleID:bundleID];
} // menuExtraUnloaded

- (void)menuExtraChangedPrefs:(NSNotification *)notification {

	if (ourPrefs) {
		[self cpuPrefChange:nil];
        [self gpuPrefChange:nil];
		[self diskPrefChange:nil];
		[self memPrefChange:nil];
		[self netPrefChange:nil];
	}

} // menuExtraChangedDefaults

///////////////////////////////////////////////////////////////
//
//	IB Targets
//
///////////////////////////////////////////////////////////////

- (IBAction)liveUpdateInterval:(id)sender {

	// Clever solution to live updating by exploiting the difference between
	// UI tracking and default runloop mode. See
	// http://www.cocoabuilder.com/archive/message/cocoa/2008/10/17/220399
	if (sender == cpuInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(cpuPrefChange:)
													object:cpuInterval];
		[self performSelector:@selector(cpuPrefChange:)
				   withObject:cpuInterval
				   afterDelay:0.0];
		[cpuIntervalDisplay takeDoubleValueFrom:cpuInterval];
    } else if (sender == gpuInterval) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(gpuPrefChange:)
                                                   object:gpuInterval];
        [self performSelector:@selector(gpuPrefChange:)
                   withObject:gpuInterval
                   afterDelay:0.0];
        [gpuIntervalDisplay takeDoubleValueFrom:gpuInterval];
	} else if (sender == diskInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(diskPrefChange:)
												   object:diskInterval];
		[self performSelector:@selector(diskPrefChange:)
				   withObject:diskInterval
				   afterDelay:0.0];
		[diskIntervalDisplay takeDoubleValueFrom:diskInterval];
	} else if (sender == memInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(memPrefChange:)
												   object:memInterval];
		[self performSelector:@selector(memPrefChange:)
				   withObject:memInterval
				   afterDelay:0.0];
		[memIntervalDisplay takeDoubleValueFrom:memInterval];
	} else if (sender == netInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(netPrefChange:)
												   object:netInterval];
		[self performSelector:@selector(netPrefChange:)
				   withObject:netInterval
				   afterDelay:0.0];
		[netIntervalDisplay takeDoubleValueFrom:netInterval];
	}

} // liveUpdateInterval:

-(int)cpuDisplayMode
{
    int r=0;
    if([cpuPercentage state]==NSOnState)
        r|=kCPUDisplayPercent;
    if([cpuGraph state]==NSOnState)
        r|=kCPUDisplayGraph;
    if([cpuThermometer state]==NSOnState)
        r|=kCPUDisplayThermometer;
    if([cpuHorizontalThermometer state]==NSOnState)
        r|=kCPUDisplayHorizontalThermometer;
#if TARGET_CPU_ARM64
    if([cpuPowerToggle state]==NSOnState)
        r|=kCPUDisplayPower;
#endif
    return r;
}
- (IBAction)cpuPrefChange:(id)sender {

	// Extra load handler
	if (([cpuMeterToggle state] == NSOnState) && ![self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[self loadExtraAtURL:kCPUMenuURL withID:kCPUMenuBundleID];
	} else if (([cpuMeterToggle state] == NSOffState) && [self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[self removeExtraWithBundleID:kCPUMenuBundleID];
	}
	[cpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kCPUMenuBundleID] ? NSOnState : NSOffState)];

	// Save changes
#if TARGET_CPU_ARM64
    BOOL isCPUPowerToggle = (sender == cpuPowerToggle);
#else
    BOOL isCPUPowerToggle = NO;
#endif
    if (sender == cpuPercentage
        || sender == cpuGraph
        || sender == cpuThermometer
        || sender == cpuHorizontalThermometer
        || isCPUPowerToggle) {
		[ourPrefs saveCpuDisplayMode:[self cpuDisplayMode]];
    } else if (sender == cpuTemperatureToggle) {
        bool show = ([cpuTemperatureToggle state] == NSOnState) ? YES : NO;
        [ourPrefs saveCpuTemperature:show];
   } else if (sender == cpuTemperatureUnit) {
       [ourPrefs saveCpuTemperatureUnit:(int)[cpuTemperatureUnit indexOfSelectedItem]];
   } else if (sender==cpuTemperatureSensor){
       NSString*sensor=[cpuTemperatureSensor selectedItem].toolTip;
       if([sensor isEqualToString:[TemperatureReader defaultSensor]]){
           sensor=kCPUTemperatureSensorDefault;
       }
       [ourPrefs saveCpuTemperatureSensor:sensor];
    } else if (sender == cpuInterval) {
		[ourPrefs saveCpuInterval:[cpuInterval doubleValue]];
	} else if (sender == cpuPercentMode) {
		[ourPrefs saveCpuPercentDisplay:(int)[cpuPercentMode indexOfSelectedItem]];
    } else if (sender == cpuMaxProcessCount) {
        [ourPrefs saveCpuMaxProcessCount:(int)[cpuMaxProcessCount intValue]];
	} else if (sender == cpuGraphWidth) {
		[ourPrefs saveCpuGraphLength:[cpuGraphWidth intValue]];
    } else if (sender == cpuHorizontalRows) {
        [ourPrefs saveCpuHorizontalRows:[cpuHorizontalRows intValue]];
    } else if (sender == cpuMenuWidth) {
        [ourPrefs saveCpuMenuWidth:[cpuMenuWidth intValue]];
    } else if (sender == cpuMultipleCPU) {
        switch([cpuMultipleCPU indexOfSelectedItem]){
            case 0:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 1:
                [ourPrefs saveCpuAvgLowerHalfProcs:YES];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 2:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:YES];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 3:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:YES];
                [ourPrefs saveCpuSumAllProcsPercent:YES];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 4:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:YES];
                break;
            default:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            }
	} else if (sender == cpuPowerMate) {
		[ourPrefs saveCpuPowerMate:(([cpuPowerMate state] == NSOnState) ? YES : NO)];
	} else if (sender == cpuPowerMateMode) {
		[ourPrefs saveCpuPowerMateMode:(int)[cpuPowerMateMode indexOfSelectedItem]];
	} else if (sender == cpuUserColor) {
		[ourPrefs saveCpuUserColor:[cpuUserColor color]];
	} else if (sender == cpuSystemColor) {
		[ourPrefs saveCpuSystemColor:[cpuSystemColor color]];
        } else if (sender == cpuTemperatureColor) {
                [ourPrefs saveCpuTemperatureColor:[cpuTemperatureColor color]];
	} else if (!sender) {
		// On first load handle multiprocs options
		if (![self isMultiProcessor]) {
			[ourPrefs saveCpuAvgAllProcs:NO];
			[ourPrefs saveCpuSumAllProcsPercent:NO];
		}
	}

	// Update controls
    [cpuPercentage setState:([ourPrefs cpuDisplayMode]&kCPUDisplayPercent)?NSOnState:NSOffState];
    [cpuGraph setState:([ourPrefs cpuDisplayMode]&kCPUDisplayGraph)?NSOnState:NSOffState];
    [cpuThermometer setState:([ourPrefs cpuDisplayMode]&kCPUDisplayThermometer)?NSOnState:NSOffState];
    [cpuHorizontalThermometer setState:([ourPrefs cpuDisplayMode]&kCPUDisplayHorizontalThermometer)?NSOnState:NSOffState];
#if TARGET_CPU_ARM64
    [cpuPowerToggle setState:([ourPrefs cpuDisplayMode]&kCPUDisplayPower)?NSOnState:NSOffState];
#endif
    if([cpuHorizontalThermometer state]==NSOnState){
        [cpuPercentage setEnabled:NO];
        [cpuGraph setEnabled:NO];
        [cpuThermometer setEnabled:NO];
    }else{
        [cpuPercentage setEnabled:YES];
        [cpuGraph setEnabled:YES];
        [cpuThermometer setEnabled:YES];
    }
    [cpuTemperatureToggle setState:[ourPrefs cpuShowTemperature]];
        [cpuTemperatureUnit selectItemAtIndex:[ourPrefs cpuTemperatureUnit]];
	[cpuInterval setDoubleValue:[ourPrefs cpuInterval]];
	[cpuPercentMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[cpuPercentMode selectItemAtIndex:[ourPrefs cpuPercentDisplay]];
    [cpuMaxProcessCount setIntValue:[ourPrefs cpuMaxProcessCount]];
    [cpuMaxProcessCountCountLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"(%d)", @"DO NOT LOCALIZE!!!"),
                                                  (short)[ourPrefs cpuMaxProcessCount]]];
	[cpuGraphWidth setIntValue:[ourPrefs cpuGraphLength]];
    [cpuHorizontalRows setIntValue:[ourPrefs cpuHorizontalRows]];
    [cpuMenuWidth setIntValue:[ourPrefs cpuMenuWidth]];
    if([ourPrefs cpuSortByUsage]){
        [cpuMultipleCPU selectItemAtIndex:4];
    }else if([ourPrefs cpuSumAllProcsPercent]){
        [cpuMultipleCPU selectItemAtIndex:3];
    }else if([ourPrefs cpuAvgAllProcs]){
        [cpuMultipleCPU selectItemAtIndex:2];
    }else if([ourPrefs cpuAvgLowerHalfProcs]){
        [cpuMultipleCPU selectItemAtIndex:1];
    }else{
        [cpuMultipleCPU selectItemAtIndex:0];
    }
	[cpuPowerMate setState:([ourPrefs cpuPowerMate] ? NSOnState : NSOffState)];
	[cpuPowerMateMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[cpuPowerMateMode selectItemAtIndex:[ourPrefs cpuPowerMateMode]];
	[cpuUserColor setColor:[ourPrefs cpuUserColor]];
	[cpuSystemColor setColor:[ourPrefs cpuSystemColor]];
        [cpuTemperatureColor setColor:[ourPrefs cpuTemperatureColor]];
	[cpuIntervalDisplay takeDoubleValueFrom:cpuInterval];

/*	if ([cpuPercentage state]==NSOnState) {
		[cpuPercentMode setEnabled:YES];
		[cpuPercentModeLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[cpuPercentMode setEnabled:NO];
        [cpuPercentModeLabel setTextColor:[NSColor disabledControlTextColor]];
	}
 */
	if ([cpuGraph state]==NSOnState) {
		[cpuGraphWidth setEnabled:YES];
		[cpuGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[cpuGraphWidth setEnabled:NO];
		[cpuGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
    if ([cpuHorizontalThermometer state]==NSOnState) {
		[cpuHorizontalRows setEnabled:YES];
		[cpuHorizontalRowsLabel setTextColor:[NSColor controlTextColor]];
        [cpuMenuWidth setEnabled:YES];
        [cpuMenuWidthLabel setTextColor:[NSColor controlTextColor]];
    }
    else {
		[cpuHorizontalRows setEnabled:NO];
		[cpuHorizontalRowsLabel setTextColor:[NSColor disabledControlTextColor]];
		[cpuMenuWidth setEnabled:NO];
		[cpuMenuWidthLabel setTextColor:[NSColor disabledControlTextColor]];
    }
/*	if ((([cpuDisplayMode indexOfSelectedItem] + 1) & (kCPUDisplayGraph | kCPUDisplayThermometer | kCPUDisplayHorizontalThermometer)) ||
		((([cpuDisplayMode indexOfSelectedItem] + 1) & kCPUDisplayPercent) &&
			([cpuPercentMode indexOfSelectedItem] == kCPUPercentDisplaySplit))) {*/
		[cpuUserColor setEnabled:YES];
		[cpuSystemColor setEnabled:YES];
		[cpuUserColorLabel setTextColor:[NSColor controlTextColor]];
		[cpuSystemColorLabel setTextColor:[NSColor controlTextColor]];
/*	} else {
		[cpuUserColor setEnabled:NO];
		[cpuSystemColor setEnabled:NO];
		[cpuUserColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[cpuSystemColorLabel setTextColor:[NSColor disabledControlTextColor]];
	}*/

	// Notify
	if ([self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kCPUMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // cpuPrefChange

- (int)gpuDisplayMode
{
    int mode = 0;
    if ([gpuPercentageToggle state] == NSOnState) {
        mode |= kGPUDisplayPercent;
    }
    if ([gpuGraphToggle state] == NSOnState) {
        mode |= kGPUDisplayGraph;
    }
    if ([gpuFrequencyToggle state] == NSOnState) {
        mode |= kGPUDisplayFrequency;
    }
    if ([gpuPowerToggle state] == NSOnState) {
        mode |= kGPUDisplayPower;
    }
    if ([cpuPaneANEPowerToggle state] == NSOnState) {
        mode |= kGPUDisplayANEPower;
    }
    if (mode == 0) {
        mode = kGPUDisplayPercent;
    }
    return mode;
}

- (IBAction)gpuPrefChange:(id)sender
{
    if (!gpuMeterToggle) {
        return;
    }

    if (([gpuMeterToggle state] == NSOnState) && ![self isExtraWithBundleIDLoaded:kGPUMenuBundleID]) {
        [self loadExtraAtURL:nil withID:kGPUMenuBundleID];
    } else if (([gpuMeterToggle state] == NSOffState) && [self isExtraWithBundleIDLoaded:kGPUMenuBundleID]) {
        [self removeExtraWithBundleID:kGPUMenuBundleID];
    }
    [gpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kGPUMenuBundleID] ? NSOnState : NSOffState)];

    BOOL layoutChanged = NO;
    if (sender == gpuPercentageToggle ||
        sender == gpuGraphToggle ||
        sender == gpuFrequencyToggle ||
        sender == gpuPowerToggle ||
        sender == cpuPaneANEPowerToggle) {
        [ourPrefs saveGpuDisplayMode:[self gpuDisplayMode]];
    } else if (sender == gpuInterval) {
        [ourPrefs saveGpuInterval:[gpuInterval doubleValue]];
    } else if (sender == gpuGraphWidth) {
        [ourPrefs saveGpuGraphLength:[gpuGraphWidth intValue]];
    } else if (sender == gpuColor) {
        [ourPrefs saveGpuColor:[gpuColor color]];
    } else if (sender == gpuTextColor) {
        [ourPrefs saveGpuTextColor:[gpuTextColor color]];
    } else if (sender == gpuANEColor) {
        [ourPrefs saveGpuANEColor:[gpuANEColor color]];
    } else if (sender == menuBarPadding) {
        [ourPrefs saveMenuBarHorizontalPadding:[menuBarPadding intValue]];
        layoutChanged = YES;
    }

    int mode = [ourPrefs gpuDisplayMode];
    [gpuPercentageToggle setState:(mode & kGPUDisplayPercent) ? NSOnState : NSOffState];
    [gpuGraphToggle setState:(mode & kGPUDisplayGraph) ? NSOnState : NSOffState];
    [gpuFrequencyToggle setState:(mode & kGPUDisplayFrequency) ? NSOnState : NSOffState];
    [gpuPowerToggle setState:(mode & kGPUDisplayPower) ? NSOnState : NSOffState];
    [cpuPaneANEPowerToggle setState:(mode & kGPUDisplayANEPower) ? NSOnState : NSOffState];

    [gpuInterval setDoubleValue:[ourPrefs gpuInterval]];
    [gpuIntervalDisplay takeDoubleValueFrom:gpuInterval];
    [gpuGraphWidth setIntValue:[ourPrefs gpuGraphLength]];
    [gpuGraphWidthLabel setStringValue:[NSString stringWithFormat:@"%d", [ourPrefs gpuGraphLength]]];
    [menuBarPadding setIntValue:[ourPrefs menuBarHorizontalPadding]];
    [menuBarPaddingLabel setStringValue:[NSString stringWithFormat:@"%d", [ourPrefs menuBarHorizontalPadding]]];
    [gpuColor setColor:[ourPrefs gpuColor]];
    [gpuTextColor setColor:[ourPrefs gpuTextColor]];
    [gpuANEColor setColor:[ourPrefs gpuANEColor]];

    BOOL graphEnabled = (mode & kGPUDisplayGraph) != 0;
    [gpuGraphWidth setEnabled:graphEnabled];
    [gpuGraphWidthLabel setTextColor:graphEnabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];

    if ([self isExtraWithBundleIDLoaded:kGPUMenuBundleID]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kGPUMenuBundleID
                                                            object:kPrefChangeNotification
                                                          userInfo:nil];
    }
    if (layoutChanged) {
        [self notifyAllMenuExtrasOfLayoutChange];
    }
}

- (void)notifyAllMenuExtrasOfLayoutChange
{
    for (NSString *bundleID in @[kCPUMenuBundleID, kGPUMenuBundleID, kDiskMenuBundleID, kMemMenuBundleID, kNetMenuBundleID]) {
        if ([self isExtraWithBundleIDLoaded:bundleID]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:bundleID
                                                                object:kPrefChangeNotification
                                                              userInfo:nil];
        }
    }
}

- (IBAction)diskPrefChange:(id)sender {

	// Extra load
	if (([diskMeterToggle state] == NSOnState) && ![self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[self loadExtraAtURL:kDiskMenuURL withID:kDiskMenuBundleID];
	} else if (([diskMeterToggle state] == NSOffState) && [self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[self removeExtraWithBundleID:kDiskMenuBundleID];
	}
	[diskMeterToggle setState:([self isExtraWithBundleIDLoaded:kDiskMenuBundleID] ? NSOnState : NSOffState)];

	// Save changes
	if (sender == diskDisplayMode) {
		[ourPrefs saveDiskDisplayMode:(int)[diskDisplayMode indexOfSelectedItem] + 1];
	} else if (sender == diskInterval) {
		[ourPrefs saveDiskInterval:[diskInterval doubleValue]];
	} else if (sender == diskSelectMode) {
		[ourPrefs saveDiskSelectMode:(int)[diskSelectMode indexOfSelectedItem]];
	} else if (sender == diskPhysicalDiskSelector) {
		NSInteger idx = [diskPhysicalDiskSelector indexOfSelectedItem];
		if (idx > 0) {
			NSString *bsd = [[diskPhysicalDiskSelector selectedItem] toolTip];
			NSMutableArray *selected = [[ourPrefs diskSelectedPhysicalDisks] mutableCopy];
			if (!selected) selected = [NSMutableArray array];
			if ([selected containsObject:bsd]) {
				[selected removeObject:bsd];
			} else {
				[selected addObject:bsd];
			}
			[ourPrefs saveDiskSelectedPhysicalDisks:selected];
		}
	}

	// Update controls
	[diskImageSet selectItemAtIndex:-1];
	[diskImageSet selectItemAtIndex:[ourPrefs diskImageset]];
	[diskInterval setDoubleValue:[ourPrefs diskInterval]];
	[diskIntervalDisplay takeDoubleValueFrom:diskInterval];
	[diskSelectMode selectItemAtIndex:-1];
	[diskSelectMode selectItemAtIndex:[ourPrefs diskSelectMode]];
	[self updateDiskPhysicalDiskSelector];

	// Notify
	if ([self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDiskMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // diskPrefChange

- (IBAction)memPrefChange:(id)sender {

	// Extra load
	if (([memMeterToggle state] == NSOnState) && ![self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[self loadExtraAtURL:kMemMenuURL withID:kMemMenuBundleID];
	} else if (([memMeterToggle state] == NSOffState) && [self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[self removeExtraWithBundleID:kMemMenuBundleID];
	}
	[memMeterToggle setState:([self isExtraWithBundleIDLoaded:kMemMenuBundleID] ? NSOnState : NSOffState)];

	// Save changes
	if (sender == memDisplayMode) {
		[ourPrefs saveMemDisplayMode:(int)[memDisplayMode indexOfSelectedItem] + 1];
	} else if (sender == memInterval) {
		[ourPrefs saveMemInterval:[memInterval doubleValue]];
	} else if (sender == memFreeUsedLabeling) {
		[ourPrefs saveMemUsedFreeLabel:(([memFreeUsedLabeling state] == NSOnState) ? YES : NO)];
	} else if (sender == memPageIndicator) {
		[ourPrefs saveMemPageIndicator:(([memPageIndicator state] == NSOnState) ? YES : NO)];
    } else if (sender == memPressureMode) {
        [ourPrefs saveMemPressure:(([memPressureMode state] == NSOnState) ? YES : NO)];
	} else if (sender == memGraphWidth) {
		[ourPrefs saveMemGraphLength:[memGraphWidth intValue]];
	} else if (sender == memActiveColor) {
		[ourPrefs saveMemActiveColor:[memActiveColor color]];
	} else if (sender == memInactiveColor) {
		[ourPrefs saveMemInactiveColor:[memInactiveColor color]];
	} else if (sender == memWiredColor) {
		[ourPrefs saveMemWireColor:[memWiredColor color]];
	} else if (sender == memCompressedColor) {
		[ourPrefs saveMemCompressedColor:[memCompressedColor color]];
	} else if (sender == memFreeColor) {
		[ourPrefs saveMemFreeColor:[memFreeColor color]];
	} else if (sender == memUsedColor) {
		[ourPrefs saveMemUsedColor:[memUsedColor color]];
	} else if (sender == memPageinColor) {
		[ourPrefs saveMemPageInColor:[memPageinColor color]];
	} else if (sender == memPageoutColor) {
		[ourPrefs saveMemPageOutColor:[memPageoutColor color]];
	}
	
	// Update controls
	[memDisplayMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[memDisplayMode selectItemAtIndex:[ourPrefs memDisplayMode] - 1];
	[memInterval setDoubleValue:[ourPrefs memInterval]];
	[memFreeUsedLabeling setState:([ourPrefs memUsedFreeLabel] ? NSOnState : NSOffState)];
	[memPageIndicator setState:([ourPrefs memPageIndicator] ? NSOnState : NSOffState)];
    [memPressureMode setState:([ourPrefs memPressure] ? NSOnState : NSOffState)];
	[memGraphWidth setIntValue:[ourPrefs memGraphLength]];
	[memActiveColor setColor:[ourPrefs memActiveColor]];
	[memInactiveColor setColor:[ourPrefs memInactiveColor]];
	[memWiredColor setColor:[ourPrefs memWireColor]];
	[memCompressedColor setColor:[ourPrefs memCompressedColor]];
	[memFreeColor setColor:[ourPrefs memFreeColor]];
	[memUsedColor setColor:[ourPrefs memUsedColor]];
	[memPageinColor setColor:[ourPrefs memPageInColor]];
	[memPageoutColor setColor:[ourPrefs memPageOutColor]];
	[memIntervalDisplay takeIntValueFrom:memInterval];

	// Disable controls as needed
	if ((([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayPie) ||
		(([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayBar) ||
		(([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayGraph)) {
		[memFreeUsedLabeling setEnabled:NO];
	} else {
		[memFreeUsedLabeling setEnabled:YES];
	}
	if (([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayGraph) {
		[memGraphWidth setEnabled:YES];
		[memGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[memGraphWidth setEnabled:NO];
		[memGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	if ([memPageIndicator state] == NSOnState) {
		[memPageinColorLabel setTextColor:[NSColor controlTextColor]];
		[memPageoutColorLabel setTextColor:[NSColor controlTextColor]];
		[memPageinColor setEnabled:YES];
		[memPageoutColor setEnabled:YES];
	} else {
		[memPageinColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[memPageoutColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[memPageinColor setEnabled:NO];
		[memPageoutColor setEnabled:NO];
	}
/*    if (([memDisplayMode indexOfSelectedItem] +1) == kMemDisplayBar) {
        [memPressureMode setEnabled:YES];
    }
    else {
        [memPressureMode setEnabled:NO];
    }*/

	// Notify
	if ([self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMemMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // memPrefChange

- (IBAction)netPrefChange:(id)sender {

	// Extra load
	if (([netMeterToggle state] == NSOnState) && ![self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[self loadExtraAtURL:kNetMenuURL withID:kNetMenuBundleID];
	}
	else if (([netMeterToggle state] == NSOffState) && [self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[self removeExtraWithBundleID:kNetMenuBundleID];
	}
	[netMeterToggle setState:([self isExtraWithBundleIDLoaded:kNetMenuBundleID] ? NSOnState : NSOffState)];

	// Save changes
	if (sender == netDisplayMode) {
		[ourPrefs saveNetDisplayMode:(int)[netDisplayMode indexOfSelectedItem] + 1];
	} else if (sender == netDisplayOrientation) {
		[ourPrefs saveNetDisplayOrientation:(int)[netDisplayOrientation indexOfSelectedItem]];
	} else if (sender == netScaleMode) {
		[ourPrefs saveNetScaleMode:(int)[netScaleMode indexOfSelectedItem]];
	} else if (sender == netScaleCalc) {
		[ourPrefs saveNetScaleCalc:(int)[netScaleCalc indexOfSelectedItem]];
	} else if (sender == netInterval) {
		[ourPrefs saveNetInterval:[netInterval doubleValue]];
	} else if (sender == netThroughputLabeling) {
		[ourPrefs saveNetThroughputLabel:(([netThroughputLabeling state] == NSOnState) ? YES : NO)];
	} else if (sender == netThroughput1KBound) {
		[ourPrefs saveNetThroughput1KBound:(([netThroughput1KBound state] == NSOnState) ? YES : NO)];
	} else if (sender == netThroughputBits) {
		[ourPrefs saveNetThroughputBits:(([netThroughputBits state] == NSOnState) ? YES : NO)];
	} else if (sender == netGraphStyle) {
		[ourPrefs saveNetGraphStyle:(int)[netGraphStyle indexOfSelectedItem]];
	} else if (sender == netGraphWidth) {
		[ourPrefs saveNetGraphLength:[netGraphWidth intValue]];
	} else if (sender == netTxColor) {
		[ourPrefs saveNetTransmitColor:[netTxColor color]];
	} else if (sender == netRxColor) {
		[ourPrefs saveNetReceiveColor:[netRxColor color]];
	} else if (sender == netInactiveColor) {
		[ourPrefs saveNetInactiveColor:[netInactiveColor color]];
	} else if (sender == netPreferInterface) {
		NSMenuItem *menuItem = (NSMenuItem *)[netPreferInterface selectedItem];
		if (menuItem) {
			if (([netPreferInterface indexOfSelectedItem] == 0) || ![menuItem representedObject]) {
				[ourPrefs saveNetPreferInterface:kNetPrimaryInterface];
			} else {
				[ourPrefs saveNetPreferInterface:[menuItem representedObject]];
			}
		}
	}

	// Update controls
	[netDisplayMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netDisplayMode selectItemAtIndex:[ourPrefs netDisplayMode] - 1];
	[netDisplayOrientation selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netDisplayOrientation selectItemAtIndex:[ourPrefs netDisplayOrientation]];
	[netScaleMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netScaleMode selectItemAtIndex:[ourPrefs netScaleMode]];
	[netScaleCalc selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netScaleCalc selectItemAtIndex:[ourPrefs netScaleCalc]];
	[netInterval setDoubleValue:[ourPrefs netInterval]];
	[netThroughputLabeling setState:([ourPrefs netThroughputLabel] ? NSOnState : NSOffState)];
	[netThroughput1KBound setState:([ourPrefs netThroughput1KBound] ? NSOnState : NSOffState)];
	[netThroughputBits setState:([ourPrefs netThroughputBits] ? NSOnState : NSOffState)];
	[netGraphStyle selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netGraphStyle selectItemAtIndex:[ourPrefs netGraphStyle]];
	[netGraphWidth setIntValue:[ourPrefs netGraphLength]];
	[netTxColor setColor:[ourPrefs netTransmitColor]];
	[netRxColor setColor:[ourPrefs netReceiveColor]];
	[netInactiveColor setColor:[ourPrefs netInactiveColor]];
	[netIntervalDisplay takeDoubleValueFrom:netInterval];
	if ([[ourPrefs netPreferInterface] isEqualToString:kNetPrimaryInterface]) {
		[netPreferInterface selectItemAtIndex:0];
	} else {
		BOOL foundBetterItem = NO;
		NSArray *itemsArray = [netPreferInterface itemArray];
		if (itemsArray) {
			NSEnumerator *itemsEnum = [itemsArray objectEnumerator];
			NSMenuItem *menuItem = nil;
			while ((menuItem = [itemsEnum nextObject])) {
				if ([menuItem representedObject]) {
					if ([[ourPrefs netPreferInterface] isEqualToString:[menuItem representedObject]]) {
						[netPreferInterface selectItem:menuItem];
						foundBetterItem = YES;
					}
				}
			}
		}
		if (!foundBetterItem) {
			[netPreferInterface selectItemAtIndex:0];
			[ourPrefs saveNetPreferInterface:kNetPrimaryInterface];
		}
	}

	// Disable controls as needed
	if (([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayThroughput) {
		[netThroughputLabeling setEnabled:YES];
		[netThroughput1KBound setEnabled:YES];
		[netThroughputBits setEnabled:YES];
	} else {
		[netThroughputLabeling setEnabled:NO];
		[netThroughput1KBound setEnabled:NO];
		[netThroughputBits setEnabled:NO];
	}
	if (([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayGraph) {
		[netGraphStyle setEnabled:YES];
		[netGraphStyleLabel setTextColor:[NSColor controlTextColor]];
		[netGraphWidth setEnabled:YES];
		[netGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[netGraphStyle setEnabled:NO];
		[netGraphStyleLabel setTextColor:[NSColor disabledControlTextColor]];
		[netGraphWidth setEnabled:NO];
		[netGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	if ((([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayArrows) ||
		(([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayGraph)) {
		[netScaleMode setEnabled:YES];
		[netScaleModeLabel setTextColor:[NSColor controlTextColor]];
		[netScaleCalc setEnabled:YES];
		[netScaleCalcLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[netScaleMode setEnabled:NO];
		[netScaleModeLabel setTextColor:[NSColor disabledControlTextColor]];
		[netScaleCalc setEnabled:NO];
		[netScaleCalcLabel setTextColor:[NSColor disabledControlTextColor]];
	}

	// Notify
	if ([self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kNetMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // netPrefChange

///////////////////////////////////////////////////////////////
//
//	Menu extra manipulations
//
///////////////////////////////////////////////////////////////

- (void)loadExtraAtURL:(NSURL *)extraURL withID:(NSString *)bundleID {
#ifdef ELCAPITAN
    [ourPrefs saveBoolPref:bundleID value:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:bundleID
                                                                   object:kPrefChangeNotification
                                                                 userInfo:nil];
    return;
#else
	// Load the crack. With MenuCracker 2.x multiple loads are allowed, so
	// we don't care if someone else has the MenuCracker 2.x bundle loaded.
	// Plus, since MC 2.x does dodgy things with the load we can't actually
	// find out if its loaded.
	CoreMenuExtraAddMenuExtra((CFURLRef)kMenuCrackerURL, 0, 0, 0, 0, 0);

	// Load actual request
	CoreMenuExtraAddMenuExtra((CFURLRef)extraURL, 0, 0, 0, 0, 0);

	// Wait for the item to load
	int microSlept = 0;
	while (![self isExtraWithBundleIDLoaded:bundleID] && (microSlept < kWaitForExtraLoadMicroSec)) {
		microSlept += kWaitForExtraLoadStepMicroSec;
		usleep(kWaitForExtraLoadStepMicroSec);
	}

	// Try again if needed
	if (![self isExtraWithBundleIDLoaded:bundleID]) {
		microSlept = 0;
		CoreMenuExtraAddMenuExtra((CFURLRef)extraURL, 0, 0, 0, 0, 0);
		while (![self isExtraWithBundleIDLoaded:bundleID] && (microSlept < kWaitForExtraLoadMicroSec)) {
			microSlept += kWaitForExtraLoadStepMicroSec;
			usleep(kWaitForExtraLoadStepMicroSec);
		}
	}

	// Give up
	if (![self isExtraWithBundleIDLoaded:bundleID]) {
		[self showMenuExtraErrorSheet];
	}
#endif
} // loadExtraAtURL:withID:

- (BOOL)isExtraWithBundleIDLoaded:(NSString *)bundleID {
    return [ourPrefs loadBoolPref:bundleID defaultValue:YES];
} // isExtraWithBundleIDLoaded

- (void)removeExtraWithBundleID:(NSString *)bundleID {
    [ourPrefs saveBoolPref:bundleID value:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:bundleID
                                                                   object:kPrefChangeNotification
     userInfo:nil];
    if([self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [self.window makeKeyAndOrderFront:self];
    }
    return;
} // removeExtraWithBundleID

- (void)showMenuExtraErrorSheet {

	NSBeginAlertSheet(
		// Title
		[[NSBundle bundleForClass:[self class]] localizedStringForKey:@"Menu Extra Could Not Load"
																value:nil
																table:nil],
		// Default button
		nil,
		// Alternate button
		nil,
		// Other button
		nil,
		// Window
		[[self mainView] window],
		// Delegate
		nil,
		// end elector
		nil,
		// dismiss selector
		nil,
		// context
		nil,
		// msg
        @"%@",
		[[NSBundle bundleForClass:[self class]]
			localizedStringForKey:@"For instructions on enabling third-party menu extras please see the documentation."
							value:nil
							table:nil]);

} // showMenuExtraErrorSheet

///////////////////////////////////////////////////////////////
//
//	Net prefs update
//
///////////////////////////////////////////////////////////////

- (void)updateNetInterfaceMenu {

	// Start by removing all items but the first
	while ([netPreferInterface numberOfItems] > 1) {
		[netPreferInterface removeItemAtIndex:[netPreferInterface numberOfItems] - 1];
	}

	// Now populate
	NSMenu *popupMenu = [netPreferInterface menu];
	if (!popupMenu) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}

	// Get the dict block for services
	NSDictionary *ipDict = [self sysconfigValueForKey:@"Setup:/Network/Global/IPv4"];
	if (!ipDict) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}
	// Get the array of services
	NSArray *serviceArray = [ipDict objectForKey:@"ServiceOrder"];
	if (!serviceArray) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}

	NSEnumerator *serviceEnum = [serviceArray objectEnumerator];
	NSString *serviceID = nil;
	int	selectIndex = 0;
	while ((serviceID = [serviceEnum nextObject])) {
		NSString *longName = nil, *shortName = nil, *pppName = nil;
		// Get interface details
		NSDictionary *interfaceDict = [self sysconfigValueForKey:
										[NSString stringWithFormat:@"Setup:/Network/Service/%@/Interface", serviceID]];
		if (!interfaceDict) continue;
		// This code is a quasi-clone of the code in MenuMeterNetConfig.
		// Look there to see what all this means
		if ([interfaceDict objectForKey:@"UserDefinedName"]) {
			longName = [interfaceDict objectForKey:@"UserDefinedName"];
		} else if ([interfaceDict objectForKey:@"Hardware"]) {
			longName = [interfaceDict objectForKey:@"Hardware"];
		}
		if ([interfaceDict objectForKey:@"DeviceName"]) {
			shortName = [interfaceDict objectForKey:@"DeviceName"];
		}
		NSDictionary *pppDict = [self sysconfigValueForKey:
									[NSString stringWithFormat:@"State:/Network/Service/%@/PPP", serviceID]];
		if (pppDict && [pppDict objectForKey:@"InterfaceName"]) {
			pppName = [pppDict objectForKey:@"InterfaceName"];
		}
		// Now we can try to build the item
		if (!shortName) continue;  // Nothing to key off, bail
		if (!longName) longName = @"Unknown Interface";
		if (!shortName && pppName) {
			// Swap pppName for short name
			shortName = pppName;
			pppName = nil;
		}
		if (longName && shortName && pppName) {
			NSMenuItem *newMenuItem = (NSMenuItem *)[popupMenu addItemWithTitle:
														[NSString stringWithFormat:@"%@ (%@, %@)", longName, shortName, pppName]
																		action:nil
																 keyEquivalent:@""];
			[newMenuItem setRepresentedObject:shortName];
			// Update the selected index if appropriate
			if ([shortName isEqualToString:[ourPrefs netPreferInterface]]) {
				selectIndex = (int)[popupMenu numberOfItems] - 1;
			}
		} else if (longName && shortName) {
			NSMenuItem *newMenuItem = (NSMenuItem *)[popupMenu addItemWithTitle:
														[NSString stringWithFormat:@"%@ (%@)", longName, shortName]
																		 action:nil
																  keyEquivalent:@""];
			[newMenuItem setRepresentedObject:shortName];
			// Update the selected index if appropriate
			if ([shortName isEqualToString:[ourPrefs netPreferInterface]]) {
				selectIndex = (int)[popupMenu numberOfItems] - 1;
			}
		}
	}

	// Menu is built, pick
	if ((selectIndex < 0) || (selectIndex >= [popupMenu numberOfItems])) {
		selectIndex = 0;
	}
	[netPreferInterface selectItemAtIndex:selectIndex];
	[self netPrefChange:netPreferInterface];

} // updateNetInterfaceMenu

///////////////////////////////////////////////////////////////
//
//	CPU info
//
///////////////////////////////////////////////////////////////

- (BOOL)isMultiProcessor {

	uint32_t cpuCount = 0;
	size_t sysctlLength = sizeof(cpuCount);
	int mib[2] = { CTL_HW, HW_NCPU };
	if (sysctl(mib, 2, &cpuCount, &sysctlLength, NULL, 0)) return NO;
	if (cpuCount > 1) {
		return YES;
	} else {
		return NO;
	}

} // isMultiProcessor

///////////////////////////////////////////////////////////////
//
// 	System config framework
//
///////////////////////////////////////////////////////////////

- (void)connectSystemConfig {

	// Create the callback context
	SCDynamicStoreContext scContext;
	scContext.version = 0;
	scContext.info = (__bridge void * _Nullable)(self);
	scContext.retain = NULL;
	scContext.release = NULL;
	scContext.copyDescription = NULL;

	// And create the session, somewhat bizarrely, passing anything other than [self description]
	// cause an occassional crash in the callback.
	scSession = SCDynamicStoreCreate(kCFAllocatorDefault,
									 (CFStringRef)[self description],
									 scChangeCallback,
									 &scContext);
	if (!scSession) {
		NSLog(@"MenuMetersPref unable to establish configd session.");
		return;
	}

	// Install notification run source
	if (!SCDynamicStoreSetNotificationKeys(scSession,
										   (CFArrayRef)[NSArray arrayWithObjects:
														@"State:/Network/Global/IPv4",
														@"Setup:/Network/Global/IPv4",
														@"State:/Network/Interface", nil],
										   (CFArrayRef)[NSArray arrayWithObjects:
														@"State:/Network/Interface.*", nil])) {
		NSLog(@"MenuMetersPref unable to install configd notification keys.");
		CFRelease(scSession);
		scSession = NULL;
		return;
	}
	scRunSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, scSession, 0);
	if (!scRunSource) {
		NSLog(@"MenuMetersPref unable to get configd notification keys run loop source.");
		CFRelease(scSession);
		scSession = NULL;
		return;
	}
	CFRunLoopAddSource(CFRunLoopGetCurrent(), scRunSource, kCFRunLoopDefaultMode);

} // connectSystemConfig

- (void)disconnectSystemConfig {

	// Remove the runsource
	if (scRunSource) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), scRunSource, kCFRunLoopDefaultMode);
		CFRelease(scRunSource);
		scRunSource = NULL;
	}

	// Kill our configd session
	if (scSession) {
		CFRelease(scSession);
		scSession = NULL;
	}

} // disconnectSystemConfig

- (NSDictionary *)sysconfigValueForKey:(NSString *)key {

	if (!scSession) return nil;
	return (NSDictionary *)CFBridgingRelease(SCDynamicStoreCopyValue(scSession, (CFStringRef)key));

} // sysconfigValueForKey

@end
