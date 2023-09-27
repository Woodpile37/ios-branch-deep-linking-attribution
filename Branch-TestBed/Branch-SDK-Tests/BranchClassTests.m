//
//  BranchClassTests.m
//  Branch-SDK-Tests
//
//  Created by Nipun Singh on 9/25/23.
//  Copyright © 2023 Branch, Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "Branch.h"
#import "BranchConstants.h"
#import "BNCPasteboard.h"
#import "BNCAppGroupsData.h"
#import "BNCPartnerParameters.h"

@interface BranchClassTests : XCTestCase
@property (nonatomic, strong) Branch *branch;
@end

@implementation BranchClassTests

- (void)setUp {
    [super setUp];
    self.branch = [Branch getInstance];
}

- (void)tearDown {
    self.branch = nil;
    [super tearDown];
}

- (void)testResetUserSession {
    [self.branch resetUserSession];
    //XCTAssertEqual([BNCPreferenceHelper sharedInstance]., BNCInitStatusUninitialized, @"Initialization status should be BNCInitStatusUninitialized");
}

- (void)testIsUserIdentified {
    [self.branch setIdentity: @"userId"];
    XCTAssertTrue([self.branch isUserIdentified], @"User should be identified");
}

- (void)testDisableAdNetworkCallouts {
    [self.branch disableAdNetworkCallouts:YES];
    XCTAssertTrue([BNCPreferenceHelper sharedInstance].disableAdNetworkCallouts, @"AdNetwork callouts should be disabled");
}

- (void)testSetNetworkTimeout {
    [self.branch setNetworkTimeout:5.0];
    XCTAssertEqual([BNCPreferenceHelper sharedInstance].timeout, 5.0, @"Network timeout should be set to 5.0");
}

- (void)testSetMaxRetries {
    [self.branch setMaxRetries:3];
    XCTAssertEqual([BNCPreferenceHelper sharedInstance].retryCount, 3, @"Max retries should be set to 3");
}

- (void)testSetRetryInterval {
    [self.branch setRetryInterval:2.0];
    XCTAssertEqual([BNCPreferenceHelper sharedInstance].retryInterval, 2.0, @"Retry interval should be set to 2.0");
}

- (void)testSetRequestMetadataKeyAndValue {
    [self.branch setRequestMetadataKey:@"key" value:@"value"];
    NSDictionary *metadata = [BNCPreferenceHelper sharedInstance].requestMetadataDictionary;
    XCTAssertEqualObjects(metadata[@"key"], @"value");
}

- (void)testSetTrackingDisabled {
    // Initial state
    XCTAssertFalse([BNCPreferenceHelper sharedInstance].trackingDisabled);

    // Set tracking to disabled
    [Branch setTrackingDisabled:YES];
    XCTAssertTrue([BNCPreferenceHelper sharedInstance].trackingDisabled);

    // Revert tracking to enabled
    [Branch setTrackingDisabled:NO];
    XCTAssertFalse([BNCPreferenceHelper sharedInstance].trackingDisabled);
}

//- (void)testSetReferrerGbraidValidityWindow {
//    // Initial state, should be nil or non-existing
//    XCTAssertNil([BNCPreferenceHelper sharedInstance].referringURLQueryParameters[BRANCH_REQUEST_KEY_REFERRER_GBRAID][BRANCH_URL_QUERY_PARAMETERS_VALIDITY_WINDOW_KEY]);
//
//    // Set validity window
//    NSTimeInterval validityWindow = 1592000.0;
//    [Branch setReferrerGbraidValidityWindow:validityWindow];
//    [NSThread sleepForTimeInterval:1.0];
//    NSLog(@"After setting 2: %@", [BNCPreferenceHelper sharedInstance].referringURLQueryParameters);
//
//    // Check if it's set correctly
//    XCTAssertEqual([BNCPreferenceHelper sharedInstance].referrerGBRAIDValidityWindow, validityWindow);
//}

- (void)testCheckPasteboardOnInstall {
    [self.branch checkPasteboardOnInstall];
    BOOL checkOnInstall = [BNCPasteboard sharedInstance].checkOnInstall;
    XCTAssertTrue(checkOnInstall);
}

- (void)testWillShowPasteboardToast_ShouldReturnYes {
    [BNCPreferenceHelper sharedInstance].randomizedBundleToken = nil;
    [BNCPasteboard sharedInstance].checkOnInstall = YES;
    UIPasteboard.generalPasteboard.URL = [NSURL URLWithString:@"https://example.com"];

    BOOL result = [self.branch willShowPasteboardToast];
    XCTAssertTrue(result);
}

- (void)testWillShowPasteboardToast_ShouldReturnNo {
    [BNCPreferenceHelper sharedInstance].randomizedBundleToken = @"some_token";
    [BNCPasteboard sharedInstance].checkOnInstall = NO;

    BOOL result = [self.branch willShowPasteboardToast];
    XCTAssertFalse(result);
}

- (void)testSetAppClipAppGroup {
    NSString *testAppGroup = @"testAppGroup";
    [self.branch setAppClipAppGroup:testAppGroup];
    NSString *actualAppGroup = [BNCAppGroupsData shared].appGroup;

    XCTAssertEqualObjects(testAppGroup, actualAppGroup);
}

- (void)testClearPartnerParameters {
    [self.branch addFacebookPartnerParameterWithName:@"ph" value:@"123456789"];
    [[BNCPartnerParameters shared] clearAllParameters];
       
    NSDictionary *result = [[BNCPartnerParameters shared] parameterJson];
    XCTAssertEqual([result count], 0, @"Parameters should be empty after calling clearAllParameters");
}

- (void)testAddFacebookParameterWithName_Value {
    [self.branch addFacebookPartnerParameterWithName:@"name" value:@"3D4F2BF07DC1BE38B20C653EE9A7E446158F84E525BBB98FEDF721CB5A40A346"];
    
    NSDictionary *result = [[BNCPartnerParameters shared] parameterJson][@"fb"];
    XCTAssertEqualObjects(result[@"name"], @"3D4F2BF07DC1BE38B20C653EE9A7E446158F84E525BBB98FEDF721CB5A40A346", @"Should add parameter for Facebook");
}

- (void)testAddSnapParameterWithName_Value {
    [self.branch addSnapPartnerParameterWithName:@"name" value:@"3D4F2BF07DC1BE38B20C653EE9A7E446158F84E525BBB98FEDF721CB5A40A346"];
    
    NSDictionary *result = [[BNCPartnerParameters shared] parameterJson][@"snap"];
    XCTAssertEqualObjects(result[@"name"], @"3D4F2BF07DC1BE38B20C653EE9A7E446158F84E525BBB98FEDF721CB5A40A346", @"Should add parameter for Snap");
}

- (void)testGetFirstReferringBranchUniversalObject_ClickedBranchLink {
    NSString *installParamsString = @"{\"$canonical_identifier\":\"content/12345\",\"$creation_timestamp\":1694557342247,\"$desktop_url\":\"https://example.com/home\",\"$og_description\":\"My Content Description\",\"$og_title\":\"My Content Title\",\"+click_timestamp\":1695749249,\"+clicked_branch_link\":1,\"+is_first_session\":1,\"+match_guaranteed\":1,\"custom\":\"data\",\"key1\":\"value1\",\"~campaign\":\"content 123 launch\",\"~channel\":\"facebook\",\"~creation_source\":3,\"~feature\":\"sharing\",\"~id\":1230269548213984984,\"~referring_link\":\"https://bnctestbed.app.link/uSPHktjO2Cb\"}";
    [[BNCPreferenceHelper sharedInstance] setInstallParams: installParamsString];

    BranchUniversalObject *result = [self.branch getFirstReferringBranchUniversalObject];\
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.title, @"My Content Title");
    XCTAssertEqualObjects(result.canonicalIdentifier, @"content/12345");
}

- (void)testGetFirstReferringBranchUniversalObject_NotClickedBranchLink {
    NSString *installParamsString = @"{\"+clicked_branch_link\":false,\"+is_first_session\":true}";
    [[BNCPreferenceHelper sharedInstance] setInstallParams: installParamsString];
        
    BranchUniversalObject *result = [self.branch getFirstReferringBranchUniversalObject];
    XCTAssertNil(result);
}

- (void)testGetFirstReferringBranchLinkProperties_ClickedBranchLink {
    NSString *installParamsString = @"{\"+clicked_branch_link\":1,\"+is_first_session\":1,\"~campaign\":\"content 123 launch\"}";
    [[BNCPreferenceHelper sharedInstance] setInstallParams:installParamsString];

    BranchLinkProperties *result = [self.branch getFirstReferringBranchLinkProperties];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.campaign, @"content 123 launch");
}

- (void)testGetFirstReferringBranchLinkProperties_NotClickedBranchLink {
    NSString *installParamsString = @"{\"+clicked_branch_link\":false,\"+is_first_session\":true}";
    [[BNCPreferenceHelper sharedInstance] setInstallParams:installParamsString];

    BranchLinkProperties *result = [self.branch getFirstReferringBranchLinkProperties];
    XCTAssertNil(result);
}

- (void)testGetFirstReferringParams {
    NSString *installParamsString = @"{\"+clicked_branch_link\":true,\"+is_first_session\":true}";
    [[BNCPreferenceHelper sharedInstance] setInstallParams:installParamsString];

    NSDictionary *result = [self.branch getFirstReferringParams];
    XCTAssertEqualObjects([result objectForKey:@"+clicked_branch_link"], @true);
}

- (void)testGetLatestReferringParams {
    NSString *sessionParamsString = @"{\"+clicked_branch_link\":true,\"+is_first_session\":false}";
    // Assume setSessionParams: exists or use a method to mock sessionParams
    [[BNCPreferenceHelper sharedInstance] setSessionParams:sessionParamsString];

    NSDictionary *result = [self.branch getLatestReferringParams];
    XCTAssertEqualObjects([result objectForKey:@"+clicked_branch_link"], @true);
}

- (void)testGetLatestReferringParamsSynchronous {
    NSString *sessionParamsString = @"{\"+clicked_branch_link\":true,\"+is_first_session\":false}";
    // Assume setSessionParams: exists or use a method to mock sessionParams
    [[BNCPreferenceHelper sharedInstance] setSessionParams:sessionParamsString];

    NSDictionary *result = [self.branch getLatestReferringParamsSynchronous];
    XCTAssertEqualObjects([result objectForKey:@"+clicked_branch_link"], @true);
}

- (void)testGetLatestReferringBranchUniversalObject_ClickedBranchLink {
    NSString *sessionParamsString = @"{\"+clicked_branch_link\":1,\"+is_first_session\":false,\"$og_title\":\"My Latest Content\"}";
    [[BNCPreferenceHelper sharedInstance] setSessionParams:sessionParamsString];

    BranchUniversalObject *result = [self.branch getLatestReferringBranchUniversalObject];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.title, @"My Latest Content");
}

- (void)testGetLatestReferringBranchLinkProperties_ClickedBranchLink {
    NSString *sessionParamsString = @"{\"+clicked_branch_link\":true,\"+is_first_session\":false,\"~campaign\":\"latest campaign\"}";
    [[BNCPreferenceHelper sharedInstance] setSessionParams:sessionParamsString];

    BranchLinkProperties *result = [self.branch getLatestReferringBranchLinkProperties];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result.campaign, @"latest campaign");
}

- (void)testGetShortURL {
   XCTestExpectation *expectation = [self expectationWithDescription:@"Fetching URL"];
      
   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
       NSString *shortURL = [self.branch getShortURL];
       
       XCTAssertNotNil(shortURL, @"URL should not be nil");
       XCTAssertTrue([shortURL hasPrefix:@"https://"], @"URL should start with 'https://'");
       
       [expectation fulfill];
   });

   [self waitForExpectationsWithTimeout:10 handler:^(NSError *error) {
       if (error) {
           NSLog(@"Timeout Error: %@", error);
       }
   }];
}

- (void)testGetShortURLWithParams {
   XCTestExpectation *expectation = [self expectationWithDescription:@"Fetching URL"];
   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
       NSDictionary *params = @{@"key": @"value"};
       NSArray *tags = @[@"tag1", @"tag2"];
       NSString *randomAlias = [[NSUUID UUID] UUIDString];
       [self.branch getShortUrlWithParams:params andTags:tags andAlias:randomAlias andMatchDuration:10 andChannel:@"channel1" andFeature:@"feature1" andStage:@"stage1" andCampaign:@"campaign1" andCallback:^(NSString * _Nullable url, NSError * _Nullable error) {
           
           NSString *expectedURL = [NSString stringWithFormat:@"https://bnctestbed.app.link/%@", randomAlias];
           XCTAssertEqualObjects(url, expectedURL, @"URL should match the expected format");

           [expectation fulfill];
       }];
   });

   [self waitForExpectationsWithTimeout:5 handler:^(NSError *error) {
       if (error) {
           NSLog(@"Timeout Error: %@", error);
       }
   }];
}

- (void)testGetLongURLWithParamsAndChannelAndTagsAndFeatureAndStageAndAlias {
    NSDictionary *params = @{@"key": @"value"};
    NSString *channel = @"channel1";
    NSArray *tags = @[@"tag1", @"tag2"];
    NSString *feature = @"feature1";
    NSString *stage = @"stage1";
    NSString *alias = @"alias1";
    
    NSString *generatedURL = [self.branch getLongURLWithParams:params andChannel:channel andTags:tags andFeature:feature andStage:stage andAlias:alias];
    NSString *expectedURL = @"https://bnctestbed.app.link?key=value&channel=channel1&tags=tag1,tag2&feature=feature1&stage=stage1&alias=alias1";
    
    XCTAssertEqualObjects(generatedURL, expectedURL, @"URL should match the expected format");
}

@end
