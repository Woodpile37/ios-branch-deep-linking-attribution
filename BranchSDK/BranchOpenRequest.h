//
//  BranchOpenRequest.h
//  Branch-TestBed
//
//  Created by Graham Mueller on 5/26/15.
//  Copyright (c) 2015 Branch Metrics. All rights reserved.
//

#import "BNCServerRequest.h"
#import "BNCCallbacks.h"

@interface BranchOpenRequest : BNCServerRequest

@property (nonatomic, copy) callbackWithStatus callback;

+ (void) waitForOpenResponseLock;
+ (void) releaseOpenResponseLock;
+ (void) setWaitNeededForOpenResponseLock;

- (id)initWithCallback:(callbackWithStatus)callback;
- (id)initWithCallback:(callbackWithStatus)callback isInstall:(BOOL)isInstall;

@end
