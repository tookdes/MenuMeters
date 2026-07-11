//
//  AppDelegate.m
//  MenuMetersApp
//
//  Created by Yuji on 2015/07/30.
//
//

#import "AppDelegate.h"
#import "MenuMeterCPUExtra.h"
#import "MenuMeterDiskExtra.h"
#import "MenuMeterGPUExtra.h"
#import "MenuMeterMemExtra.h"
#import "MenuMeterNetExtra.h"
#import "MenuMetersPref.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate
{
    MenuMeterCPUExtra*cpuExtra;
    MenuMeterDiskExtra*diskExtra;
    MenuMeterGPUExtra*gpuExtra;
    MenuMeterNetExtra*netExtra;
    MenuMeterMemExtra*memExtra;
    MenuMetersPref*pref;
}

-(void)killOlderInstances{
    NSString*thisVersion=NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"];
    for(NSRunningApplication* x in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.yujitach.MenuMeters"]){
        if([x isEqualTo:NSRunningApplication.currentApplication]){
            continue;
        }
        NSBundle*b=[NSBundle bundleWithURL:x.bundleURL];
        NSString*version=b.infoDictionary[@"CFBundleVersion"];
        NSComparisonResult r=[version compare:thisVersion options:NSNumericSearch];
        NSLog(@"vers: running is %@, ours is %@, compare result was %ld", version, thisVersion, r);
        if(r!=NSOrderedDescending){
            NSLog(@"version %@ already running, which is equal or older than this binary %@. Going to kill it.",version,thisVersion);
            [x terminate];
        }
    }
}
- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [MenuMeterDefaults movePreferencesIfNecessary];
}
#define WELCOME @"v2.0.8alert"
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [NSColor setIgnoresAlpha:NO];
    if([self isRunningOnReadOnlyVolume]){
        [self alertConcerningAppTranslocation];
    }
    [self killOlderInstances];
    pref=[[MenuMetersPref alloc] initWithAboutFileName:WELCOME];
    NSString*key=[WELCOME stringByAppendingString:@"Presented"];
    if(![[NSUserDefaults standardUserDefaults] boolForKey:key]){
        [pref openAbout:WELCOME];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
    }
    // init of extras were moved to the last step.
    // It is because init of extras can raise exceptions when I introduce bugs.
    // If extras are init'ed first and raise, the preferences window is not live yet.
    // When extras are inited last, at least the pref pane is available for troubleshooting.
    cpuExtra=[[MenuMeterCPUExtra alloc] init];
    gpuExtra=[[MenuMeterGPUExtra alloc] init];
    diskExtra=[[MenuMeterDiskExtra alloc] init];
    netExtra=[[MenuMeterNetExtra alloc] init];
    memExtra=[[MenuMeterMemExtra alloc] init];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [pref.window makeKeyAndOrderFront:sender];
    return YES;
}


- (BOOL)isRunningOnReadOnlyVolume {
    // taken from https://github.com/Squirrel/Squirrel.Mac/pull/186/files
    struct statfs statfsInfo;
    NSURL *bundleURL = NSRunningApplication.currentApplication.bundleURL;
    int result = statfs(bundleURL.fileSystemRepresentation, &statfsInfo);
    if (result == 0) {
        return (statfsInfo.f_flags & MNT_RDONLY) != 0;
    } else {
        // If we can't even check if the volume is read-only, assume it is.
        return YES;
    }
}

-(void)alertConcerningAppTranslocation{
    NSAlert*alert=[[NSAlert alloc] init];
    alert.messageText=NSLocalizedString(@"Please move MenuMeters to Applications", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Quit MenuMeters", nil)];
    alert.informativeText=NSLocalizedString(@"MenuMeters cannot reliably launch at login from a read-only volume. Move it to /Applications, then open it again.", nil);
    [alert runModal];
    [NSApp terminate:nil];
}

@end
