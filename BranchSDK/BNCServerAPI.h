//
//  BNCServerAPI.h
//  BranchSDK
//
//  Created by Nidhi Dixit on 8/29/23.
//

#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface BNCServerAPI : NSObject

+ (BNCServerAPI *)sharedInstance;

// BNCServerInterface takes a NSString and is using url.absoluteString
- (NSURL *)installServiceURL;
- (NSURL *)openServiceURL;
- (NSURL *)standardEventServiceURL;
- (NSURL *)customEventServiceURL;
- (NSURL *)linkServiceURL;

@property (nonatomic, assign, readwrite) BOOL useTrackingDomain;
@property (nonatomic, assign, readwrite) BOOL useEUServers;

// Enable tracking domains based on IDFA authorization. YES by default
// Used to enable unit tests without regard for ATT authorization status
@property (nonatomic, assign, readwrite) BOOL automaticallyEnableTrackingDomain;

@end

NS_ASSUME_NONNULL_END



