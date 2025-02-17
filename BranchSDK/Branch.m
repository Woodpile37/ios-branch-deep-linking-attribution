//
//  Branch_SDK.m
//  Branch-SDK
//
//  Created by Alex Austin on 6/5/14.
//  Copyright (c) 2014 Branch Metrics. All rights reserved.
//

#import "Branch.h"
#import "BNCConfig.h"
#import "BNCCrashlyticsWrapper.h"
#import "BNCDeepLinkViewControllerInstance.h"
#import "BNCEncodingUtils.h"
#import "BNCLinkData.h"
#import "BNCNetworkService.h"
#import "BNCPreferenceHelper.h"
#import "BNCServerRequest.h"
#import "BNCServerRequestQueue.h"
#import "BNCServerResponse.h"
#import "BNCSystemObserver.h"
#import "BranchConstants.h"
#import "BranchInstallRequest.h"
#import "BranchJsonConfig.h"
#import "BranchOpenRequest.h"
#import "BranchShortUrlRequest.h"
#import "BranchShortUrlSyncRequest.h"
#import "BranchSpotlightUrlRequest.h"
#import "BranchUniversalObject.h"
#import "NSMutableDictionary+Branch.h"
#import "NSString+Branch.h"
#import "Branch+Validator.h"
#import "BNCApplication.h"
#import "BNCURLFilter.h"
#import "BNCDeviceInfo.h"
#import "BNCCallbackMap.h"
#import "BNCSKAdNetwork.h"
#import "BNCAppGroupsData.h"
#import "BNCPartnerParameters.h"
#import "BranchEvent.h"
#import "BNCPasteboard.h"
#import "NSError+Branch.h"
#import "BNCLog.h"
#import "UIViewController+Branch.h"
#import "BNCReferringURLUtility.h"
#import "BNCServerAPI.h"

#if !TARGET_OS_TV
#import "BNCUserAgentCollector.h"
#import "BNCSpotlightService.h"
#import "BNCContentDiscoveryManager.h"
#import "BranchContentDiscoverer.h"
#endif

NSString * const BRANCH_FEATURE_TAG_SHARE = @"share";
NSString * const BRANCH_FEATURE_TAG_REFERRAL = @"referral";
NSString * const BRANCH_FEATURE_TAG_INVITE = @"invite";
NSString * const BRANCH_FEATURE_TAG_DEAL = @"deal";
NSString * const BRANCH_FEATURE_TAG_GIFT = @"gift";

NSString * const BRANCH_INIT_KEY_CHANNEL = @"~channel";
NSString * const BRANCH_INIT_KEY_FEATURE = @"~feature";
NSString * const BRANCH_INIT_KEY_TAGS = @"~tags";
NSString * const BRANCH_INIT_KEY_CAMPAIGN = @"~campaign";
NSString * const BRANCH_INIT_KEY_STAGE = @"~stage";
NSString * const BRANCH_INIT_KEY_CREATION_SOURCE = @"~creation_source";
NSString * const BRANCH_INIT_KEY_REFERRER = @"+referrer";
NSString * const BRANCH_INIT_KEY_PHONE_NUMBER = @"+phone_number";
NSString * const BRANCH_INIT_KEY_IS_FIRST_SESSION = @"+is_first_session";
NSString * const BRANCH_INIT_KEY_CLICKED_BRANCH_LINK = @"+clicked_branch_link";
static NSString * const BRANCH_PUSH_NOTIFICATION_PAYLOAD_KEY = @"branch";

NSString * const BNCCanonicalIdList = @"$canonical_identifier_list";
NSString * const BNCPurchaseAmount = @"$amount";
NSString * const BNCPurchaseCurrency = @"$currency";
NSString * const BNCRegisterViewEvent = @"View";
NSString * const BNCAddToWishlistEvent = @"Add to Wishlist";
NSString * const BNCAddToCartEvent = @"Add to Cart";
NSString * const BNCPurchaseInitiatedEvent = @"Purchase Started";
NSString * const BNCPurchasedEvent = @"Purchased";
NSString * const BNCShareInitiatedEvent = @"Share Started";
NSString * const BNCShareCompletedEvent = @"Share Completed";

static NSString * const BNCLogLevelKey = @"io.branch.sdk.BNCLogLevel";
NSString * const BNCSpotlightFeature = @"spotlight";

#ifndef CSSearchableItemActivityIdentifier
#define CSSearchableItemActivityIdentifier @"kCSSearchableItemActivityIdentifier"
#endif

#pragma mark - Load Categories

void ForceCategoriesToLoad(void);
void ForceCategoriesToLoad(void) {
    BNCForceNSErrorCategoryToLoad();
    BNCForceNSStringCategoryToLoad();
    BNCForceNSMutableDictionaryCategoryToLoad();
    BNCForceBranchValidatorCategoryToLoad();
    BNCForceUIViewControllerCategoryToLoad();
}

#pragma mark - BranchLink

@implementation BranchLink

+ (BranchLink*) linkWithUniversalObject:(BranchUniversalObject*)universalObject
                             properties:(BranchLinkProperties*)linkProperties {
    BranchLink *link = [[BranchLink alloc] init];
    link.universalObject = universalObject;
    link.linkProperties = linkProperties;
    return link;
}

@end

#pragma mark - Branch

typedef NS_ENUM(NSInteger, BNCInitStatus) {
    BNCInitStatusUninitialized = 0,
    BNCInitStatusInitializing,
    BNCInitStatusInitialized
};

@interface Branch() <BranchDeepLinkingControllerCompletionDelegate> {
    NSInteger _networkCount;
}

// This isolation queue protects branch initialization and ensures things are processed in order.
@property (nonatomic, strong, readwrite) dispatch_queue_t isolationQueue;

@property (strong, nonatomic) BNCServerInterface *serverInterface;
@property (strong, nonatomic) BNCServerRequestQueue *requestQueue;
@property (strong, nonatomic) dispatch_semaphore_t processing_sema;
@property (assign, nonatomic) NSInteger networkCount;
@property (assign, nonatomic) BNCInitStatus initializationStatus;
@property (assign, nonatomic) BOOL shouldAutomaticallyDeepLink;
@property (strong, nonatomic) BNCLinkCache *linkCache;
@property (strong, nonatomic) BNCPreferenceHelper *preferenceHelper;
@property (strong, nonatomic) NSMutableDictionary *deepLinkControllers;
@property (weak,   nonatomic) UIViewController *deepLinkPresentingController;
@property (strong, nonatomic) NSDictionary *deepLinkDebugParams;
@property (strong, nonatomic) NSMutableArray *allowedSchemeList;
@property (strong, nonatomic) BNCURLFilter *urlFilter;
@property (strong, nonatomic, readwrite) BNCURLFilter *userURLFilter;

@property (strong, nonatomic) BNCServerAPI *serverAPI;

#if !TARGET_OS_TV
@property (strong, nonatomic) BNCContentDiscoveryManager *contentDiscoveryManager;
#endif

@property (nonatomic, copy, nullable) void (^sceneSessionInitWithCallback)(BNCInitSessionResponse * _Nullable initResponse, NSError * _Nullable error);

// Support for deferred SDK initialization. Used to support slow plugin runtime startup.
// This is enabled by setting deferInitForPluginRuntime to true in branch.json
@property (nonatomic, assign, readwrite) BOOL deferInitForPluginRuntime;
@property (nonatomic, copy, nullable) void (^cachedInitBlock)(void);

@end

@implementation Branch

#pragma mark - Public methods

#pragma mark - GetInstance methods

// deprecated
+ (Branch *)getTestInstance {
    Branch.useTestBranchKey = YES;
    return [Branch getInstance];
}

+ (Branch *)getInstance {
    return [Branch getInstanceInternal:self.class.branchKey];
}

+ (Branch *)getInstance:(NSString *)branchKey {
    self.branchKey = branchKey;
    return [Branch getInstanceInternal:self.branchKey];
}

- (id)initWithInterface:(BNCServerInterface *)interface
                  queue:(BNCServerRequestQueue *)queue
                  cache:(BNCLinkCache *)cache
       preferenceHelper:(BNCPreferenceHelper *)preferenceHelper
                    key:(NSString *)key {

    self = [super init];
    if (!self) return self;

    // Initialize instance variables
    self.isolationQueue = dispatch_queue_create([@"branchIsolationQueue" UTF8String], DISPATCH_QUEUE_SERIAL);

    _serverInterface = interface;
    _serverInterface.preferenceHelper = preferenceHelper;
    _requestQueue = queue;
    _linkCache = cache;
    _preferenceHelper = preferenceHelper;
    _initializationStatus = BNCInitStatusUninitialized;
    _processing_sema = dispatch_semaphore_create(1);
    _networkCount = 0;
    _deepLinkControllers = [[NSMutableDictionary alloc] init];
    _allowedSchemeList = [[NSMutableArray alloc] init];
    _serverAPI = [BNCServerAPI sharedInstance];

    #if !TARGET_OS_TV
    _contentDiscoveryManager = [[BNCContentDiscoveryManager alloc] init];
    #endif

    self.class.branchKey = key;
    self.urlFilter = [BNCURLFilter new];
    [self.urlFilter useSavedPatternList];
    self.userURLFilter = nil;

    [BranchOpenRequest setWaitNeededForOpenResponseLock];

    // Register for notifications
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter
        addObserver:self
        selector:@selector(applicationWillResignActive)
        name:UIApplicationWillResignActiveNotification
        object:nil];

    [notificationCenter
        addObserver:self
        selector:@selector(applicationDidBecomeActive)
        name:UIApplicationDidBecomeActiveNotification
        object:nil];

    // queue up async data loading
    [self loadApplicationData];
    [self loadUserAgent];
    
    BranchJsonConfig *config = BranchJsonConfig.instance;
    self.deferInitForPluginRuntime = config.deferInitForPluginRuntime;
    
    if (config.enableLogging) {
        [self enableLogging];
    }
    
    if (config.checkPasteboardOnInstall) {
        [self checkPasteboardOnInstall];
    }

    return self;
}

static Class bnc_networkServiceClass = NULL;

+ (void)setNetworkServiceClass:(Class)networkServiceClass {
    @synchronized ([Branch class]) {
        if (bnc_networkServiceClass) {
            BNCLogError(@"The Branch network service class is already set. It can be set only once.");
            return;
        }
        if (![networkServiceClass conformsToProtocol:@protocol(BNCNetworkServiceProtocol)]) {
            BNCLogError([NSString stringWithFormat:@"Class '%@' doesn't conform to protocol '%@'.",
                NSStringFromClass(networkServiceClass),
                NSStringFromProtocol(@protocol(BNCNetworkServiceProtocol))]
            );
            return;
        }
        bnc_networkServiceClass = networkServiceClass;
    }
}

+ (Class)networkServiceClass {
    @synchronized ([Branch class]) {
        if (!bnc_networkServiceClass) bnc_networkServiceClass = [BNCNetworkService class];
        return bnc_networkServiceClass;
    }
}

#pragma mark - BrachActivityItemProvider methods
#if !TARGET_OS_TV

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:nil feature:nil stage:nil campaign:nil alias:nil delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:nil feature:feature stage:nil campaign:nil alias:nil delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature stage:(NSString *)stage {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:nil feature:feature stage:stage campaign:nil alias:nil delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature stage:(NSString *)stage tags:(NSArray *)tags {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:tags feature:feature stage:stage campaign:nil alias:nil delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature stage:(NSString *)stage campaign:(NSString *)campaign tags:(NSArray *)tags alias:(NSString *)alias {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:tags feature:feature stage:stage campaign:campaign alias:alias delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature stage:(NSString *)stage tags:(NSArray *)tags alias:(NSString *)alias {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:tags feature:feature stage:stage campaign:nil alias:alias delegate:nil];
}

+ (BranchActivityItemProvider *)getBranchActivityItemWithParams:(NSDictionary *)params feature:(NSString *)feature stage:(NSString *)stage tags:(NSArray *)tags alias:(NSString *)alias delegate:(id <BranchActivityItemProviderDelegate>)delegate {
    return [[BranchActivityItemProvider alloc] initWithParams:params tags:tags feature:feature stage:stage campaign:nil alias:alias delegate:delegate];
}

#endif

#pragma mark - Configuration methods

static BOOL bnc_useTestBranchKey = NO;
static NSString *bnc_branchKey = nil;

+ (void)resetBranchKey {
    bnc_branchKey = nil;
}

+ (void)setUseTestBranchKey:(BOOL)useTestKey {
    @synchronized (self) {
        if (bnc_branchKey && !!useTestKey != !!bnc_useTestBranchKey) {
            BNCLogError(@"Can't switch the Branch key once it's in use.");
            return;
        }
        bnc_useTestBranchKey = useTestKey;
    }
}

+ (BOOL)useTestBranchKey {
    @synchronized (self) {
        return bnc_useTestBranchKey;
    }
}

+ (void)setBranchKey:(NSString *)branchKey {
    NSError *error;
    [self setBranchKey:branchKey error:&error];

    if (error) {
        BNCLogError([NSString stringWithFormat:@"Branch init error: %@", error.localizedDescription]);
    }
}

+ (void)setBranchKey:(NSString*)branchKey error:(NSError **)error {
    @synchronized (self) {
        if (bnc_branchKey) {
            if (branchKey &&
                [branchKey isKindOfClass:[NSString class]] &&
                [branchKey isEqualToString:bnc_branchKey]) {
                return;
            }

            NSString *errorMessage = [NSString stringWithFormat:@"Branch key can only be set once."];
            *error = [NSError branchErrorWithCode:BNCInitError localizedMessage:errorMessage];
            return;
        }

        if (![branchKey isKindOfClass:[NSString class]]) {
            NSString *typeName = (branchKey) ? NSStringFromClass(branchKey.class) : @"<nil>";

            NSString *errorMessage = [NSString stringWithFormat:@"Invalid Branch key of type '%@'.", typeName];
            *error = [NSError branchErrorWithCode:BNCInitError localizedMessage:errorMessage];
            return;
        }

        if ([branchKey hasPrefix:@"key_test"]) {
            bnc_useTestBranchKey = YES;
            BNCLogWarning(
                @"You are using your test app's Branch Key. "
                 "Remember to change it to live Branch Key for production deployment."
            );

        } else if ([branchKey hasPrefix:@"key_live"]) {
            bnc_useTestBranchKey = NO;

        } else {
            NSString *errorMessage = [NSString stringWithFormat:@"Invalid Branch key format. Did you add your Branch key to your Info.plist? Passed key is '%@'.", branchKey];
            *error = [NSError branchErrorWithCode:BNCInitError localizedMessage:errorMessage];
            return;
        }

        bnc_branchKey = branchKey;
    }
}

+ (NSString *)branchKey {
    @synchronized (self) {
        if (bnc_branchKey) return bnc_branchKey;
        
        NSString *branchKey = nil;
        
        BranchJsonConfig *config = BranchJsonConfig.instance;
        BOOL usingTestInstance = bnc_useTestBranchKey || config.useTestInstance;
        branchKey = config.branchKey ?: usingTestInstance ? config.testKey : config.liveKey;
        [self setUseTestBranchKey:usingTestInstance];
        
        if (branchKey == nil) {
            NSDictionary *branchDictionary = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"branch_key"];
            if ([branchDictionary isKindOfClass:[NSString class]]) {
                branchKey = (NSString*) branchDictionary;
            } else
            if ([branchDictionary isKindOfClass:[NSDictionary class]]) {
                branchKey =
                    (self.useTestBranchKey) ? branchDictionary[@"test"] : branchDictionary[@"live"];
            }
        }

        self.branchKey = branchKey;
        if (!bnc_branchKey) {
            BNCLogError(@"Your Branch key is not set in your Info.plist file. See "
                "https://dev.branch.io/getting-started/sdk-integration-guide/guide/ios/#configure-xcode-project"
                " for configuration instructions.");
        }
        return bnc_branchKey;
    }
}

+ (BOOL)branchKeyIsSet {
    @synchronized (self) {
        return (bnc_branchKey.length) ? YES : NO;
    }
}

- (void)enableLogging {
    BNCLogSetDisplayLevel(BNCLogLevelDebug);
}

- (void)useEUEndpoints {
    [BNCServerAPI sharedInstance].useEUServers = YES;
}

- (void)setDebug {
    NSLog(@"Branch setDebug is deprecated and all functionality has been disabled. "
          "If you wish to enable logging, please invoke enableLogging. "
          "If you wish to simulate installs, please see add a Test Device "
          "(https://help.branch.io/using-branch/docs/adding-test-devices) "
          "then reset your test device's data "
          "(https://help.branch.io/using-branch/docs/adding-test-devices#section-resetting-your-test-device-data).");
}

- (void)validateSDKIntegration {
    [self validateSDKIntegrationCore];
}

- (void)resetUserSession {
    dispatch_async(self.isolationQueue, ^(){
        self.initializationStatus = BNCInitStatusUninitialized;
    });
}

- (BOOL)isUserIdentified {
    return self.preferenceHelper.userIdentity != nil;
}

- (void)disableAdNetworkCallouts:(BOOL)disableCallouts {
    self.preferenceHelper.disableAdNetworkCallouts = disableCallouts;
}

- (void)setNetworkTimeout:(NSTimeInterval)timeout {
    self.preferenceHelper.timeout = timeout;
}

- (void)setMaxRetries:(NSInteger)maxRetries {
    self.preferenceHelper.retryCount = maxRetries;
}

- (void)setRetryInterval:(NSTimeInterval)retryInterval {
    self.preferenceHelper.retryInterval = retryInterval;
}

- (void)disableCookieBasedMatching {
    // deprecated
}

- (void)accountForFacebookSDKPreventingAppLaunch {
    // deprecated
}

- (void)suppressWarningLogs {
    NSLog(@"suppressWarningLogs is deprecated and all functionality has been disabled. "
          "If you wish to turn off all logging, please invoke BNCLogSetDisplayLevel(BNCLogLevelNone).");
}

- (void)setRequestMetadataKey:(NSString *)key value:(NSObject *)value {
    [self.preferenceHelper setRequestMetadataKey:key value:value];
}

- (void)enableDelayedInit {
    // deprecated
}

- (void)disableDelayedInit {
    // deprecated
}

- (NSURL *)getUrlForOnboardingWithRedirectUrl:(NSString *)redirectUrl {
    // deprecated
    return nil;
}

- (void)resumeInit {
    // deprecated
}

- (void)setInstallRequestDelay:(NSInteger)installRequestDelay {
    // deprecated
}

+ (BOOL)trackingDisabled {
    @synchronized(self) {
        return [BNCPreferenceHelper sharedInstance].trackingDisabled;
    }
}

+ (void)setTrackingDisabled:(BOOL)disabled {
    @synchronized(self) {
        BOOL currentSetting = self.trackingDisabled;
        if (!!currentSetting == !!disabled)
            return;
        if (disabled) {
            [[BNCPartnerParameters shared] clearAllParameters];
            
            // Set the flag (which also clears the settings):
            [BNCPreferenceHelper sharedInstance].trackingDisabled = YES;
            Branch *branch = Branch.getInstance;
            [branch clearNetworkQueue];
            branch.initializationStatus = BNCInitStatusUninitialized;
            [branch.linkCache clear];
            // Release the lock in case it's locked:
            [BranchOpenRequest releaseOpenResponseLock];
        } else {
            // Set the flag:
            [BNCPreferenceHelper sharedInstance].trackingDisabled = NO;
            // Initialize a Branch session:
            [Branch.getInstance initUserSessionAndCallCallback:NO sceneIdentifier:nil];
        }
    }
}

+ (void)setReferrerGbraidValidityWindow:(NSTimeInterval)validityWindow{
    @synchronized(self) {
        [BNCPreferenceHelper sharedInstance].referringURLQueryParameters[BRANCH_REQUEST_KEY_REFERRER_GBRAID][BRANCH_URL_QUERY_PARAMETERS_VALIDITY_WINDOW_KEY] = @(validityWindow);
    }
}

#pragma mark - InitSession Permutation methods

- (void)initSessionWithLaunchOptions:(NSDictionary *)options {
    [self initSessionWithLaunchOptions:options
                          isReferrable:YES
         explicitlyRequestedReferrable:NO
        automaticallyDisplayController:NO
               registerDeepLinkHandler:nil];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options andRegisterDeepLinkHandler:(callbackWithParams)callback {
    [self initSessionWithLaunchOptions:options isReferrable:YES explicitlyRequestedReferrable:NO automaticallyDisplayController:NO registerDeepLinkHandler:callback];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options andRegisterDeepLinkHandlerUsingBranchUniversalObject:(callbackWithBranchUniversalObject)callback {
    [self initSessionWithLaunchOptions:options isReferrable:YES explicitlyRequestedReferrable:NO automaticallyDisplayController:NO registerDeepLinkHandlerUsingBranchUniversalObject:callback];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable {
    [self initSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:YES automaticallyDisplayController:NO registerDeepLinkHandler:nil];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options automaticallyDisplayDeepLinkController:(BOOL)automaticallyDisplayController {
    [self initSessionWithLaunchOptions:options isReferrable:YES explicitlyRequestedReferrable:NO automaticallyDisplayController:automaticallyDisplayController registerDeepLinkHandler:nil];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable andRegisterDeepLinkHandler:(callbackWithParams)callback {
    [self initSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:YES automaticallyDisplayController:NO registerDeepLinkHandler:callback];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options automaticallyDisplayDeepLinkController:(BOOL)automaticallyDisplayController deepLinkHandler:(callbackWithParams)callback {
    [self initSessionWithLaunchOptions:options isReferrable:YES explicitlyRequestedReferrable:NO automaticallyDisplayController:automaticallyDisplayController registerDeepLinkHandler:callback];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable automaticallyDisplayDeepLinkController:(BOOL)automaticallyDisplayController {
    [self initSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:YES automaticallyDisplayController:automaticallyDisplayController registerDeepLinkHandler:nil];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options automaticallyDisplayDeepLinkController:(BOOL)automaticallyDisplayController isReferrable:(BOOL)isReferrable deepLinkHandler:(callbackWithParams)callback {
    [self initSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:YES automaticallyDisplayController:automaticallyDisplayController registerDeepLinkHandler:callback];
}

#pragma mark - Actual Init Session

- (void)initSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable explicitlyRequestedReferrable:(BOOL)explicitlyRequestedReferrable automaticallyDisplayController:(BOOL)automaticallyDisplayController registerDeepLinkHandlerUsingBranchUniversalObject:(callbackWithBranchUniversalObject)callback {

    [self initSceneSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:explicitlyRequestedReferrable automaticallyDisplayController:automaticallyDisplayController
                    registerDeepLinkHandler:^(BNCInitSessionResponse * _Nullable initResponse, NSError * _Nullable error) {
        if (callback) {
            if (initResponse) {
                callback(initResponse.universalObject, initResponse.linkProperties, error);
            } else {
                callback([BranchUniversalObject new], [BranchLinkProperties new], error);
            }
        }
    }];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable explicitlyRequestedReferrable:(BOOL)explicitlyRequestedReferrable automaticallyDisplayController:(BOOL)automaticallyDisplayController registerDeepLinkHandler:(callbackWithParams)callback {

    [self initSceneSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:explicitlyRequestedReferrable automaticallyDisplayController:automaticallyDisplayController
                    registerDeepLinkHandler:^(BNCInitSessionResponse * _Nullable initResponse, NSError * _Nullable error) {
        if (callback) {
            if (initResponse) {
                callback(initResponse.params, error);
            } else {
                callback([NSDictionary new], error);
            }
        }
    }];
}

- (void)initSceneSessionWithLaunchOptions:(NSDictionary *)options isReferrable:(BOOL)isReferrable explicitlyRequestedReferrable:(BOOL)explicitlyRequestedReferrable automaticallyDisplayController:(BOOL)automaticallyDisplayController
                  registerDeepLinkHandler:(void (^)(BNCInitSessionResponse * _Nullable initResponse, NSError * _Nullable error))callback {
    [self deferInitBlock:^{
        self.sceneSessionInitWithCallback = callback;
        [self initSessionWithLaunchOptions:options isReferrable:isReferrable explicitlyRequestedReferrable:explicitlyRequestedReferrable automaticallyDisplayController:automaticallyDisplayController];
    }];
}

- (void)initSessionWithLaunchOptions:(NSDictionary *)options
                        isReferrable:(BOOL)isReferrable
       explicitlyRequestedReferrable:(BOOL)explicitlyRequestedReferrable
      automaticallyDisplayController:(BOOL)automaticallyDisplayController {

    [self.class addBranchSDKVersionToCrashlyticsReport];
    self.shouldAutomaticallyDeepLink = automaticallyDisplayController;

    // If the SDK is already initialized, this means that initSession was called after other lifecycle calls.
    if (self.initializationStatus == BNCInitStatusInitialized) {
        [self initUserSessionAndCallCallback:YES sceneIdentifier:nil];
        return;
    }

    // Save data from push notification on app launch
    #if !TARGET_OS_TV
    if ([options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey]) {
        id branchUrlFromPush = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey][BRANCH_PUSH_NOTIFICATION_PAYLOAD_KEY];
        if ([branchUrlFromPush isKindOfClass:[NSString class]]) {
            self.preferenceHelper.universalLinkUrl = branchUrlFromPush;
            self.preferenceHelper.referringURL = branchUrlFromPush;
        }
    }
    #endif

    // Handle case where there's no URI scheme or Universal Link.
    if (![options.allKeys containsObject:UIApplicationLaunchOptionsURLKey] && ![options.allKeys containsObject:UIApplicationLaunchOptionsUserActivityDictionaryKey]) {

        // queue up async attribution checks
        [self checkAttributionStatusAndInitialize];
    }
}

- (void)checkAttributionStatusAndInitialize {
    dispatch_async(self.isolationQueue, ^(){
        [self initUserSessionAndCallCallback:YES sceneIdentifier:nil];
    });
}

//these params will be added
- (void)setDeepLinkDebugMode:(NSDictionary *)debugParams {
    self.deepLinkDebugParams = debugParams;
}

- (void)setAllowedSchemes:(NSArray *)schemes {
    self.allowedSchemeList = [schemes mutableCopy];
}

- (void)addAllowedScheme:(NSString *)scheme {
    [self.allowedSchemeList addObject:scheme];
}

- (void)setUrlPatternsToIgnore:(NSArray<NSString*>*)urlsToIgnore {
    self.userURLFilter = [[BNCURLFilter alloc] init];
    [self.userURLFilter useCustomPatternList:urlsToIgnore];
}

// This is currently the same as handleDeeplink
- (BOOL)handleDeepLinkWithNewSession:(NSURL *)url {
    return [self handleDeepLink:url sceneIdentifier:nil];
}

- (BOOL)handleDeepLink:(NSURL *)url {
    return [self handleDeepLink:url sceneIdentifier:nil];
}

- (BOOL)handleDeepLink:(NSURL *)url sceneIdentifier:(NSString *)sceneIdentifier {

    // we've been resetting the session on all deeplinks for quite some time
    // this allows foreground links to callback
    self.initializationStatus = BNCInitStatusUninitialized;

    //Check the referring url/uri for query parameters and save them
    BNCReferringURLUtility *utility = [BNCReferringURLUtility new];
    [utility parseReferringURL:url];
    
    NSString *pattern = nil;
    pattern = [self.urlFilter patternMatchingURL:url];
    if (!pattern) {
        pattern = [self.userURLFilter patternMatchingURL:url];
    }
    if (pattern) {
        self.preferenceHelper.dropURLOpen = YES;
        self.preferenceHelper.externalIntentURI = pattern;
        self.preferenceHelper.referringURL = pattern;

        [self initUserSessionAndCallCallback:YES sceneIdentifier:sceneIdentifier];
        return NO;
    }

    NSString *scheme = [url scheme];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        return [self handleUniversalDeepLink_private:url.absoluteString sceneIdentifier:sceneIdentifier];
    } else {
        return [self handleSchemeDeepLink_private:url sceneIdentifier:sceneIdentifier];
    }
}

- (BOOL)handleSchemeDeepLink_private:(NSURL*)url sceneIdentifier:(NSString *)sceneIdentifier {
    BOOL handled = NO;
    self.preferenceHelper.referringURL = nil;
    if (url && ![url isEqual:[NSNull null]]) {

        NSString *urlScheme = [url scheme];

        // save the incoming url in the preferenceHelper in the externalIntentURI field
        if ([self.allowedSchemeList count]) {
            for (NSString *scheme in self.allowedSchemeList) {
                if (urlScheme && [scheme isEqualToString:urlScheme]) {
                    self.preferenceHelper.externalIntentURI = [url absoluteString];
                    self.preferenceHelper.referringURL = [url absoluteString];
                    break;
                }
            }
        } else {
            self.preferenceHelper.externalIntentURI = [url absoluteString];
            self.preferenceHelper.referringURL = [url absoluteString];
        }

        NSString *query = [url fragment];
        if (!query) {
            query = [url query];
        }

        NSDictionary *params = [BNCEncodingUtils decodeQueryStringToDictionary:query];
        if (params[@"link_click_id"]) {
            handled = YES;
            self.preferenceHelper.linkClickIdentifier = params[@"link_click_id"];
        }
    }
    [self initUserSessionAndCallCallback:YES sceneIdentifier:sceneIdentifier];
    return handled;
}


- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    return [self handleDeepLink:url sceneIdentifier:nil];
}

- (BOOL)sceneIdentifier:(NSString *)sceneIdentifier
                openURL:(NSURL *)url
      sourceApplication:(NSString *)sourceApplication
             annotation:(id)annotation {
    return [self  handleDeepLink:url sceneIdentifier:sceneIdentifier];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {

    NSString *source = options[UIApplicationOpenURLOptionsSourceApplicationKey];
    NSString *annotation = options[UIApplicationOpenURLOptionsAnnotationKey];
    return [self application:application openURL:url sourceApplication:source annotation:annotation];
}

- (BOOL)handleUniversalDeepLink_private:(NSString*)urlString sceneIdentifier:(NSString *)sceneIdentifier {
    if (urlString.length) {
        self.preferenceHelper.universalLinkUrl = urlString;
        self.preferenceHelper.referringURL = urlString;
    }

    [self initUserSessionAndCallCallback:YES sceneIdentifier:sceneIdentifier];

    return [Branch isBranchLink:urlString];
}

- (BOOL)continueUserActivity:(NSUserActivity *)userActivity {
    return [self continueUserActivity:userActivity sceneIdentifier:nil];
}

- (BOOL)continueUserActivity:(NSUserActivity *)userActivity sceneIdentifier:(NSString *)sceneIdentifier {
    BNCLogDebugSDK(@"continueUserActivity:");

    if (userActivity.referrerURL) {
        self.preferenceHelper.initialReferrer = userActivity.referrerURL.absoluteString;
    }
    
    // Check to see if a browser activity needs to be handled
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        return [self handleDeepLink:userActivity.webpageURL sceneIdentifier:sceneIdentifier];
    }

    NSString *spotlightIdentifier = nil;

    #if !TARGET_OS_TV
    // Check to see if a spotlight activity needs to be handled
    spotlightIdentifier = [self.contentDiscoveryManager spotlightIdentifierFromActivity:userActivity];
    NSURL *webURL = userActivity.webpageURL;

    if ([Branch isBranchLink:userActivity.userInfo[CSSearchableItemActivityIdentifier]]) {
        return [self handleDeepLink:[NSURL URLWithString:userActivity.userInfo[CSSearchableItemActivityIdentifier]] sceneIdentifier:sceneIdentifier];
    } else if (webURL != nil && [Branch isBranchLink:[webURL absoluteString]]) {
        return [self handleDeepLink:webURL sceneIdentifier:sceneIdentifier];
    } else if (spotlightIdentifier) {
        self.preferenceHelper.spotlightIdentifier = spotlightIdentifier;
    } else {
        NSString *nonBranchSpotlightIdentifier = [self.contentDiscoveryManager standardSpotlightIdentifierFromActivity:userActivity];
        if (nonBranchSpotlightIdentifier) {
            self.preferenceHelper.spotlightIdentifier = nonBranchSpotlightIdentifier;
        }
    }
    #endif

    [self initUserSessionAndCallCallback:YES sceneIdentifier:sceneIdentifier];

    return spotlightIdentifier != nil;
}

// checks if URL string looks like a branch link
+ (BOOL)isBranchLink:(NSString *)urlString {
    id branchUniversalLinkDomains = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"branch_universal_link_domains"];
    
    // check url list in bundle
    if ([branchUniversalLinkDomains isKindOfClass:[NSString class]] && [urlString containsString:branchUniversalLinkDomains]) {
        return YES;
    } else if ([branchUniversalLinkDomains isKindOfClass:[NSArray class]]) {
        for (id oneDomain in branchUniversalLinkDomains) {
            if ([oneDomain isKindOfClass:[NSString class]] && [urlString containsString:oneDomain]) {
                return YES;
            }
        }
    }

    // check default urls
    NSString *userActivityURL = urlString;
    NSArray *branchDomains = [NSArray arrayWithObjects:@"bnc.lt", @"app.link", @"test-app.link", nil];
    for (NSString* domain in branchDomains) {
        if ([userActivityURL containsString:domain]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Push Notification support

- (void)handlePushNotification:(NSDictionary *)userInfo {
    // look for a branch shortlink in the payload (shortlink because iOS7 only supports 256 bytes)
    NSString *urlStr = [userInfo objectForKey:BRANCH_PUSH_NOTIFICATION_PAYLOAD_KEY];
    if (urlStr.length) {
        // reusing this field, so as not to create yet another url slot on prefshelper
        self.preferenceHelper.universalLinkUrl = urlStr;
        self.preferenceHelper.referringURL = urlStr;
    }

    // If app is active, then close out the session and start a new one.
    // Else the URL will be handled by `applicationDidBecomeActive`.

    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if (urlStr && [[UIApplicationClass sharedApplication] applicationState] == UIApplicationStateActive) {
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url)  {
            [self handleDeepLink:url sceneIdentifier:nil];
        }
    }
}

#pragma mark - async data collection

- (void)loadUserAgent {
    #if !TARGET_OS_TV
    dispatch_async(self.isolationQueue, ^(){
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[BNCUserAgentCollector instance] loadUserAgentWithCompletion:^(NSString * _Nullable userAgent) {
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    });
    #endif
}

- (void)loadApplicationData {
    dispatch_async(self.isolationQueue, ^(){
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [BNCApplication loadCurrentApplicationWithCompletion:^(BNCApplication *application) {
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    });
}

#pragma mark - Apple Search Ad Check

- (void)checkPasteboardOnInstall {
    [BNCPasteboard sharedInstance].checkOnInstall = YES;
}

- (BOOL)willShowPasteboardToast {
    if (!self.preferenceHelper.randomizedBundleToken &&
        [BNCPasteboard sharedInstance].checkOnInstall &&
        [BNCPasteboard sharedInstance].isUrlOnPasteboard) {
        return YES;
    }
    return NO;
}

- (void)setAppClipAppGroup:(NSString *)appGroup {
    [BNCAppGroupsData shared].appGroup = appGroup;
}

- (void)handleATTAuthorizationStatus:(NSUInteger)status {
    // limits impact if the client fails to check that status = notDetermined before calling
    if ([BNCPreferenceHelper sharedInstance].hasCalledHandleATTAuthorizationStatus) {
        return;
    } else {
        [BNCPreferenceHelper sharedInstance].hasCalledHandleATTAuthorizationStatus = YES;
    }
    
    BranchEvent *event;
    switch (status) {
        case 2:
            // denied
            event = [BranchEvent standardEvent:BranchStandardEventOptOut];
            break;
        case 3:
            // authorized
            event = [BranchEvent standardEvent:BranchStandardEventOptIn];
            break;
        default:
            break;
    }
    if (event) {
        [event logEvent];
    }
}

- (void)setSKAdNetworkCalloutMaxTimeSinceInstall:(NSTimeInterval)maxTimeInterval {
    if (@available(iOS 16.1, macCatalyst 16.1, *)) {
        BNCLogDebug(@"This is no longer supported for iOS 16.1+ - SKAN4.0");
    } else {
        [BNCSKAdNetwork sharedInstance].maxTimeSinceInstall = maxTimeInterval;
    }
}

#pragma mark - Partner Parameters

- (void)clearPartnerParameters {
    [[BNCPartnerParameters shared] clearAllParameters];
}

- (void)addFacebookPartnerParameterWithName:(NSString *)name value:(NSString *)value {
    if (![Branch trackingDisabled]) {
        [[BNCPartnerParameters shared] addFacebookParameterWithName:name value:value];
    }
}

- (void)addSnapPartnerParameterWithName:(NSString *)name value:(NSString *)value {
    if (![Branch trackingDisabled]) {
        [[BNCPartnerParameters shared] addSnapParameterWithName:name value:value];
    }
}

#pragma mark - Pre-initialization support

- (void) dispatchToIsolationQueue:(dispatch_block_t) initBlock {
    dispatch_async(self.isolationQueue, initBlock);
}

#pragma mark - Deep Link Controller methods

- (void)registerDeepLinkController:(UIViewController <BranchDeepLinkingController> *)controller forKey:(NSString *)key {
    self.deepLinkControllers[key] = controller;
}

- (void)registerDeepLinkController:(UIViewController <BranchDeepLinkingController> *)controller forKey:(NSString *)key withPresentation:(BNCViewControllerPresentationOption)option{

    BNCDeepLinkViewControllerInstance* deepLinkModal = [[BNCDeepLinkViewControllerInstance alloc] init];

    deepLinkModal.viewController = controller;
    deepLinkModal.option         = option;

    self.deepLinkControllers[key] = deepLinkModal;
}


#pragma mark - Identity methods

- (void)setIdentity:(NSString *)userId {
    [self setIdentity:userId withCallback: nil];
}

- (void)setIdentity:(NSString *)userId withCallback:(callbackWithParams)callback {
    if (userId) {
        self.preferenceHelper.userIdentity = userId;
    }
    if (callback) {
        callback([self getFirstReferringParams], nil);
    }
}

- (void)logout {
    [self logoutWithCallback:nil];
}

- (void)logoutWithCallback:(callbackWithStatus)callback {
    if (self.initializationStatus == BNCInitStatusUninitialized) {
        NSError *error =
            (Branch.trackingDisabled)
            ? [NSError branchErrorWithCode:BNCTrackingDisabledError]
            : [NSError branchErrorWithCode:BNCInitError];
        BNCLogError(@"Branch is not initialized, cannot logout.");
        if (callback) {callback(NO, error);}
        return;
    }

    // Clear cached links
    self.linkCache = [[BNCLinkCache alloc] init];
    
    // Removed stored values
    self.preferenceHelper.userIdentity = nil;
    
    if (callback) {
        callback(YES, nil);
    }
}

- (void)sendServerRequest:(BNCServerRequest*)request {
    [self initSafetyCheck];
    dispatch_async(self.isolationQueue, ^(){
        [self.requestQueue enqueue:request];
        [self processNextQueueItem];
    });
}

// deprecated, use sendServerRequest
- (void)sendServerRequestWithoutSession:(BNCServerRequest*)request {
    [self sendServerRequest:request];
}

- (BranchUniversalObject *)getFirstReferringBranchUniversalObject {
    NSDictionary *params = [self getFirstReferringParams];
    if ([[params objectForKey:BRANCH_INIT_KEY_CLICKED_BRANCH_LINK] isEqual:@1]) {
        return [BranchUniversalObject objectWithDictionary:params];
    }
    return nil;
}

- (BranchLinkProperties *)getFirstReferringBranchLinkProperties {
    NSDictionary *params = [self getFirstReferringParams];
    if ([[params objectForKey:BRANCH_INIT_KEY_CLICKED_BRANCH_LINK] isEqual:@1]) {
        return [BranchLinkProperties getBranchLinkPropertiesFromDictionary:params];
    }
    return nil;
}

- (NSDictionary *)getFirstReferringParams {
    NSDictionary *origInstallParams = [BNCEncodingUtils decodeJsonStringToDictionary:self.preferenceHelper.installParams];

    if (self.deepLinkDebugParams) {
        NSMutableDictionary* debugInstallParams =
			[[BNCEncodingUtils decodeJsonStringToDictionary:self.preferenceHelper.sessionParams]
				mutableCopy];
        [debugInstallParams addEntriesFromDictionary:self.deepLinkDebugParams];
        return debugInstallParams;
    }
    return origInstallParams;
}

- (NSDictionary *)getLatestReferringParams {
    NSDictionary *origSessionParams = [BNCEncodingUtils decodeJsonStringToDictionary:self.preferenceHelper.sessionParams];

    if (self.deepLinkDebugParams) {
        NSMutableDictionary* debugSessionParams = [origSessionParams mutableCopy];
        [debugSessionParams addEntriesFromDictionary:self.deepLinkDebugParams];
        return debugSessionParams;
    }
    return origSessionParams;
}

- (NSDictionary *)getLatestReferringParamsSynchronous {
    [BranchOpenRequest waitForOpenResponseLock];
    NSDictionary *result = [self getLatestReferringParams];
    [BranchOpenRequest releaseOpenResponseLock];
    return result;
}

- (BranchUniversalObject *)getLatestReferringBranchUniversalObject {
    NSDictionary *params = [self getLatestReferringParams];
    if ([[params objectForKey:BRANCH_INIT_KEY_CLICKED_BRANCH_LINK] isEqual:@1]) {
        return [BranchUniversalObject objectWithDictionary:params];
    }
    return nil;
}

- (BranchLinkProperties *)getLatestReferringBranchLinkProperties {
    NSDictionary *params = [self getLatestReferringParams];
    if ([[params objectForKey:BRANCH_INIT_KEY_CLICKED_BRANCH_LINK] boolValue]) {
        return [BranchLinkProperties getBranchLinkPropertiesFromDictionary:params];
    }
    return nil;
}

#pragma mark - Query methods

- (void)lastAttributedTouchDataWithAttributionWindow:(NSInteger)window completion:(void(^) (BranchLastAttributedTouchData * _Nullable latd, NSError * _Nullable error))completion {
    [self initSafetyCheck];
    dispatch_async(self.isolationQueue, ^(){
        [BranchLastAttributedTouchData requestLastTouchAttributedData:self.serverInterface key:self.class.branchKey attributionWindow:window completion:completion];
    });
}

#pragma mark - ShortUrl methods

- (NSString *)getShortURL {
    return [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:nil andFeature:nil andStage:nil andCampaign:nil andParams:nil ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params {
    return [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:nil andFeature:nil andStage:nil andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage {
    return [self generateShortUrl:tags andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias {
    return [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias ignoreUAString:(NSString *)ignoreUAString {
    return [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:ignoreUAString forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCampaign:(NSString *)campaign andAlias:(NSString *)alias ignoreUAString:(NSString *)ignoreUAString forceLinkCreation:(BOOL)forceLinkCreation {
    return [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:campaign andParams:params ignoreUAString:ignoreUAString forceLinkCreation:forceLinkCreation];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andType:(BranchLinkType)type {
    return [self generateShortUrl:tags andAlias:nil andType:type andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andMatchDuration:(NSUInteger)duration {
    return [self generateShortUrl:tags andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage {
    return [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias {
    return [self generateShortUrl:nil andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andType:(BranchLinkType)type {
    return [self generateShortUrl:nil andAlias:nil andType:type andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andMatchDuration:(NSUInteger)duration {
    return [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature {
    return [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:nil andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortUrlWithParams:(NSDictionary *)params andTags:(NSArray *)tags andAlias:(NSString *)alias andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCampaign:(NSString *)campaign andMatchDuration:(NSUInteger)duration {
    return [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:campaign andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (NSString *)getShortUrlWithParams:(NSDictionary *)params andTags:(NSArray *)tags andAlias:(NSString *)alias andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andMatchDuration:(NSUInteger)duration {
    return [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params ignoreUAString:nil forceLinkCreation:YES];
}

- (void)getShortURLWithCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:nil andFeature:nil andStage:nil andCampaign:nil andParams:nil andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:nil andFeature:nil andStage:nil andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andType:(BranchLinkType)type andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:nil andType:type andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andTags:(NSArray *)tags andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andMatchDuration:(NSUInteger)duration andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andType:(BranchLinkType)type andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:type andMatchDuration:0 andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andMatchDuration:(NSUInteger)duration andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andFeature:(NSString *)feature andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:nil andAlias:nil andType:BranchLinkTypeUnlimitedUse andMatchDuration:0 andChannel:channel andFeature:feature andStage:nil andCampaign:nil andParams:params andCallback:callback];
}

- (void)getShortUrlWithParams:(NSDictionary *)params andTags:(NSArray *)tags andAlias:(NSString *)alias andMatchDuration:(NSUInteger)duration andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCampaign:campaign andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:campaign andParams:params andCallback:callback];
}

- (void)getShortUrlWithParams:(NSDictionary *)params andTags:(NSArray *)tags andAlias:(NSString *)alias andMatchDuration:(NSUInteger)duration andChannel:(NSString *)channel andFeature:(NSString *)feature andStage:(NSString *)stage andCallback:(callbackWithUrl)callback {
    [self generateShortUrl:tags andAlias:alias andType:BranchLinkTypeUnlimitedUse andMatchDuration:duration andChannel:channel andFeature:feature andStage:stage andCampaign:nil andParams:params andCallback:callback];
}

- (void)getSpotlightUrlWithParams:(NSDictionary *)params callback:(callbackWithParams)callback {
    [self initSafetyCheck];
    dispatch_async(self.isolationQueue, ^(){
        BranchSpotlightUrlRequest *req = [[BranchSpotlightUrlRequest alloc] initWithParams:params callback:callback];
        [self.requestQueue enqueue:req];
        [self processNextQueueItem];
    });
}

#pragma mark - LongUrl methods
- (NSString *)getLongURLWithParams:(NSDictionary *)params andChannel:(NSString *)channel andTags:(NSArray *)tags andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias {
    return [self generateLongURLWithParams:params andChannel:channel andTags:tags andFeature:feature andStage:stage andAlias:alias];
}

- (NSString *)getLongURLWithParams:(NSDictionary *)params {
    return [self generateLongURLWithParams:params andChannel:nil andTags:nil andFeature:nil andStage:nil andAlias:nil];
}

- (NSString *)getLongURLWithParams:(NSDictionary *)params andFeature:(NSString *)feature {
    return [self generateLongURLWithParams:params andChannel:nil andTags:nil andFeature:feature andStage:nil andAlias:nil];
}

- (NSString *)getLongURLWithParams:(NSDictionary *)params andFeature:(NSString *)feature andStage:(NSString *)stage {
    return [self generateLongURLWithParams:params andChannel:nil andTags:nil andFeature:feature andStage:stage andAlias:nil];
}

- (NSString *)getLongURLWithParams:(NSDictionary *)params andFeature:(NSString *)feature andStage:(NSString *)stage andTags:(NSArray *)tags {
    return [self generateLongURLWithParams:params andChannel:nil andTags:tags andFeature:feature andStage:stage andAlias:nil];
}

- (NSString *)getLongURLWithParams:(NSDictionary *)params andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias {
    return [self generateLongURLWithParams:params andChannel:nil andTags:nil andFeature:feature andStage:stage andAlias:alias];
}

- (NSString *)getLongAppLinkURLWithParams:(NSDictionary *)params andChannel:(nullable NSString *)channel andTags:(NSArray *)tags andFeature:(NSString *)feature andStage:(NSString *)stage andAlias:(NSString *)alias {
    return [self generateLongAppLinkURLWithParams:params andChannel:channel andTags:tags andFeature:feature andStage:stage andAlias:alias];
}

#pragma mark - Discoverable content methods
#if !TARGET_OS_TV

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description publiclyIndexable:(BOOL)publiclyIndexable callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams publiclyIndexable:(BOOL)publiclyIndexable {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable thumbnailUrl:thumbnailUrl userInfo:linkParams];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams callback:callback];
}
- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords expirationDate:(NSDate *)expirationDate callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams expirationDate:expirationDate callback:callback];
}
- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl canonicalId:canonicalId linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords expirationDate:(NSDate *)expirationDate callback:(callbackWithUrl)callback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description canonicalId:canonicalId publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams expirationDate:expirationDate callback:callback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords expirationDate:(NSDate *)expirationDate spotlightCallback:(callbackWithUrlAndSpotlightIdentifier)spotlightCallback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description canonicalId:nil publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams expirationDate:expirationDate callback:nil spotlightCallback:spotlightCallback];
}

- (void)createDiscoverableContentWithTitle:(NSString *)title description:(NSString *)description thumbnailUrl:(NSURL *)thumbnailUrl canonicalId:(NSString *)canonicalId linkParams:(NSDictionary *)linkParams type:(NSString *)type publiclyIndexable:(BOOL)publiclyIndexable keywords:(NSSet *)keywords expirationDate:(NSDate *)expirationDate spotlightCallback:(callbackWithUrlAndSpotlightIdentifier)spotlightCallback {
    [self.contentDiscoveryManager indexContentWithTitle:title description:description canonicalId:canonicalId publiclyIndexable:publiclyIndexable type:type thumbnailUrl:thumbnailUrl keywords:keywords userInfo:linkParams expirationDate:expirationDate callback:nil spotlightCallback:spotlightCallback];
}

- (void)indexOnSpotlightWithBranchUniversalObject:(BranchUniversalObject*)universalObject
                                   linkProperties:(BranchLinkProperties*)linkProperties
                                       completion:(void (^) (BranchUniversalObject *universalObject, NSString * url,NSError *error))completion {
    BNCSpotlightService *spotlightService = [[BNCSpotlightService alloc] init];

    if (!universalObject) {
        NSError* error = [NSError branchErrorWithCode:BNCInitError localizedMessage:@"Branch Universal Object is nil"];
        if (completion) completion(universalObject,nil,error);
        return;
    } else {
        [spotlightService indexWithBranchUniversalObject:universalObject
                                          linkProperties:linkProperties
                                                callback:^(BranchUniversalObject * _Nullable universalObject,
                                                           NSString * _Nullable url,
                                                           NSError * _Nullable error) {
                                              if (completion) completion(universalObject,url,error);
                                          }];
    }
}

/* Indexing of multiple BUOs
 * Content privately indexed irrestive of the value of contentIndexMode
 */


- (void)indexOnSpotlightUsingSearchableItems:(NSArray<BranchUniversalObject*>* )universalObjects
                                  completion:(void (^) (NSArray<BranchUniversalObject *>* universalObjects,
                                                        NSError* error))completion {

    BNCSpotlightService *spotlight = [[BNCSpotlightService alloc] init];
    [spotlight indexPrivatelyWithBranchUniversalObjects:universalObjects
                                             completion:^(NSArray<BranchUniversalObject *> * _Nullable universalObjects,
                                                          NSError * _Nullable error) {
                                                 if (completion) completion(universalObjects,error);
                                             }];
}

- (void)removeSearchableItemWithBranchUniversalObject:(BranchUniversalObject *)universalObject
                                             callback:(void (^_Nullable)(NSError * _Nullable error))completion {
    BNCSpotlightService *spotlight = [[BNCSpotlightService alloc] init];

    NSString *dynamicUrl = [universalObject getLongUrlWithChannel:nil
                                                          andTags:nil
                                                       andFeature:BNCSpotlightFeature
                                                         andStage:nil
                                                         andAlias:nil];
    [spotlight removeSearchableItemsWithIdentifier:dynamicUrl
                                          callback:^(NSError * _Nullable error) {
                                              if (completion) completion(error);
                                          }];
}


/* Only removes the indexing of BUOs indexed through CSSearchable item
 */
- (void)removeSearchableItemsWithBranchUniversalObjects:(NSArray<BranchUniversalObject*> *)universalObjects
                                               callback:(void (^)(NSError * error))completion {
    BNCSpotlightService *spotlight = [[BNCSpotlightService alloc] init];
    NSMutableArray<NSString *> *identifiers = [[NSMutableArray alloc] init];
    for (BranchUniversalObject* universalObject in universalObjects) {
        NSString *dynamicUrl = [universalObject getLongUrlWithChannel:nil
                                                              andTags:nil
                                                           andFeature:BNCSpotlightFeature
                                                             andStage:nil andAlias:nil];
        if (dynamicUrl) [identifiers addObject:dynamicUrl];
    }

    [spotlight removeSearchableItemsWithIdentifiers:identifiers
                                           callback:^(NSError * error) {
                                               if (completion)
                                                   completion(error);
                                           }];
}

/* Removes all content from spotlight indexed through CSSearchable item and has set the Domain identifier = "com.branch.io"
 */

- (void)removeAllPrivateContentFromSpotLightWithCallback:(void (^)(NSError * error))completion {
    BNCSpotlightService *spotlight = [[BNCSpotlightService alloc] init];
    [spotlight removeAllBranchSearchableItemsWithCallback:^(NSError * _Nullable error) {
        completion(error);
    }];
}
#endif

#if !TARGET_OS_TV
#pragma mark - UIPasteControl Support methods

- (void)passPasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders {
    
   // 1. Extract URL from NSItemProvider arrary
    for (NSItemProvider* item in itemProviders){
        if ( [item hasItemConformingToTypeIdentifier: UTTypeURL.identifier] ) {
            // 2. Check if URL is branch URL and if yes -> store it.
            [item loadItemForTypeIdentifier:UTTypeURL.identifier options:NULL completionHandler:^(NSURL *url, NSError * _Null_unspecified error) {
                if (error) {
                    BNCLogError([NSString stringWithFormat:@"%@", error]);
                }
                else if ([Branch isBranchLink:url.absoluteString]) {
                    [self.preferenceHelper setLocalUrl:[url absoluteString]];
                    // 3. Send Open Event
                    [[Branch getInstance] handleDeepLink:url];
                }
            }];
        }
    }
}
#endif

#pragma mark - Private methods

+ (Branch *)getInstanceInternal:(NSString *)key {

    static Branch *branch = nil;
    @synchronized (self) {
        static dispatch_once_t onceToken = 0;
        dispatch_once(&onceToken, ^{
            BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];

            // If there was stored key and it isn't the same as the currently used (or doesn't exist), we need to clean up
            // Note: Link Click Identifier is not cleared because of the potential for that to mess up a deep link
            if (preferenceHelper.lastRunBranchKey && ![key isEqualToString:preferenceHelper.lastRunBranchKey]) {
                BNCLogWarning(@"The Branch Key has changed, clearing relevant items.");

                preferenceHelper.appVersion = nil;
                preferenceHelper.randomizedDeviceToken = nil;
                preferenceHelper.sessionID = nil;
                preferenceHelper.randomizedBundleToken = nil;
                preferenceHelper.userUrl = nil;
                preferenceHelper.installParams = nil;
                preferenceHelper.sessionParams = nil;

                [[BNCServerRequestQueue getInstance] clearQueue];
            }

            if(!preferenceHelper.firstAppLaunchTime){
                preferenceHelper.firstAppLaunchTime = [NSDate date];
            }
            
            preferenceHelper.lastRunBranchKey = key;
            branch =
                [[Branch alloc] initWithInterface:[[BNCServerInterface alloc] init]
                    queue:[BNCServerRequestQueue getInstance]
                    cache:[[BNCLinkCache alloc] init]
                    preferenceHelper:preferenceHelper
                    key:key];
        });
        return branch;
    }
}


#pragma mark - URL Generation methods

- (void)generateShortUrl:(NSArray *)tags
                andAlias:(NSString *)alias
                 andType:(BranchLinkType)type
        andMatchDuration:(NSUInteger)duration
              andChannel:(NSString *)channel
              andFeature:(NSString *)feature
                andStage:(NSString *)stage
             andCampaign:campaign andParams:(NSDictionary *)params
             andCallback:(callbackWithUrl)callback {

    [self initSafetyCheck];
    dispatch_async(self.isolationQueue, ^(){
        BNCLinkData *linkData = [self prepareLinkDataFor:tags
                                                andAlias:alias
                                                 andType:type
                                        andMatchDuration:duration
                                              andChannel:channel
                                              andFeature:feature
                                                andStage:stage
                                             andCampaign:campaign
                                               andParams:params
                                          ignoreUAString:nil];

        if ([self.linkCache objectForKey:linkData]) {
            if (callback) {
                // callback on main, this is generally what the client expects and maintains our previous behavior
                dispatch_async(dispatch_get_main_queue(), ^ {
                    callback([self.linkCache objectForKey:linkData], nil);
                });
            }
            return;
        }

        BranchShortUrlRequest *req = [[BranchShortUrlRequest alloc] initWithTags:tags
                                                                           alias:alias
                                                                            type:type
                                                                   matchDuration:duration
                                                                         channel:channel
                                                                         feature:feature
                                                                           stage:stage
                                                                        campaign:campaign
                                                                          params:params
                                                                        linkData:linkData
                                                                       linkCache:self.linkCache
                                                                        callback:callback];
        [self.requestQueue enqueue:req];
        [self processNextQueueItem];
    });
}

- (NSString *)generateShortUrl:(NSArray *)tags
                      andAlias:(NSString *)alias
                       andType:(BranchLinkType)type
              andMatchDuration:(NSUInteger)duration
                    andChannel:(NSString *)channel
                    andFeature:(NSString *)feature
                      andStage:(NSString *)stage
                   andCampaign:(NSString *)campaign
                     andParams:(NSDictionary *)params
                ignoreUAString:(NSString *)ignoreUAString
             forceLinkCreation:(BOOL)forceLinkCreation {
    
    NSString *shortURL = nil;
    
    BNCLinkData *linkData =
    [self prepareLinkDataFor:tags
                    andAlias:alias
                     andType:type
            andMatchDuration:duration
                  andChannel:channel
                  andFeature:feature
                    andStage:stage
                 andCampaign:campaign
                   andParams:params
              ignoreUAString:ignoreUAString];
    
    // If an ignore UA string is present, we always get a new url.
    // Otherwise, if we've already seen this request, use the cached version.
    if (!ignoreUAString && [self.linkCache objectForKey:linkData]) {
        shortURL = [self.linkCache objectForKey:linkData];
    } else {
        BranchShortUrlSyncRequest *req =
        [[BranchShortUrlSyncRequest alloc]
         initWithTags:tags
         alias:alias
         type:type
         matchDuration:duration
         channel:channel
         feature:feature
         stage:stage
         campaign:campaign
         params:params
         linkData:linkData
         linkCache:self.linkCache];
        
        BNCLogDebug(@"Creating a custom URL synchronously.");
        BNCServerResponse *serverResponse = [req makeRequest:self.serverInterface key:self.class.branchKey];
        shortURL = [req processResponse:serverResponse];
        
        // cache the link
        if (shortURL) {
            [self.linkCache setObject:shortURL forKey:linkData];
        }
    }
    
    return shortURL;
}

- (NSString *)generateLongURLWithParams:(NSDictionary *)params
                             andChannel:(NSString *)channel
                                andTags:(NSArray *)tags
                             andFeature:(NSString *)feature
                               andStage:(NSString *)stage
                               andAlias:(NSString *)alias {

    NSString *baseLongUrl = [NSString stringWithFormat:@"%@/a/%@", BNC_LINK_URL, self.class.branchKey];

    return [self longUrlWithBaseUrl:baseLongUrl params:params tags:tags feature:feature
        channel:nil stage:stage alias:alias duration:0 type:BranchLinkTypeUnlimitedUse];
}

- (NSString *)generateLongAppLinkURLWithParams:(NSDictionary *)params
                                    andChannel:(NSString *)channel
                                       andTags:(NSArray *)tags
                                    andFeature:(NSString *)feature
                                      andStage:(NSString *)stage
                                      andAlias:(NSString *)alias {
    
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    NSString *baseUrl;
    
    if (preferenceHelper.userUrl) {
        NSString *fullUserUrl = [preferenceHelper sanitizedMutableBaseURL:preferenceHelper.userUrl];
        baseUrl = [fullUserUrl componentsSeparatedByString:@"?"].firstObject;
    } else {
        baseUrl = [[NSMutableString alloc] initWithFormat:@"%@/a/%@?", BNC_LINK_URL, self.class.branchKey];
    }
    
    return [self longUrlWithBaseUrl:baseUrl params:params tags:tags feature:feature
        channel:nil stage:stage alias:alias duration:0 type:BranchLinkTypeUnlimitedUse];
}

- (NSString *)longUrlWithBaseUrl:(NSString *)baseUrl
                          params:(NSDictionary *)params
                            tags:(NSArray *)tags
                         feature:(NSString *)feature
                         channel:(NSString *)channel
                           stage:(NSString *)stage
                           alias:(NSString *)alias
                        duration:(NSUInteger)duration
                            type:(BranchLinkType)type {

    NSMutableString *longUrl = [self.preferenceHelper sanitizedMutableBaseURL:baseUrl];
    for (NSString *tag in tags) {
        [longUrl appendFormat:@"tags=%@&", [BNCEncodingUtils stringByPercentEncodingStringForQuery:tag]];
    }

    if ([alias length]) {
        [longUrl appendFormat:@"alias=%@&", [BNCEncodingUtils stringByPercentEncodingStringForQuery:alias]];
    }

    if ([channel length]) {
        [longUrl appendFormat:@"channel=%@&", [BNCEncodingUtils stringByPercentEncodingStringForQuery:channel]];
    }

    if ([feature length]) {
        [longUrl appendFormat:@"feature=%@&", [BNCEncodingUtils stringByPercentEncodingStringForQuery:feature]];
    }

    if ([stage length]) {
        [longUrl appendFormat:@"stage=%@&", [BNCEncodingUtils stringByPercentEncodingStringForQuery:stage]];
    }
    if (type) {
        [longUrl appendFormat:@"type=%ld&", (long)type];
    }
    if (duration) {
        [longUrl appendFormat:@"matchDuration=%ld&", (long)duration];
    }

    NSData *jsonData = [BNCEncodingUtils encodeDictionaryToJsonData:params];
    NSString *base64EncodedParams = [BNCEncodingUtils base64EncodeData:jsonData];
    [longUrl appendFormat:@"source=ios&data=%@", base64EncodedParams];

    return longUrl;
}

- (BNCLinkData *)prepareLinkDataFor:(NSArray *)tags
                           andAlias:(NSString *)alias
                            andType:(BranchLinkType)type
                   andMatchDuration:(NSUInteger)duration
                         andChannel:(NSString *)channel
                         andFeature:(NSString *)feature
                           andStage:(NSString *)stage
                        andCampaign:(NSString *)campaign
                          andParams:(NSDictionary *)params
                     ignoreUAString:(NSString *)ignoreUAString {

    BNCLinkData *post = [[BNCLinkData alloc] init];

    [post setupType:type];
    [post setupTags:tags];
    [post setupChannel:channel];
    [post setupFeature:feature];
    [post setupStage:stage];
    [post setupCampaign:campaign];
    [post setupAlias:alias];
    [post setupMatchDuration:duration];
    [post setupIgnoreUAString:ignoreUAString];
    [post setupParams:params];

    return post;
}

#pragma mark - BranchUniversalObject methods

- (void)registerViewWithParams:(NSDictionary *)params andCallback:(callbackWithParams)callback {
    [self initSafetyCheck];
    dispatch_async(self.isolationQueue, ^(){
        BranchUniversalObject *buo = [[BranchUniversalObject alloc] init];
        buo.contentMetadata.customMetadata = (id) params;
        [[BranchEvent standardEvent:BranchStandardEventViewItem withContentItem:buo] logEvent];
        if (callback) {
            // callback on main, this is generally what the client expects and maintains our previous behavior
            dispatch_async(dispatch_get_main_queue(), ^ {
                callback(@{}, nil);
            });
        }
    });
}

#pragma mark - Application State Change methods

- (void)applicationDidBecomeActive {
    if (!Branch.trackingDisabled &&
        self.initializationStatus != BNCInitStatusInitialized &&
        ![self.requestQueue containsInstallOrOpen]) {
        [self initUserSessionAndCallCallback:YES sceneIdentifier:nil];
    }
}

- (void)applicationWillResignActive {
    if (!Branch.trackingDisabled) {
        self.initializationStatus = BNCInitStatusUninitialized;
        [self.requestQueue persistImmediately];
        [BranchOpenRequest setWaitNeededForOpenResponseLock];
        BNCLogDebugSDK(@"Application resigned active.");
    }
}

#pragma mark - Queue management

- (NSInteger) networkCount {
    @synchronized (self) {
        return _networkCount;
    }
}

- (void)setNetworkCount:(NSInteger)networkCount {
    @synchronized (self) {
        _networkCount = networkCount;
    }
}

- (void)insertRequestAtFront:(BNCServerRequest *)req {
    if (self.networkCount == 0) {
        [self.requestQueue insert:req at:0];
    }
    else {
        [self.requestQueue insert:req at:1];
    }
}

static inline void BNCPerformBlockOnMainThreadSync(dispatch_block_t block) {
    if (block) {
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_sync(dispatch_get_main_queue(), block);
        }
    }
}

//static inline void BNCPerformBlockOnMainThreadAsync(dispatch_block_t block) {
//    dispatch_async(dispatch_get_main_queue(), block);
//}

- (void) processRequest:(BNCServerRequest*)req
               response:(BNCServerResponse*)response
                  error:(NSError*)error {

    // If the request was successful, or was a bad user request, continue processing.
    if (!error ||
        error.code == BNCTrackingDisabledError ||
        error.code == BNCBadRequestError ||
        error.code == BNCDuplicateResourceError) {

        BNCPerformBlockOnMainThreadSync(^{
            [req processResponse:response error:error];
            if ([req isKindOfClass:[BranchEventRequest class]]) {
                [[BNCCallbackMap shared] callCompletionForRequest:req withSuccessStatus:(error == nil) error:error];
            }
        });

        [self.requestQueue dequeue];
        self.networkCount = 0;
        [self processNextQueueItem];
    }
    // On network problems, or Branch down, call the other callbacks and stop processing.
    else {
        BNCLogDebugSDK(@"Network error: failing queued requests.");

        // First, gather all the requests to fail
        NSMutableArray *requestsToFail = [[NSMutableArray alloc] init];
        for (int i = 0; i < self.requestQueue.queueDepth; i++) {
            BNCServerRequest *request = [self.requestQueue peekAt:i];
            if (request) {
                [requestsToFail addObject:request];
            }
        }

        // Next, remove all the requests that should not be replayed. Note, we do this before
        // calling callbacks, in case any of the callbacks try to kick off another request, which
        // could potentially start another request (and call these callbacks again)
        for (BNCServerRequest *request in requestsToFail) {
            if (Branch.trackingDisabled || ![self isReplayableRequest:request]) {
                [self.requestQueue remove:request];
            }
        }

        // Then, set the network count to zero, indicating that requests can be started again
        self.networkCount = 0;

        // Finally, call all the requests callbacks with the error
        for (BNCServerRequest *request in requestsToFail) {
            BNCPerformBlockOnMainThreadSync(^ {
                [request processResponse:nil error:error];

                // BranchEventRequests can have callbacks directly tied to them.
                if ([request isKindOfClass:[BranchEventRequest class]]) {
                    NSError *error = [NSError branchErrorWithCode:BNCGeneralError localizedMessage:@"Cancelling queued network requests due to a previous network error."];
                    [[BNCCallbackMap shared] callCompletionForRequest:req withSuccessStatus:NO error:error];
                }
            });
        }
    }
}

- (BOOL)isReplayableRequest:(BNCServerRequest *)request {

    // These request types
    NSSet<Class> *replayableRequests = [[NSSet alloc] initWithArray:@[
        BranchEventRequest.class
    ]];

    if ([replayableRequests containsObject:request.class]) {

        // Check if the client registered a callback for this request.
        // This indicates the client will handle retry themselves, so fail it.
        if ([[BNCCallbackMap shared] containsRequest:request]) {
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}

- (void)processNextQueueItem {
    dispatch_semaphore_wait(self.processing_sema, DISPATCH_TIME_FOREVER);

    if (self.networkCount == 0 &&
        self.requestQueue.queueDepth > 0) {

        self.networkCount = 1;
        dispatch_semaphore_signal(self.processing_sema);
        BNCServerRequest *req = [self.requestQueue peek];

        if (req) {

            // If tracking is disabled, then do not check for install event.  It won't exist.
            if (!Branch.trackingDisabled) {
                if (![req isKindOfClass:[BranchInstallRequest class]] && !self.preferenceHelper.randomizedBundleToken) {
                    BNCLogError(@"User session has not been initialized!");
                    BNCPerformBlockOnMainThreadSync(^{
                        [req processResponse:nil error:[NSError branchErrorWithCode:BNCInitError]];
                    });
                    return;

                } else if (![req isKindOfClass:[BranchOpenRequest class]] &&
                    (!self.preferenceHelper.randomizedDeviceToken || !self.preferenceHelper.sessionID)) {
                    BNCLogError(@"Missing session items!");
                    BNCPerformBlockOnMainThreadSync(^{
                        [req processResponse:nil error:[NSError branchErrorWithCode:BNCInitError]];
                    });
                    return;
                }
            }

            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_async(queue, ^ {
                [req makeRequest:self.serverInterface key:self.class.branchKey callback:
                    ^(BNCServerResponse* response, NSError* error) {
                        [self processRequest:req response:response error:error];
                }];
            });
        }
    }
    else {
        dispatch_semaphore_signal(self.processing_sema);
    }
}

- (void)clearNetworkQueue {
    dispatch_semaphore_wait(self.processing_sema, DISPATCH_TIME_FOREVER);
    self.networkCount = 0;
    [[BNCServerRequestQueue getInstance] clearQueue];
    dispatch_semaphore_signal(self.processing_sema);
}

#pragma mark - Session Initialization

// Defers block until notifyNativeToInit is called.
- (BOOL)deferInitBlock:(void (^)(void))block {
    BOOL deferred = NO;
    @synchronized (self) {
        if (self.deferInitForPluginRuntime) {
            self.cachedInitBlock = block;
            deferred = YES;
        }
    }
    
    if (!deferred && block) {
        block();
    }
    return deferred;
}

// Releases deferred init block
- (void)notifyNativeToInit {
    @synchronized (self) {
        self.deferInitForPluginRuntime = NO;
    }
    
    if (self.cachedInitBlock) {
        self.cachedInitBlock();
    }
    self.cachedInitBlock = nil;
}

// SDK-631 Workaround to maintain existing error handling behavior.
// Some methods require init before they are called.  Instead of returning an error, we try to fix the situation by calling init ourselves.
- (void)initSafetyCheck {
    if (self.initializationStatus == BNCInitStatusUninitialized) {
        BNCLogDebug(@"Branch avoided an error by preemptively initializing.");
        [self initUserSessionAndCallCallback:NO sceneIdentifier:nil];
    }
}

- (void)initUserSessionAndCallCallback:(BOOL)callCallback sceneIdentifier:(NSString *)sceneIdentifier {
    
    // ignore lifecycle calls while waiting for a plugin runtime.
    @synchronized (self) {
        if (self.deferInitForPluginRuntime) {
            //NSString *debug = [NSString stringWithFormat:@"Init is deferred, ignoring call: %@", NSThread.callStackSymbols];
            //BNCLogDebug(debug);
            return;
        }
    }
    
    dispatch_async(self.isolationQueue, ^(){
        NSString *urlstring = nil;
        if (self.preferenceHelper.universalLinkUrl.length) {
            urlstring = self.preferenceHelper.universalLinkUrl;
        } else if (self.preferenceHelper.externalIntentURI.length) {
            urlstring = self.preferenceHelper.externalIntentURI;
        }

        if (urlstring.length) {
            NSArray<BNCKeyValue*> *queryItems = [BNCEncodingUtils queryItems:[NSURL URLWithString:urlstring]];
            for (BNCKeyValue*item in queryItems) {
                if ([item.key isEqualToString:@"BranchLogLevel"]) {
                    BNCLogLevel logLevel = BNCLogLevelFromString(item.value);
                    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInteger:logLevel] forKey:BNCLogLevelKey];
                    BNCLogSetDisplayLevel(logLevel);
                    NSLog(@"[io.branch.sdk] BNCLogLevel set to %ld.", (long) logLevel);
                }
            }
        }

        // If the session is not yet initialized
        if (self.initializationStatus == BNCInitStatusUninitialized) {
            [self initializeSessionAndCallCallback:callCallback sceneIdentifier:sceneIdentifier];
        }
        // If the session was initialized, but callCallback was specified, do so.
        else if (callCallback && self.initializationStatus == BNCInitStatusInitialized) {

            // callback on main, this is generally what the client expects and maintains our previous behavior
            dispatch_async(dispatch_get_main_queue(), ^ {
                if (self.sceneSessionInitWithCallback) {
                    BNCInitSessionResponse *response = [BNCInitSessionResponse new];
                    response.params = [self getLatestReferringParams];
                    response.universalObject = [self getLatestReferringBranchUniversalObject];
                    response.linkProperties = [self getLatestReferringBranchLinkProperties];
                    response.sceneIdentifier = sceneIdentifier;
                    self.sceneSessionInitWithCallback(response, nil);
                }
            });
        }
    });
}

// only called from initUserSessionAndCallCallback!
- (void)initializeSessionAndCallCallback:(BOOL)callCallback sceneIdentifier:(NSString *)sceneIdentifier {
	Class clazz = [BranchInstallRequest class];
	if (self.preferenceHelper.randomizedBundleToken) {
		clazz = [BranchOpenRequest class];
	}

    callbackWithStatus initSessionCallback = ^(BOOL success, NSError *error) {
        // callback on main, this is generally what the client expects and maintains our previous behavior
		dispatch_async(dispatch_get_main_queue(), ^ {
			if (error) {
				[self handleInitFailure:error callCallback:callCallback sceneIdentifier:(NSString *)sceneIdentifier];
			} else {
				[self handleInitSuccessAndCallCallback:callCallback sceneIdentifier:(NSString *)sceneIdentifier];
			}
		});
    };

    // Notify everyone --

    NSURL *URL =
        (self.preferenceHelper.referringURL.length)
        ? [NSURL URLWithString:self.preferenceHelper.referringURL]
        : nil;

    if ([self.delegate respondsToSelector:@selector(branch:willStartSessionWithURL:)])
        [self.delegate branch:self willStartSessionWithURL:URL];

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[BranchURLKey] = URL;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BranchWillStartSessionNotification
        object:self
        userInfo:userInfo];

    // Fix the queue order and open --

	@synchronized (self) {
        [self removeInstallOrOpen];
		[BranchOpenRequest setWaitNeededForOpenResponseLock];
		BranchOpenRequest *req = [[clazz alloc] initWithCallback:initSessionCallback];
		[self insertRequestAtFront:req];
        self.initializationStatus = BNCInitStatusInitializing;
		[self processNextQueueItem];
	}
}

- (BOOL)removeInstallOrOpen {
	@synchronized (self) {
		if ([self.requestQueue removeInstallOrOpen]) {
			self.networkCount = 0;
            return YES;
        }
        return NO;
    }
}

- (void)handleInitSuccessAndCallCallback:(BOOL)callCallback sceneIdentifier:(NSString *)sceneIdentifier {

    self.initializationStatus = BNCInitStatusInitialized;
    NSDictionary *latestReferringParams = [self getLatestReferringParams];

    if ([latestReferringParams[@"_branch_validate"] isEqualToString:@"060514"]) {
        [self validateDeeplinkRouting:latestReferringParams];
    }
    else if (([latestReferringParams[@"bnc_validate"] isEqualToString:@"true"])) {
        NSString* referringLink = [self.class returnNonUniversalLink:latestReferringParams[@"~referring_link"] ];
        NSURLComponents *comp = [NSURLComponents componentsWithURL:[NSURL URLWithString:referringLink]
                                           resolvingAgainstBaseURL:NO];
        
        Class applicationClass = NSClassFromString(@"UIApplication");
        id<NSObject> sharedApplication = [applicationClass performSelector:@selector(sharedApplication)];
        if ([sharedApplication respondsToSelector:@selector(openURL:)])
            [sharedApplication performSelector:@selector(openURL:) withObject:comp.URL];
    }

    if (callCallback) {

        if (self.sceneSessionInitWithCallback) {
            BNCInitSessionResponse *response = [BNCInitSessionResponse new];
            response.params = [self getLatestReferringParams];
            response.universalObject = [self getLatestReferringBranchUniversalObject];
            response.linkProperties = [self getLatestReferringBranchLinkProperties];
            response.sceneIdentifier = sceneIdentifier;
            self.sceneSessionInitWithCallback(response, nil);
        }
    }
    [self sendOpenNotificationWithLinkParameters:latestReferringParams error:nil];

    [self.urlFilter updatePatternListFromServerWithCompletion:nil];

    if (self.shouldAutomaticallyDeepLink) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self automaticallyDeeplinkWithReferringParams:latestReferringParams];
        });
    }
}

// TODO: can we deprecate and remove this, it doesn't work well.
// UI code, must run on main
- (void)automaticallyDeeplinkWithReferringParams:(NSDictionary *)latestReferringParams {
    // Find any matched keys, then launch any controllers that match
    // TODO which one to launch if more than one match?
    NSMutableSet *keysInParams = [NSMutableSet setWithArray:[latestReferringParams allKeys]];
    NSSet *desiredKeysSet = [NSSet setWithArray:[self.deepLinkControllers allKeys]];
    [keysInParams intersectSet:desiredKeysSet];

    // If we find a matching key, configure and show the controller
    if ([keysInParams count]) {
        NSString *key = [[keysInParams allObjects] firstObject];
        UIViewController <BranchDeepLinkingController> *branchSharingController = self.deepLinkControllers[key];
        if ([branchSharingController respondsToSelector:@selector(configureControlWithData:)]) {
            [branchSharingController configureControlWithData:latestReferringParams];
        }
        else {
            BNCLogWarning([NSString stringWithFormat:@"The automatic deeplink view controller '%@' for key '%@' does not implement 'configureControlWithData:'.",
                branchSharingController, key]);
        }

        self.deepLinkPresentingController = [UIViewController bnc_currentViewController];
        if([self.deepLinkControllers[key] isKindOfClass:[BNCDeepLinkViewControllerInstance class]]) {
            BNCDeepLinkViewControllerInstance* deepLinkInstance = self.deepLinkControllers[key];
            UIViewController <BranchDeepLinkingController> *branchSharingController = deepLinkInstance.viewController;

            if ([branchSharingController respondsToSelector:@selector(configureControlWithData:)]) {
                [branchSharingController configureControlWithData:latestReferringParams];
            }
            else {
                BNCLogWarning(@"View controller does not implement configureControlWithData:");
            }
            branchSharingController.deepLinkingCompletionDelegate = self;
            switch (deepLinkInstance.option) {
                case BNCViewControllerOptionPresent:
                    [self presentSharingViewController:branchSharingController];
                    break;

                case BNCViewControllerOptionPush:

                    if ([self.deepLinkPresentingController isKindOfClass:[UINavigationController class]]) {

                        if ([[(UINavigationController*)self.deepLinkPresentingController viewControllers]
                              containsObject:branchSharingController]) {
                            [self removeViewControllerFromRootNavigationController:branchSharingController];
                            [(UINavigationController*)self.deepLinkPresentingController
                                 pushViewController:branchSharingController animated:false];
                        }
                        else {
                            [(UINavigationController*)self.deepLinkPresentingController
                                 pushViewController:branchSharingController animated:true];
                        }
                    }
                    else {
                        deepLinkInstance.option = BNCViewControllerOptionPresent;
                        [self presentSharingViewController:branchSharingController];
                    }

                    break;

                default:
                    if ([self.deepLinkPresentingController isKindOfClass:[UINavigationController class]]) {
                        if ([self.deepLinkPresentingController respondsToSelector:@selector(showViewController:sender:)]) {

                            if ([[(UINavigationController*)self.deepLinkPresentingController viewControllers]
                                   containsObject:branchSharingController]) {
                                [self removeViewControllerFromRootNavigationController:branchSharingController];
                            }

                            [self.deepLinkPresentingController showViewController:branchSharingController sender:self];
                        }
                        else {
                            deepLinkInstance.option = BNCViewControllerOptionPush;
                            [(UINavigationController*)self.deepLinkPresentingController
                                 pushViewController:branchSharingController animated:true];
                        }
                    }
                    else {
                        deepLinkInstance.option = BNCViewControllerOptionPresent;
                        [self presentSharingViewController:branchSharingController];
                    }
                    break;
            }
        }
        else {

            //Support for old API
            UIViewController <BranchDeepLinkingController> *branchSharingController = self.deepLinkControllers[key];
            if ([branchSharingController respondsToSelector:@selector(configureControlWithData:)]) {
                [branchSharingController configureControlWithData:latestReferringParams];
            }
            else {
                BNCLogWarning(@"View controller does not implement configureControlWithData:");
            }
            branchSharingController.deepLinkingCompletionDelegate = self;
            if ([self.deepLinkPresentingController presentedViewController]) {
                [self.deepLinkPresentingController dismissViewControllerAnimated:NO completion:^{
                    [self.deepLinkPresentingController presentViewController:branchSharingController animated:YES completion:NULL];
                }];
            }
            else {
                [self.deepLinkPresentingController presentViewController:branchSharingController animated:YES completion:NULL];
            }
        }
    }
}

- (void)sendOpenNotificationWithLinkParameters:(NSDictionary*)linkParameters
                                         error:(NSError*)error {

    NSURL *originalURL =
        (self.preferenceHelper.referringURL.length)
        ? [NSURL URLWithString:self.preferenceHelper.referringURL]
        : nil;
    BranchLinkProperties *linkProperties = nil;
    BranchUniversalObject *universalObject = nil;

    NSNumber *isBranchLink = linkParameters[BRANCH_INIT_KEY_CLICKED_BRANCH_LINK];
    if ([isBranchLink boolValue]) {
        universalObject = [BranchUniversalObject objectWithDictionary:linkParameters];
        linkProperties = [BranchLinkProperties getBranchLinkPropertiesFromDictionary:linkParameters];
    }

    if (error) {

        if ([self.delegate respondsToSelector:@selector(branch:failedToStartSessionWithURL:error:)])
            [self.delegate branch:self failedToStartSessionWithURL:originalURL error:error];

    } else {

        BranchLink *branchLink = nil;
        if (universalObject) {
            branchLink = [BranchLink linkWithUniversalObject:universalObject properties:linkProperties];
        }
        if ([self.delegate respondsToSelector:@selector(branch:didStartSessionWithURL:branchLink:)])
            [self.delegate branch:self didStartSessionWithURL:originalURL branchLink:branchLink];

    }

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[BranchErrorKey] = error;
    userInfo[BranchURLKey] = originalURL;
    userInfo[BranchUniversalObjectKey] = universalObject;
    userInfo[BranchLinkPropertiesKey] = linkProperties;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BranchDidStartSessionNotification
        object:self
        userInfo:userInfo];

    self.preferenceHelper.referringURL = nil;
}

- (void)removeViewControllerFromRootNavigationController:(UIViewController*)branchSharingController {

    NSMutableArray* viewControllers =
        [NSMutableArray arrayWithArray: [(UINavigationController*)self.deepLinkPresentingController viewControllers]];

    if ([viewControllers lastObject] == branchSharingController) {

        [(UINavigationController*)self.deepLinkPresentingController popViewControllerAnimated:YES];
    }else {
        [viewControllers removeObject:branchSharingController];
        ((UINavigationController*)self.deepLinkPresentingController).viewControllers = viewControllers;
    }
}

- (void)presentSharingViewController:(UIViewController <BranchDeepLinkingController> *)branchSharingController {
    if ([self.deepLinkPresentingController presentedViewController]) {
        [self.deepLinkPresentingController dismissViewControllerAnimated:NO completion:^{
            [self.deepLinkPresentingController presentViewController:branchSharingController animated:YES completion:NULL];
        }];
    }
    else {
        [self.deepLinkPresentingController presentViewController:branchSharingController animated:YES completion:NULL];
    }
}

- (void)handleInitFailure:(NSError *)error callCallback:(BOOL)callCallback sceneIdentifier:(NSString *)sceneIdentifier {
    self.initializationStatus = BNCInitStatusUninitialized;

    if (callCallback) {
        if (self.sceneSessionInitWithCallback) {
            BNCInitSessionResponse *response = [BNCInitSessionResponse new];
            response.error = error;
            response.params = [NSDictionary new];
            response.universalObject = [BranchUniversalObject new];
            response.linkProperties = [BranchLinkProperties new];
            response.sceneIdentifier = sceneIdentifier;
            self.sceneSessionInitWithCallback(response, error);
        }
    }

    [self sendOpenNotificationWithLinkParameters:@{} error:error];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)registerPluginName:(NSString *)name version:(NSString *)version {
    [[BNCDeviceInfo getInstance] registerPluginName:name version:version];
}

#pragma mark - BranchDeepLinkingControllerCompletionDelegate methods

- (void)deepLinkingControllerCompletedFrom:(UIViewController *)viewController {
    [self.deepLinkControllers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {

        if([obj isKindOfClass:[BNCDeepLinkViewControllerInstance class]]) {
            BNCDeepLinkViewControllerInstance* deepLinkInstance = (BNCDeepLinkViewControllerInstance*) obj;

            if (deepLinkInstance.viewController == viewController) {

                switch (deepLinkInstance.option) {
                    case BNCViewControllerOptionPresent:
                        [viewController dismissViewControllerAnimated:YES completion:nil];
                        break;

                    default:
                        [self removeViewControllerFromRootNavigationController:viewController];
                        break;
                }
            }

        } else {
            //Support for old API
            if ((UIViewController*)obj == viewController)
                [self.deepLinkPresentingController dismissViewControllerAnimated:YES completion:nil];
        }

    }];
}

#pragma mark - Crashlytics reporting enhancements

+ (void)logLowMemoryToCrashlytics {
    [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            BNCCrashlyticsWrapper *crashlytics = [BNCCrashlyticsWrapper wrapper];
            [crashlytics setCustomValue:@YES forKey:BRANCH_CRASHLYTICS_LOW_MEMORY_KEY];
        }
    ];
}

+ (void)addBranchSDKVersionToCrashlyticsReport {
    BNCCrashlyticsWrapper *crashlytics = [BNCCrashlyticsWrapper wrapper];
    [crashlytics setCustomValue:BNC_SDK_VERSION forKey:BRANCH_CRASHLYTICS_SDK_VERSION_KEY];
}

+ (void) clearAll {
    [[BNCServerRequestQueue getInstance] clearQueue];
    [BranchOpenRequest releaseOpenResponseLock];
    [BNCPreferenceHelper clearAll];
}

@end
