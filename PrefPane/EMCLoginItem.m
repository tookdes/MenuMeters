//
//  Created by Enrico Maria Crisostomo on 04/05/14.
//  Copyright (c) 2014 Enrico M. Crisostomo. All rights reserved.
//
//  License: BSD 3-Clause License
//  (http://opensource.org/licenses/BSD-3-Clause)
//

#import "EMCLoginItem.h"

#if !__has_feature(objc_arc)
#error This class requires ARC support to be enabled.
#endif

@implementation EMCLoginItem
{
    CFURLRef url;
}

- (void)dealloc
{
    if (url)
    {
        CFRelease(url);
    }
}

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    if (!bundle)
    {
        NSException* nullException = [NSException
                                      exceptionWithName:@"NullPointerException"
                                      reason:@"Bundle cannot be null."
                                      userInfo:nil];
        @throw nullException;
    }
    
    self = [super init];
    
    if (self)
    {
        NSString * appPath = [bundle bundlePath];
        [self initHelper:appPath];
    }
    
    return self;
}

- (instancetype)initWithPath:(NSString *)appPath
{
    if (!appPath)
    {
        NSException* nullException = [NSException
                                      exceptionWithName:@"NullPointerException"
                                      reason:@"Path cannot be null."
                                      userInfo:nil];
        @throw nullException;
    }
    
    self = [super init];
    
    if (self)
    {
        [self initHelper:appPath];
    }
    
    return self;
}

- (void)initHelper:(NSString *)appPath
{
    url = (CFURLRef)CFBridgingRetain([NSURL fileURLWithPath:appPath]);
}

+ (instancetype)loginItemWithBundle:(NSBundle *)bundle
{
    return [[EMCLoginItem alloc] initWithBundle:bundle];
}

+ (instancetype)loginItemWithPath:(NSString *)path
{
    return [[EMCLoginItem alloc] initWithPath:path];
}

- (BOOL)isLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    
    if (loginItems)
    {
        UInt32 seed;
        NSArray* loginItemsArray = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
        
        for (id item in loginItemsArray)
        {
            LSSharedFileListItemRef loginItem = (__bridge LSSharedFileListItemRef)item;
            CFURLRef itemUrl;
            
            if (LSSharedFileListItemResolve(loginItem, kLSSharedFileListNoUserInteraction|kLSSharedFileListDoNotMountVolumes, &itemUrl, NULL) == noErr)
            {
                BOOL isTargetItem = CFEqual(itemUrl, url);
                CFRelease(itemUrl);
                if (isTargetItem)
                {
                    CFRelease(loginItems);
                    return YES;
                }
            }
            else
            {
                NSLog(@"Error: LSSharedFileListItemResolve failed.");
            }
        }
        CFRelease(loginItems);
    }
    else
    {
        NSLog(@"Warning: LSSharedFileListCreate failed, could not get list of login items.");
    }
    
    return NO;
}

- (void)addLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    
    if (!loginItems)
    {
        NSLog(@"Error: LSSharedFileListCreate failed, could not get list of login items.");
        return;
    }
    
    // If an item path has been specified as specific insertion point for the
    // login item to add, then look for it.
    LSSharedFileListItemRef insertedItem = LSSharedFileListInsertItemURL(loginItems,
                                                                         kLSSharedFileListItemLast,
                                                                         NULL,
                                                                         NULL,
                                                                         url,
                                                                         NULL,
                                                                         NULL);
    if(!insertedItem)
    {
        NSLog(@"Error: LSSharedFileListInsertItemURL failed, could not create login item.");
    }
    else
    {
        CFRelease(insertedItem);
    }
    CFRelease(loginItems);
}

- (void)removeLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    if (loginItems)
    {
        BOOL removed = NO;
        UInt32 seed;
        NSArray* loginItemsArray = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
        
        for (id item in loginItemsArray)
        {
            LSSharedFileListItemRef loginItem = (__bridge LSSharedFileListItemRef)item;
            CFURLRef itemUrl;
            
            if (LSSharedFileListItemResolve(loginItem, kLSSharedFileListNoUserInteraction|kLSSharedFileListDoNotMountVolumes, &itemUrl, NULL) == noErr)
            {
                BOOL isTargetItem = CFEqual(itemUrl, url);
                CFRelease(itemUrl);
                if (isTargetItem)
                {
                    if (LSSharedFileListItemRemove(loginItems, loginItem) == noErr)
                    {
                        removed = YES;
                        break;
                    }
                    else
                    {
                        NSLog(@"Error: Unknown error while removing login item.");
                    }
                }
            }
            else
            {
                NSLog(@"Warning: LSSharedFileListItemResolve failed, could not resolve item.");
            }
        }
        
        if (!removed)
        {
            NSLog(@"Error: could not find login item to remove.");
        }
        CFRelease(loginItems);
    }
    else
    {
        NSLog(@"Warning: could not get list of login items.");
    }
}

@end
