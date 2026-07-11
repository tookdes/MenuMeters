//
//  Copyright (c) 2014 Enrico M. Crisostomo. All rights reserved.
//
//  License: BSD 3-Clause License
//  (http://opensource.org/licenses/BSD-3-Clause)
//

#import <Foundation/Foundation.h>

@interface EMCLoginItem : NSObject

- (instancetype)initWithBundle:(NSBundle *)bundle;
- (instancetype)initWithPath:(NSString *)path;

- (BOOL)isLoginItem;
- (void)addLoginItem;
- (void)removeLoginItem;
+ (instancetype)loginItemWithBundle:(NSBundle *)bundle;
+ (instancetype)loginItemWithPath:(NSString *)path;

@end
