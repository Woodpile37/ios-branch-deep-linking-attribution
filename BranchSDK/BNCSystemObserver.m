//
//  BNCSystemObserver.m
//  BranchSDK
//
//  Created by Alex Austin on 6/5/14.
//  Copyright (c) 2014 Branch Metrics. All rights reserved.
//

#import "BNCSystemObserver.h"
#import "BNCLog.h"
#if __has_feature(modules)
@import UIKit;
@import SystemConfiguration;
@import Darwin.POSIX.sys.utsname;
#else
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/utsname.h>
#endif

#if !TARGET_OS_TV
#if __has_feature(modules)
@import AdServices;
#else
#import <AdServices/AdServices.h>
#endif
#endif

@implementation BNCSystemObserver

+ (NSString *)appleAttributionToken {
    // token is not available on simulator
    if ([self isSimulator]) {
        return nil;
    }
    
    __block NSString *token = nil;
    
#if !TARGET_OS_TV
    if (@available(iOS 14.3, macCatalyst 14.3, *)) {

        // We are getting reports on iOS 14.5 that this API can hang, adding a short timeout for now.
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error;
            NSString *appleAttributionToken = [AAAttribution attributionTokenWithError:&error];
            if (!error) {
                token = appleAttributionToken;
            }
            dispatch_semaphore_signal(semaphore);
        });

        // Apple said this API should respond within 50ms, lets give up after 500 ms
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)));
        if (token == nil) {
            BNCLogDebug([NSString stringWithFormat:@"AppleAttributionToken request timed out"]);
        }
    }
#endif
    
    return token;
}

+ (NSString *)advertiserIdentifier {
    #ifdef BRANCH_EXCLUDE_IDFA_CODE
    return nil;
    
    #else
    NSString *uid = nil;
    Class ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        SEL sharedManagerSelector = NSSelectorFromString(@"sharedManager");
        id sharedManager =
            ((id (*)(id, SEL))[ASIdentifierManagerClass methodForSelector:sharedManagerSelector])
                (ASIdentifierManagerClass, sharedManagerSelector);
        SEL advertisingIdentifierSelector = NSSelectorFromString(@"advertisingIdentifier");
        NSUUID *uuid =
            ((NSUUID* (*)(id, SEL))[sharedManager methodForSelector:advertisingIdentifierSelector])
                (sharedManager, advertisingIdentifierSelector);
        uid = [uuid UUIDString];
        if ([uid isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
            uid = nil;
        }
    }
    return uid;
    #endif
}

// Returns AppTrackingTransparency status. It does not trigger the prompt.
+ (NSString *)attOptedInStatus {
    NSString *statusString = @"unavailable";

    #ifdef BRANCH_EXCLUDE_ATT_STATUS_CODE
    #else

    Class ATTrackingManagerClass = NSClassFromString(@"ATTrackingManager");
    if (ATTrackingManagerClass) {
        SEL trackingAuthorizationStatusSelector = NSSelectorFromString(@"trackingAuthorizationStatus");
        unsigned long status = ((unsigned long (*)(id, SEL))[ATTrackingManagerClass methodForSelector:trackingAuthorizationStatusSelector])(ATTrackingManagerClass, trackingAuthorizationStatusSelector);
        
        // map ATT status to string values
        switch (status) {
            case 0:
                statusString = @"not_determined";
                break;
            case 1:
                statusString = @"restricted";
                break;
            case 2:
                statusString = @"denied";
                break;
            case 3:
                statusString = @"authorized";
                break;
            default:
                break;
        }
    }
    
    #endif
    return statusString;
}

+ (NSString *)defaultURIScheme {
    NSArray *urlTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];

    for (NSDictionary *urlType in urlTypes) {
        NSArray *urlSchemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *uriScheme in urlSchemes) {
            if ([uriScheme hasPrefix:@"fb"]) continue;  // Facebook
            if ([uriScheme hasPrefix:@"db"]) continue;  // DB?
            if ([uriScheme hasPrefix:@"twitterkit-"]) continue; // Twitter
            if ([uriScheme hasPrefix:@"pdk"]) continue; // Pinterest
            if ([uriScheme hasPrefix:@"pin"]) continue; // Pinterest
            if ([uriScheme hasPrefix:@"com.googleusercontent.apps"]) continue; // Google

            // Otherwise this must be it!
            return uriScheme;
        }
    }
    return nil;
}

+ (NSString *)bundleIdentifier {
    return [[NSBundle mainBundle] bundleIdentifier];
}

+ (NSString *)teamIdentifier {
    NSString *teamWithDot = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"AppIdentifierPrefix"];
    if (teamWithDot.length) {
        return [teamWithDot substringToIndex:([teamWithDot length] - 1)];
    }
    return nil;
}

+ (BOOL)isAppClip {
    // App Clips have a zero'd out IDFV
    if ([@"00000000-0000-0000-0000-000000000000" isEqualToString:[[UIDevice currentDevice].identifierForVendor UUIDString]]) {
        return YES;
    }
    return NO;
}

+ (NSString *)applicationVersion {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    if (!version.length) {
        version = [NSBundle mainBundle].infoDictionary[@"CFBundleVersionKey"];
    }
    return version;
}

+ (NSString *)environment {
    NSString *result = @"FULL_APP";
    
    if ([self isAppClip]) {
        result = @"APP_CLIP";
    }
    
    // iMessage has an extension id set in the Bundle
    NSString *extensionType = [NSBundle mainBundle].infoDictionary[@"NSExtension"][@"NSExtensionPointIdentifier"];
    if ([extensionType isEqualToString:@"com.apple.identitylookup.message-filter"]) {
        result = @"IMESSAGE_APP";
    }
    
    return result;
}

+ (NSString *)brand {
    return @"Apple";
}

+ (NSString *)model {
    struct utsname systemInfo;
    uname(&systemInfo);

    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (BOOL)isSimulator {
    #if (TARGET_OS_SIMULATOR)
    return YES;
    #else
    return NO;
    #endif
}

+ (NSString *)osName {
    #if TARGET_OS_TV
    return @"tv_OS";
    #else
    return @"iOS";
    #endif
}

+ (NSString *)osVersion {
    UIDevice *device = [UIDevice currentDevice];
    return [device systemVersion];
}

+ (NSNumber *)screenWidth {
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGFloat scaleFactor = mainScreen.scale;
    CGFloat width = mainScreen.bounds.size.width * scaleFactor;
    return [NSNumber numberWithInteger:(NSInteger)width];
}

+ (NSNumber *)screenHeight {
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGFloat scaleFactor = mainScreen.scale;
    CGFloat height = mainScreen.bounds.size.height * scaleFactor;
    return [NSNumber numberWithInteger:(NSInteger)height];
}

+ (NSNumber *)screenScale {
    return @([UIScreen mainScreen].scale);
}

@end
