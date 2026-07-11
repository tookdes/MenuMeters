//
//  MenuMeterDiskExtra.h
//
//	Menu Extra implementation with throughput display
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "MenuMeters.h"
#import "MenuMeterDefaults.h"
#import "MenuMeterDisk.h"
#import "MenuMeterDiskIO.h"
#import "MenuMeterDiskSpace.h"
#import "MenuMeterWorkarounds.h"


@interface MenuMeterDiskExtra : NSMenuExtra {

	// Menu Extra necessities
	NSMenu 							*extraMenu;
	// Pref object
	MenuMeterDefaults				*ourPrefs;
	// Info gatherers
	MenuMeterDiskIO					*diskIOMonitor;
	MenuMeterDiskSpace				*diskSpaceMonitor;
	// Legacy display state and images
	NSImage							*idleImageLight, *readImageLight, *writeImageLight, *readwriteImageLight;
    NSImage                         *idleImageDark, *readImageDark, *writeImageDark, *readwriteImageDark;
	DiskIOActivityType				displayedActivity;
	// Throughput display
	NSFont							*throughputFont;
	// Theme support
	NSColor							*fgMenuThemeColor;

} // MenuMeterDiskExtra

@end
