//
//  FBAudienceNetworkPaidLibrary.mm
//  Facebook Audience Network Paid Plugin
//
//  Copyright (c) 2015-2017 CoronaLabs Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <sys/utsname.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLuaIOS.h"
#import "CoronaLibrary.h"

#import "FBAudienceNetworkLibrary.h"
#import <FBAudienceNetwork/FBAudienceNetwork.h>

// some macros to make life easier, and code more readable
#define UTF8StringWithFormat(format, ...) [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]
#define MsgFormat(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]
#define UTF8IsEqual(utf8str1, utf8str2) (strcmp(utf8str1, utf8str2) == 0)

// ----------------------------------------------------------------------------
// Plugin Constants
// ----------------------------------------------------------------------------

#define PLUGIN_NAME        "plugin.fbAudienceNetwork"
#define PLUGIN_VERSION     "1.0.2"
#define PLUGIN_SDK_VERSION [FB_AD_SDK_VERSION UTF8String] // No API to get SDK version (yet)

static const char EVENT_NAME[]    = "adsRequest";
static const char PROVIDER_NAME[] = "fbAudienceNetwork";

// ad types
static const char TYPE_BANNER[]       = "banner";
static const char TYPE_INTERSTITIAL[] = "interstitial";
static const char TYPE_REWARDED[] = "rewardedVideo";

// valid ad types
static const NSArray *validAdTypes = @[
  @(TYPE_BANNER),
  @(TYPE_INTERSTITIAL),
  @(TYPE_REWARDED)
];

// banner sizes
static const char BANNER_320_50[]        = "BANNER_320_50";
static const char BANNER_HEIGHT_50[]     = "BANNER_HEIGHT_50";
static const char BANNER_HEIGHT_90[]     = "BANNER_HEIGHT_90";
static const char RECTANGLE_HEIGHT_250[] = "RECTANGLE_HEIGHT_250";

// banner alignment
static const char BANNER_ALIGN_TOP[]    = "top";
static const char BANNER_ALIGN_CENTER[] = "center";
static const char BANNER_ALIGN_BOTTOM[] = "bottom";

// valid ad types
static const NSArray *validBannerPositions = @[
  @(BANNER_ALIGN_TOP),
  @(BANNER_ALIGN_CENTER),
  @(BANNER_ALIGN_BOTTOM)
];

// event keys
static const char CORONA_EVENT_PLACEMENTID_KEY[] = "placementId";

// event phases
static NSString * const PHASE_INIT      = @"init";
static NSString * const PHASE_LOADED    = @"loaded";
static NSString * const PHASE_REFRESHED = @"refreshed";
static NSString * const PHASE_FAILED    = @"failed";
static NSString * const PHASE_CLOSED    = @"closed";
static NSString * const PHASE_CLICKED   = @"clicked";
static NSString * const PHASE_REWARD    = @"reward";

static NSString * const STATUS_FORMAT   = @"%@_status";

// response codes
static NSString * const RESPONSE_LOADFAILED = @"failed to load";

// message constants
static NSString * const ERROR_MSG   = @"ERROR: ";
static NSString * const WARNING_MSG = @"WARNING: ";

// saved objects (apiKey, ad state, etc)
static NSMutableDictionary *fbObjects;

// ad dictionary keys
static NSString * const Y_RATIO_KEY  = @"yRatio";    // used to calculate Corona -> UIKit coordinate ratio
static NSString * const SDKREADY_KEY = @"sdkReady";  // true when corona's placement id's could be retrieved

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

@interface CoronaFBAudienceNetworkPaidAdStatus: NSObject

@property (nonatomic, assign) BOOL     isLoaded;

@end

// ----------------------------------------------------------------------------

@interface CoronaFBAudienceNetworkPaidAdInstance: NSObject

@property (nonatomic, strong) NSObject *adInstance;
@property (nonatomic, copy)   NSString *adType;
@property (nonatomic, assign) CGFloat  width;
@property (nonatomic, assign) CGFloat  height;

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType;
- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType width:(CGFloat)width height:(CGFloat)height;
- (void)invalidateInfo;

@end

// ----------------------------------------------------------------------------

@interface CoronaFBAudienceNetworkPaidDelegate : UIViewController <FBInterstitialAdDelegate, FBAdViewDelegate, FBRewardedVideoAdDelegate>

@property (nonatomic, assign) CoronaLuaRef      coronaListener;
@property (nonatomic, weak)   id<CoronaRuntime> coronaRuntime;

- (void)dispatchLuaEvent:(NSDictionary *)dict;

@end

// ----------------------------------------------------------------------------

class FBAudienceNetworkPaidLibrary
{
  public:
    typedef FBAudienceNetworkPaidLibrary Self;
    
  public:
    static const char kName[];
    
  public:
    static int Open(lua_State *L);
    static int Finalizer(lua_State *L);
    static Self *ToLibrary(lua_State *L);
    
  protected:
    FBAudienceNetworkPaidLibrary();
    bool Initialize(CoronaLuaRef listener);
    
  public:
    static int init(lua_State *L);
    static int load(lua_State *L);
    static int show(lua_State *L);
    static int hide(lua_State *L);
    static int isLoaded(lua_State *L);
    static int getSize(lua_State *L);
    
  private: // internal helper functions
    static void logMsg(lua_State *L, NSString *msgType,  NSString *errorMsg);
    static bool isSDKInitialized(lua_State *L);
    
  private:
    NSString *functionSignature;               // used in logMsg to identify function
    UIViewController *coronaViewController;
};

// ----------------------------------------------------------------------------

const char FBAudienceNetworkPaidLibrary::kName[] = PLUGIN_NAME;
CoronaFBAudienceNetworkPaidDelegate *fbAudienceNetworkDelegate = nil;

// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// log message to console
void
FBAudienceNetworkPaidLibrary::logMsg(lua_State *L, NSString* msgType, NSString* errorMsg)
{
  Self *context = ToLibrary(L);
  
  if (context) {
    Self& library = *context;
    
    NSString *functionID = [library.functionSignature copy];
    if (functionID.length > 0) {
      functionID = [functionID stringByAppendingString:@", "];
    }
    
    CoronaLuaLogPrefix(L, [msgType UTF8String], UTF8StringWithFormat(@"%@%@", functionID, errorMsg));
  }
}

// check if SDK calls can be made
bool
FBAudienceNetworkPaidLibrary::isSDKInitialized(lua_State *L)
{
  // has init() been called?
  if (fbAudienceNetworkDelegate.coronaListener == NULL) {
    logMsg(L, ERROR_MSG, @"fbAudienceNetwork.init() must be called before calling other API methods");
    return false;
  }
  
  // have we got our placement ids from the endpoint?
  if (! [fbObjects[SDKREADY_KEY] boolValue]) {
    logMsg(L, ERROR_MSG, @"You must wait for the 'init' event before calling other API methods");
    return false;
  }
  
  return true;
}

// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

FBAudienceNetworkPaidLibrary::FBAudienceNetworkPaidLibrary()
:	coronaViewController(NULL)
{
}

bool
FBAudienceNetworkPaidLibrary::Initialize(void *platformContext)
{
  bool shouldInit = (fbAudienceNetworkDelegate == nil);
  
  if (shouldInit) {
    id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
    coronaViewController = runtime.appViewController;
    
    fbAudienceNetworkDelegate = [CoronaFBAudienceNetworkPaidDelegate new];
    fbAudienceNetworkDelegate.coronaRuntime = runtime;
    
    fbObjects = [NSMutableDictionary new];
    fbObjects[SDKREADY_KEY] = @(false);
  }
  
  return shouldInit;
}

int
FBAudienceNetworkPaidLibrary::Open(lua_State *L)
{
  // Register __gc callback
  const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
  CoronaLuaInitializeGCMetatable(L, kMetatableName, Finalizer);
  
  void *platformContext = CoronaLuaGetContext(L);
  
  // Set library as upvalue for each library function
  Self *library = new Self;
  
  if (library->Initialize(platformContext)) {
    // Functions in library
    static const luaL_Reg kFunctions[] = {
      {"init", init},
      {"load", load},
      {"show", show},
      {"hide", hide},
      {"isLoaded", isLoaded},
      {"getSize", getSize},
      {NULL, NULL}
    };
    
    // Register functions as closures, giving each access to the
    // 'library' instance via ToLibrary()
    {
      CoronaLuaPushUserdata(L, library, kMetatableName);
      luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
    }
  }
  
  return 1;
}

int
FBAudienceNetworkPaidLibrary::Finalizer(lua_State *L)
{
  Self *library = (Self *)CoronaLuaToUserdata(L, 1);
  
  // clear the saved ad objects
  [fbObjects removeAllObjects];
  
  CoronaLuaDeleteRef(L, fbAudienceNetworkDelegate.coronaListener);
  fbAudienceNetworkDelegate = nil;
  
  delete library;
  
  return 0;
}

FBAudienceNetworkPaidLibrary *
FBAudienceNetworkPaidLibrary::ToLibrary(lua_State *L)
{
  // library is pushed as part of the closure
  Self *library = (Self *)CoronaLuaToUserdata(L, lua_upvalueindex(1));
  return library;
}

// [Lua] fbAudienceNetwork.init(listener [, options])
int
FBAudienceNetworkPaidLibrary::init(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.init(listener [, options])";
  
  // prevent init from being called twice
  if (fbAudienceNetworkDelegate.coronaListener != NULL) {
    logMsg(L, WARNING_MSG, @"init() should only be called once");
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 1) || (nargs > 2)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
    return 0;
  }
  
  const char *hashedId = NULL;
  NSMutableArray *hashedIds = [NSMutableArray new];
  
  // Get listener key (required)
  if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
    fbAudienceNetworkDelegate.coronaListener = CoronaLuaNewRef(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"listener expected, got: %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // check second parameter
  if (! lua_isnoneornil(L, 2)) {
    if (lua_type(L, 2) == LUA_TSTRING) {
      // Single device hashed id
      hashedId = lua_tostring(L, 2);
    }
    else if (lua_type(L, 2) == LUA_TTABLE) {
      bool legacyAPI = false;
      
      for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
        if (lua_type(L, -2) != LUA_TSTRING) {
          legacyAPI = true;
          lua_pop(L, 2);
          break;
        }
        
        const char *key = lua_tostring(L, -2);
        
        if (UTF8IsEqual(key, "testDevices")) {
          if (lua_type(L, -1) == LUA_TSTRING) {
            hashedId = lua_tostring(L, -1);
          }
          else if (lua_type(L, -1) == LUA_TTABLE) {
            int ntypes = (int)lua_objlen(L, -1);
            
            if (ntypes > 0) {
              for (int i=1; i<=ntypes; i++) {
                lua_rawgeti(L, -1, i);
                
                if (lua_type(L, -1) == LUA_TSTRING) {
                  [hashedIds addObject:@(lua_tostring(L, -1))];
                }
                else {
                  logMsg(L, ERROR_MSG, MsgFormat(@"hashedId[%d] (string) expected, got: %s", i, luaL_typename(L, -1)));
                  return 0;
                }
                lua_pop(L, 1);
              }
            }
            else {
              logMsg(L, ERROR_MSG, MsgFormat(@"hashedId table cannot be empty"));
              return 0;
            }
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"options.hashedId (string or table) expected, got: %s", luaL_typename(L, -1)));
            return 0;
          }
        }
		else if (UTF8IsEqual(key, "advertiserTrackingEnabled")) {
			[FBAdSettings setAdvertiserTrackingEnabled:lua_toboolean(L, -1)];
		}
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
          return 0;
        }
      }
      
      if (legacyAPI) {
        // Multiple device hashed id's
        int ntypes = (int)lua_objlen(L, 2);
        
        if (ntypes > 0) {
          for (int i=1; i<=ntypes; i++) {
            lua_rawgeti(L, 2, i);
            
            if (lua_type(L, -1) == LUA_TSTRING) {
              [hashedIds addObject:@(lua_tostring(L, -1))];
            }
            else {
              logMsg(L, ERROR_MSG, MsgFormat(@"hashedId[%d] (string) expected, got: %s", i, luaL_typename(L, -1)));
              return 0;
            }
            lua_pop(L, 1);
          }
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"hashedId table cannot be empty"));
          return 0;
        }
      }
    }
    else {
      logMsg(L, ERROR_MSG, MsgFormat(@"hashedId (string or table) expected, got %s", luaL_typename(L, 2)));
      return 0;
    }
  }
  
  // set test devices
  if (hashedId != NULL) {
    [FBAdSettings addTestDevice:@(hashedId)];
  }
  
  if (hashedIds.count > 0) {
    [FBAdSettings addTestDevices:hashedIds];
  }
  
  // log hashed device ID to the console
  NSLog(@"Test mode device hash: %@", [FBAdSettings testDeviceHash]);
  
  // log the plugin version to device console
  NSLog(@"%s: %s (SDK: %s)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);
  
  fbObjects[SDKREADY_KEY] = @(true);
  
  // send Corona Lua Event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()) : PHASE_INIT
  };
  [fbAudienceNetworkDelegate dispatchLuaEvent:coronaEvent];
  
  return 0;
}

// [Lua] fbAudienceNetwork.load(adUnitType, options)
int
FBAudienceNetworkPaidLibrary::load(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.load(adUnitType, options)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 2) || (nargs > 3)) { // 3 for legacy support
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 2 arguments, got %d", nargs));
    return 0;
  }
  
  const char *adUnitType = NULL;
  const char *placementId = NULL;
  const char *requestedBannerSize = BANNER_HEIGHT_50;
  bool legacyAPI = false;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    adUnitType = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  if (lua_type(L, 2) == LUA_TSTRING) {
    placementId = lua_tostring(L, 2);
    legacyAPI = true;
  }
  else if (lua_type(L, 2) == LUA_TTABLE) {
    // traverse all options
    for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
      if (lua_type(L, -2) != LUA_TSTRING) {
        logMsg(L, ERROR_MSG, @"options must be a key/value table");
        return 0;
      }
      
      const char *key = lua_tostring(L, -2);
      
      if (UTF8IsEqual(key, "placementId")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          placementId = lua_tostring(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.placementId (string) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else if (UTF8IsEqual(key, "bannerSize")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          requestedBannerSize = lua_tostring(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.bannerSize (string) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
        return 0;
      }
    }
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got %s", luaL_typename(L, 2)));
    return 0;
  }
  
  if (legacyAPI) {
    // check banner size
    if (! lua_isnoneornil(L, 3)) {
      if (lua_type(L, 3) == LUA_TSTRING) {
        requestedBannerSize = lua_tostring(L, 3);
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"bannerSize (string) expected, got %s", luaL_typename(L, 3)));
        return 0;
      }
    }
  }
  
  // validation
  if (! [validAdTypes containsObject:@(adUnitType)]) {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType '%s' invalid", adUnitType));
    return 0;
  }
  
  if (UTF8IsEqual(adUnitType, TYPE_BANNER)) {
    // check type
    CoronaFBAudienceNetworkPaidAdInstance *oldAdInstance = fbObjects[@(placementId)];
    if (oldAdInstance != nil) {
      if (! [oldAdInstance.adType isEqualToString:@(TYPE_BANNER)]) {
        logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a banner", placementId));
        return 0;
      }
    }
    
    // calculate the Corona->device coordinate ratio.
    // we don't use display.contentScaleY here as there are cases where it's difficult to get the proper values to use
    // especially on Android. uses the same formula for iOS and Android for the sake of consistency.
    // re-calculate this value on every load as the ratio can change between orientation changes
    CGPoint point1 = {0, 0};
    CGPoint point2 = {1000, 1000};
    CGPoint uikitPoint1 = [fbAudienceNetworkDelegate.coronaRuntime coronaPointToUIKitPoint: point1];
    CGPoint uikitPoint2 = [fbAudienceNetworkDelegate.coronaRuntime coronaPointToUIKitPoint: point2];
    CGFloat yRatio = (uikitPoint2.y - uikitPoint1.y) / 1000.0;
    fbObjects[Y_RATIO_KEY] = @(yRatio);
    
    FBAdSize bannerAdSize = kFBAdSizeHeight50Banner;
    
    if (UTF8IsEqual(requestedBannerSize, BANNER_320_50)) {
      bannerAdSize = kFBAdSize320x50;
    }
    else if (UTF8IsEqual(requestedBannerSize, BANNER_HEIGHT_50)) {
      bannerAdSize = kFBAdSizeHeight50Banner;
    }
    else if (UTF8IsEqual(requestedBannerSize, BANNER_HEIGHT_90)) {
      bannerAdSize = kFBAdSizeHeight90Banner;
    }
    else if (UTF8IsEqual(requestedBannerSize, RECTANGLE_HEIGHT_250)) {
      bannerAdSize = kFBAdSizeHeight250Rectangle;
    }
    else {
      logMsg(L, WARNING_MSG, MsgFormat(@"bannerSize '%s' not valid. Using default size '%s'.", requestedBannerSize, BANNER_HEIGHT_50));
    }
    
    // Create the banner Ad
    FBAdView *bannerAd = [[FBAdView alloc]
      initWithPlacementID:@(placementId)
      adSize:bannerAdSize
      rootViewController:library.coronaViewController
    ];
    
    // If the banner size is 250 rectangle set the frame manually
    // (recommended by facebook in their docs, presumably to work around their own bug)
    // If/when their bug is fixed, this section of code should be removed.
    if (UTF8IsEqual(requestedBannerSize, RECTANGLE_HEIGHT_250)) {
      bannerAd.frame = CGRectMake(0, 0, 300, 250);
    }
    
    bannerAd.delegate = fbAudienceNetworkDelegate;
    bannerAd.hidden = true;
    [library.coronaViewController.view addSubview:bannerAd];
    
    // save ad object for future use
    CoronaFBAudienceNetworkPaidAdInstance *adInstance = [[CoronaFBAudienceNetworkPaidAdInstance alloc]
      initWithAd:bannerAd
      adType:@(adUnitType)
      width:bannerAd.bounds.size.width
      height:bannerAd.bounds.size.height
    ];
    fbObjects[@(placementId)] = adInstance;
    
    // save extra ad status information not available in ad object
    CoronaFBAudienceNetworkPaidAdStatus *adStatus = [CoronaFBAudienceNetworkPaidAdStatus new];
    NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, @(placementId)];
    fbObjects[statusKey] = adStatus;
    
    [bannerAd loadAd];
  }
  else if (UTF8IsEqual(adUnitType, TYPE_INTERSTITIAL)) {
    // check type
    CoronaFBAudienceNetworkPaidAdInstance *oldAdInstance = fbObjects[@(placementId)];
    if (oldAdInstance != nil) {
      if (! [oldAdInstance.adType isEqualToString:@(TYPE_INTERSTITIAL)]) {
        logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not an interstitial", placementId));
        return 0;
      }
    }
    
    // create the interstitial ad
    FBInterstitialAd *interstitialAd = [[FBInterstitialAd alloc] initWithPlacementID:@(placementId)];
    interstitialAd.delegate = fbAudienceNetworkDelegate;
    
    // save ad object for future use
    CoronaFBAudienceNetworkPaidAdInstance *adInstance = [[CoronaFBAudienceNetworkPaidAdInstance alloc]
      initWithAd:interstitialAd
      adType:@(adUnitType)
    ];
    fbObjects[@(placementId)] = adInstance;
    
    // save extra ad status information not available in ad object
    CoronaFBAudienceNetworkPaidAdStatus *adStatus = [CoronaFBAudienceNetworkPaidAdStatus new];
    NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, @(placementId)];
    fbObjects[statusKey] = adStatus;
    
    [interstitialAd loadAd];
  }
  else if (UTF8IsEqual(adUnitType, TYPE_REWARDED)) {
	  // check type
	  CoronaFBAudienceNetworkPaidAdInstance *oldAdInstance = fbObjects[@(placementId)];
	  if (oldAdInstance != nil) {
		  if (! [oldAdInstance.adType isEqualToString:@(TYPE_REWARDED)]) {
			  logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a rewarded video", placementId));
			  return 0;
		  }
	  }
	  
	  NSString *activePlacementId = @(placementId);
	  
	  // create the interstitial ad
	  FBRewardedVideoAd *ad = [[FBRewardedVideoAd alloc] initWithPlacementID:activePlacementId];
	  ad.delegate = fbAudienceNetworkDelegate;
	  
	  // save ad object for future use
	  CoronaFBAudienceNetworkPaidAdInstance *adInstance = [[CoronaFBAudienceNetworkPaidAdInstance alloc]
													   initWithAd:ad
													   adType:@(adUnitType)
													   ];
	  fbObjects[@(placementId)] = adInstance;
	  
	  // save extra ad status information not available in ad object
	  CoronaFBAudienceNetworkPaidAdStatus *adStatus = [[CoronaFBAudienceNetworkPaidAdStatus alloc] init];
	  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, activePlacementId];
	  fbObjects[statusKey] = adStatus;
	  
	  [ad loadAd];
  }
  
  return 0;
}

// [Lua] fbAudienceNetwork.show(adUnitType, options)
int
FBAudienceNetworkPaidLibrary::show(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.show(adUnitType, options)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if ((nargs < 2) || (nargs > 3)) { // 3 for legacy support
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 2 arguments, got %d", nargs));
    return 0;
  }
  
  const char *adUnitType = NULL;
  const char *placementId = NULL;
  const char *yAlign = NULL;
  double yOffset = 0;
  bool legacyAPI = false;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    adUnitType = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  if (lua_type(L, 2) == LUA_TSTRING) {
    placementId = lua_tostring(L, 2);
    legacyAPI = true;
  }
  else if (lua_type(L, 2) == LUA_TTABLE) {
    // traverse all options
    for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
      if (lua_type(L, -2) != LUA_TSTRING) {
        logMsg(L, ERROR_MSG, @"options must be a key/value table");
        return 0;
      }
      
      const char *key = lua_tostring(L, -2);
      
      if (UTF8IsEqual(key, "placementId")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          placementId = lua_tostring(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.placementId (string) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else if (UTF8IsEqual(key, "y")) {
        if (lua_type(L, -1) == LUA_TSTRING) {
          yAlign = lua_tostring(L, -1);
        }
        else if (lua_type(L, -1) == LUA_TNUMBER) {
          yOffset = lua_tonumber(L, -1);
        }
        else {
          logMsg(L, ERROR_MSG, MsgFormat(@"options.y (string or number) expected, got: %s", luaL_typename(L, -1)));
          return 0;
        }
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
        return 0;
      }
    }
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got %s", luaL_typename(L, 2)));
    return 0;
  }
  
  if (legacyAPI) {
    if (! lua_isnoneornil(L, 3)) {
      if (lua_type(L, 3) == LUA_TTABLE) {
        // traverse and verify all options
        for (lua_pushnil(L); lua_next(L, 3) != 0; lua_pop(L, 1)) {
          const char *key = lua_tostring(L, -2);
          
          if (UTF8IsEqual(key, "y")) {
            if (lua_type(L, -1) == LUA_TNUMBER) {
              yOffset = lua_tonumber(L, -1);
            }
            else {
              logMsg(L, ERROR_MSG, MsgFormat(@"options.y (number) expected, got: %s", luaL_typename(L, -1)));
              return 0;
            }
          }
          else if (UTF8IsEqual(key, "yAlign")) {
            if (lua_type(L, -1) == LUA_TSTRING) {
              yAlign = lua_tostring(L, -1);
            }
            else {
              logMsg(L, ERROR_MSG, MsgFormat(@"options.yAlign (string) expected, got: %s", luaL_typename(L, -1)));
              return 0;
            }
          }
          else {
            logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
            return 0;
          }
        }
      }
      else {
        logMsg(L, ERROR_MSG, MsgFormat(@"options (table) expected, got %s", luaL_typename(L, 3)));
        return 0;
      }
    }
  }
  
  // validation
  if (! [validAdTypes containsObject:@(adUnitType)]) {
    logMsg(L, ERROR_MSG, MsgFormat(@"adUnitType '%s' invalid", adUnitType));
    return 0;
  }
  
  if (yAlign != NULL) {
    if (! [validBannerPositions containsObject:@(yAlign)]) {
      logMsg(L, ERROR_MSG, MsgFormat(@"y '%s' invalid", yAlign));
      return 0;
    }
  }
  
  // get ad info
  CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[@(placementId)];
  if (adInstance == nil) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
    return 0;
  }
  
  if (UTF8IsEqual(adUnitType, TYPE_BANNER)) {
    if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a banner", placementId));
      return 0;
    }
    
    FBAdView *bannerAd = (FBAdView *)adInstance.adInstance;
    NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, bannerAd.placementID];
    CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
    
    if (! adStatus.isLoaded) {
      logMsg(L, ERROR_MSG, MsgFormat(@"banner placementId '%s' not loaded", placementId));
      return 0;
    }
    
    // get screen size
    CGFloat orientedWidth = library.coronaViewController.view.frame.size.width;
    CGFloat orientedHeight = library.coronaViewController.view.frame.size.height;
    
    // calculate the size for the ad, and set its frame
    CGSize bannerSize = bannerAd.bounds.size;
    
    CGFloat bannerCenterX = ((orientedWidth - bannerSize.width) / 2);
    CGFloat bannerCenterY = ((orientedHeight - bannerSize.height) / 2);
    CGFloat bannerTopY = 0;
    CGFloat bannerBottomY = (orientedHeight - bannerSize.height);
    
    CGRect bannerFrame = bannerAd.frame;
    bannerFrame.origin.x = bannerCenterX;
    
    // set the banner position
    if (yAlign == NULL) {
      // convert corona coordinates to device coordinates and set banner position
      CGFloat newBannerY = floor(yOffset * [fbObjects[Y_RATIO_KEY] floatValue]);
      
      // negative values count from bottom
      if (yOffset < 0) {
        newBannerY = bannerBottomY + newBannerY;
      }
      
      // make sure the banner frame is visible.
      // adjust it if the user has specified 'y' which will render it partially off-screen
      NSUInteger ySnap = 0;
      if (newBannerY + bannerFrame.size.height > orientedHeight) {
        logMsg(L, WARNING_MSG, @"Banner y position off screen. Adjusting position.");
        ySnap = newBannerY - orientedHeight + bannerFrame.size.height;
      }
      bannerFrame.origin.y = newBannerY - ySnap;
    }
    else {
      if (UTF8IsEqual(yAlign, BANNER_ALIGN_TOP)) {
        bannerFrame.origin.y = bannerTopY;
      }
      else if (UTF8IsEqual(yAlign, BANNER_ALIGN_CENTER)) {
        bannerFrame.origin.y = bannerCenterY;
      }
      else if (UTF8IsEqual(yAlign, BANNER_ALIGN_BOTTOM)) {
        bannerFrame.origin.y = bannerBottomY;
      }
    }
    
    [bannerAd setFrame:bannerFrame];
    bannerAd.hidden = false;
    
  }
  else if (UTF8IsEqual(adUnitType, TYPE_INTERSTITIAL)) {
    if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_INTERSTITIAL)) {
      logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not an interstitial", placementId));
      return 0;
    }
    
    FBInterstitialAd *interstitialAd = (FBInterstitialAd *)adInstance.adInstance;
    
    // NOTE: delegate is set to nil after ad has been closed to prevent it from being used twice
    if ((interstitialAd.delegate == nil) || (! interstitialAd.isAdValid)) {
      logMsg(L, ERROR_MSG, MsgFormat(@"interstitial placementId '%s' not loaded", placementId));
      return 0;
    }
    
    [interstitialAd showAdFromRootViewController:library.coronaViewController];
  }
  else if (UTF8IsEqual(adUnitType, TYPE_REWARDED)) {
	  if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_REWARDED)) {
		  logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not an interstitial", placementId));
		  return 0;
	  }
	  
	  FBRewardedVideoAd *interstitialAd = (FBRewardedVideoAd *)adInstance.adInstance;
	  
	  // NOTE: delegate is set to nil after ad has been closed to prevent it from being used twice
	  if ((interstitialAd.delegate == nil) || (! interstitialAd.isAdValid)) {
		  logMsg(L, ERROR_MSG, MsgFormat(@"interstitial placementId '%s' not loaded", placementId));
		  return 0;
	  }
	  
	  [interstitialAd showAdFromRootViewController:library.coronaViewController];
  }
  
  return 0;
}

// [Lua] fbAudienceNetwork.hide(placementId) - For banners only
int
FBAudienceNetworkPaidLibrary::hide(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.hide(placementId)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if (nargs != 1) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // get ad info
  CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[@(placementId)];
  if (adInstance == nil) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
    return 0;
  }
  
  // only banners can be hidden
  if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a banner", placementId));
    return 0;
  }
  
  // remove banner (automatic dealloc will occur)
  [fbObjects removeObjectForKey:@(placementId)];
  
  return 0;
}

// [Lua] fbAudienceNetwork.isLoaded(placementId)
int
FBAudienceNetworkPaidLibrary::isLoaded(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.isLoaded(placementId)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if (nargs != 1) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  bool isAdLoaded = false;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // get ad info
  CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[@(placementId)];
  
  if (adInstance != nil) {
    if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
      FBAdView *bannerAd = (FBAdView *)adInstance.adInstance;
      NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, bannerAd.placementID];
      CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
      isAdLoaded = adStatus.isLoaded;
    }
    else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_INTERSTITIAL)) {
      FBInterstitialAd *interstitialAd = (FBInterstitialAd *)adInstance.adInstance;
      isAdLoaded = ((interstitialAd.delegate != nil) && interstitialAd.isAdValid);
    }
	else if (UTF8IsEqual([adInstance.adType UTF8String], TYPE_REWARDED)) {
		FBRewardedVideoAd *interstitialAd = (FBRewardedVideoAd *)adInstance.adInstance;
		isAdLoaded = ((interstitialAd.delegate != nil) && interstitialAd.isAdValid);
	}
  }
  
  lua_pushboolean(L, isAdLoaded);
  
  return 1;
}

// [Lua] fbAudienceNetwork.getSize(placementId)
int
FBAudienceNetworkPaidLibrary::getSize(lua_State *L)
{
  Self *context = ToLibrary(L);
  
  if (! context) { // abort if no valid context
    return 0;
  }
  
  Self& library = *context;
  
  library.functionSignature = @"fbAudienceNetwork.getSize(placementId)";
  
  if (! isSDKInitialized(L)) {
    return 0;
  }
  
  // check number of arguments
  int nargs = lua_gettop(L);
  if (nargs != 1) {
    logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
    return 0;
  }
  
  const char *placementId = NULL;
  CGFloat width = 0;
  CGFloat height = 0;
  
  if (lua_type(L, 1) == LUA_TSTRING) {
    placementId = lua_tostring(L, 1);
  }
  else {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId (string) expected, got %s", luaL_typename(L, 1)));
    return 0;
  }
  
  // get ad info
  CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[@(placementId)];
  if (adInstance == nil) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' not loaded", placementId));
    return 0;
  }
  
  // getSize only works with banners
  if (! UTF8IsEqual([adInstance.adType UTF8String], TYPE_BANNER)) {
    logMsg(L, ERROR_MSG, MsgFormat(@"placementId '%s' is not a banner", placementId));
    return 0;
  }
  
  width = floor(adInstance.width / [fbObjects[Y_RATIO_KEY] floatValue]);
  height = floor(adInstance.height / [fbObjects[Y_RATIO_KEY] floatValue]);
  
  // Push the width/height of the Ad
  lua_pushnumber(L, (int)roundf(width));
  lua_pushnumber(L, (int)roundf(height));
  
  return 2;
}

// ----------------------------------------------------------------------------
// delegate implementation
// ----------------------------------------------------------------------------

@implementation CoronaFBAudienceNetworkPaidDelegate

- (instancetype)init {
  if (self = [super init]) {
    self.coronaListener = NULL;
    self.coronaRuntime = NULL;
  }
  
  return self;
}

// dispatch a new Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    lua_State *L = self.coronaRuntime.L;
    CoronaLuaRef coronaListener = self.coronaListener;
    bool hasErrorKey = false;
    
    // create new event
    CoronaLuaNewEvent(L, EVENT_NAME);
    
    for (NSString *key in dict) {
      CoronaLuaPushValue(L, [dict valueForKey:key]);
      lua_setfield(L, -2, key.UTF8String);
      
      if (! hasErrorKey) {
        hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
      }
    }
    
    // add error key if not in dict
    if (! hasErrorKey) {
      lua_pushboolean(L, false);
      lua_setfield(L, -2, CoronaEventIsErrorKey());
    }
    
    // add provider
    lua_pushstring(L, PROVIDER_NAME );
    lua_setfield(L, -2, CoronaEventProviderKey());
    
    CoronaLuaDispatchEvent(L, coronaListener, 0);
  }];
}

// Asks the delegate for a view controller to present modal content, such as the in-app browser that can appear when an ad is clicked.
- (UIViewController *)viewControllerForPresentingModalView
{
  return [[self coronaRuntime] appViewController];
}

// ----------------------------------------------------------------------------
// Banner delegates

// Sent after an FBAdView fails to load the ad.
- (void)adView:(FBAdView *)adView didFailWithError:(NSError *)error
{
  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, adView.placementID];
  CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
  adStatus.isLoaded = false;
  
  NSString *errorMessage = [NSString stringWithFormat:@"%@ - Error Code %ld", [error localizedDescription], (long)error.code];
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_FAILED,
    @(CoronaEventTypeKey()): @(TYPE_BANNER),
    @(CORONA_EVENT_PLACEMENTID_KEY): adView.placementID,
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): errorMessage
  };
  [self dispatchLuaEvent:coronaEvent];
}

// Sent when an ad has been successfully loaded.
- (void)adViewDidLoad:(FBAdView *)adView;
{
  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, adView.placementID];
  CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
  adStatus.isLoaded = true;
  
  NSString *phase = adView.hidden ? PHASE_LOADED : PHASE_REFRESHED;
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): phase,
    @(CoronaEventTypeKey()): @(TYPE_BANNER),
    @(CORONA_EVENT_PLACEMENTID_KEY): adView.placementID
  };
  [self dispatchLuaEvent:coronaEvent];
  
}

// Sent after an ad has been clicked by the person.
- (void)adViewDidClick:(FBAdView *)adView
{
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_CLICKED,
    @(CoronaEventTypeKey()): @(TYPE_BANNER),
    @(CORONA_EVENT_PLACEMENTID_KEY): adView.placementID
  };
  [self dispatchLuaEvent:coronaEvent];
}

// When an banner is clicked, the modal view will be presented and when the user finishes the interaction with the modal
// view and dismiss it, this message will be sent, returning control to the application.
- (void)adViewDidFinishHandlingClick:(FBAdView *)adView // Not available on Android (Ignore)
{
  // NOP
}

- (void)adViewWillLogImpression:(FBAdView *)adView
{
  // NOP
}

// ----------------------------------------------------------------------------
// Interstitial delegates

// Sent when an FBInterstitialAd fails to load an ad.
- (void)interstitialAd:(FBInterstitialAd *)interstitialAd didFailWithError:(NSError *)error
{
  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, interstitialAd.placementID];
  CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
  adStatus.isLoaded = false;
  
  // prevent ad from being used again
  interstitialAd.delegate = nil;
  
  NSString *errorMessage = [NSString stringWithFormat:@"%@ - Error Code %ld", [error localizedDescription], (long)error.code];
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_FAILED,
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CORONA_EVENT_PLACEMENTID_KEY): interstitialAd.placementID,
    @(CoronaEventIsErrorKey()): @(true),
    @(CoronaEventResponseKey()): errorMessage
  };
  [self dispatchLuaEvent:coronaEvent];
}

// Sent when an FBInterstitialAd successfully loads an ad.
- (void)interstitialAdDidLoad:(FBInterstitialAd *)interstitialAd
{
  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, interstitialAd.placementID];
  CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
  adStatus.isLoaded = true;
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_LOADED,
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CORONA_EVENT_PLACEMENTID_KEY): interstitialAd.placementID
  };
  [self dispatchLuaEvent:coronaEvent];
  
}

// Sent after an ad in the FBInterstitialAd object is clicked. The appropriate app store view or app browser will be launched.
- (void)interstitialAdDidClick:(FBInterstitialAd *)interstitialAd
{
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_CLICKED,
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CORONA_EVENT_PLACEMENTID_KEY): interstitialAd.placementID
  };
  [self dispatchLuaEvent:coronaEvent];
}

// Sent immediately before an FBInterstitialAd object will be dismissed from the screen.
- (void)interstitialAdWillClose:(FBInterstitialAd *)interstitialAd
{
  // NOP
  // Using interstitialAdDidClose
}

// Sent after an FBInterstitialAd object has been dismissed from the screen, returning control to your application.
- (void)interstitialAdDidClose:(FBInterstitialAd *)interstitialAd
{
  NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, interstitialAd.placementID];
  CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
  adStatus.isLoaded = false;
  
  // must deallocate ad object to ensure video playback is terminated when closed
  CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[interstitialAd.placementID];
  interstitialAd.delegate = nil;
  adInstance.adInstance = nil;
  [fbObjects removeObjectForKey:interstitialAd.placementID];
  
  // send Corona Lua event
  NSDictionary *coronaEvent = @{
    @(CoronaEventPhaseKey()): PHASE_CLOSED,
    @(CoronaEventTypeKey()): @(TYPE_INTERSTITIAL),
    @(CORONA_EVENT_PLACEMENTID_KEY): interstitialAd.placementID
  };
  [self dispatchLuaEvent:coronaEvent];
}

// Sent immediately before the impression of an FBInterstitialAd object will be logged.
- (void)interstitialAdWillLogImpression:(FBInterstitialAd *)interstitialAd
{
  // NOP
  // Cannot be used for a 'displayed' event as the user can close the ad before this triggers
}

-(void)rewardedVideoAd:(FBRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
	NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, rewardedVideoAd.placementID];
	CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
	adStatus.isLoaded = false;
	
	// prevent ad from being used again
	rewardedVideoAd.delegate = nil;
	
	NSString *errorMessage = [NSString stringWithFormat:@"%@ - Error Code %ld", [error localizedDescription], (long)error.code];
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
								  @(CoronaEventPhaseKey()): PHASE_FAILED,
								  @(CoronaEventTypeKey()): @(TYPE_REWARDED),
								  @(CORONA_EVENT_PLACEMENTID_KEY): rewardedVideoAd.placementID,
								  @(CoronaEventIsErrorKey()): @(true),
								  @(CoronaEventResponseKey()): errorMessage
								  };
	[self dispatchLuaEvent:coronaEvent];

}

-(void)rewardedVideoAdDidLoad:(FBRewardedVideoAd *)rewardedVideoAd
{
	NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, rewardedVideoAd.placementID];
	CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
	adStatus.isLoaded = true;
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
								  @(CoronaEventPhaseKey()): PHASE_LOADED,
								  @(CoronaEventTypeKey()): @(TYPE_REWARDED),
								  @(CORONA_EVENT_PLACEMENTID_KEY): rewardedVideoAd.placementID
								  };
	[self dispatchLuaEvent:coronaEvent];
	
}

-(void)rewardedVideoAdDidClick:(FBRewardedVideoAd *)rewardedVideoAd
{
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
								  @(CoronaEventPhaseKey()): PHASE_CLICKED,
								  @(CoronaEventTypeKey()): @(TYPE_REWARDED),
								  @(CORONA_EVENT_PLACEMENTID_KEY): rewardedVideoAd.placementID
								  };
	[self dispatchLuaEvent:coronaEvent];
}

-(void)rewardedVideoAdDidClose:(FBRewardedVideoAd *)rewardedVideoAd
{
	NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, rewardedVideoAd.placementID];
	CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
	adStatus.isLoaded = false;
	
	// must deallocate ad object to ensure video playback is terminated when closed
	CoronaFBAudienceNetworkPaidAdInstance *adInstance = fbObjects[rewardedVideoAd.placementID];
	rewardedVideoAd.delegate = nil;
	adInstance.adInstance = nil;
	[fbObjects removeObjectForKey:rewardedVideoAd.placementID];
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
								  @(CoronaEventPhaseKey()): PHASE_CLOSED,
								  @(CoronaEventTypeKey()): @(TYPE_REWARDED),
								  @(CORONA_EVENT_PLACEMENTID_KEY): rewardedVideoAd.placementID
								  };
	[self dispatchLuaEvent:coronaEvent];
}

-(void)rewardedVideoAdVideoComplete:(FBRewardedVideoAd *)rewardedVideoAd
{
	NSString *statusKey = [NSString stringWithFormat:STATUS_FORMAT, rewardedVideoAd.placementID];
	CoronaFBAudienceNetworkPaidAdStatus *adStatus = fbObjects[statusKey];
	adStatus.isLoaded = false;
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
								  @(CoronaEventPhaseKey()): PHASE_REWARD,
								  @(CoronaEventTypeKey()): @(TYPE_REWARDED),
								  @(CORONA_EVENT_PLACEMENTID_KEY): rewardedVideoAd.placementID
								  };
	[self dispatchLuaEvent:coronaEvent];
}
@end

// ----------------------------------------------------------------------------

@implementation CoronaFBAudienceNetworkPaidAdStatus

- (instancetype)init {
  if (self = [super init]) {
    self.isLoaded = false;
  }
  
  return self;
}

@end

// ----------------------------------------------------------------------------

@implementation CoronaFBAudienceNetworkPaidAdInstance

- (instancetype)init {
  return [self initWithAd:nil adType:nil];
}

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType
{
  return [self initWithAd:adInstance adType:adType width:0 height:0];
}

- (instancetype)initWithAd:(NSObject *)adInstance adType:(NSString *)adType width:(CGFloat)width height:(CGFloat)height
{
  if (self = [super init]) {
    self.adInstance = adInstance;
    self.adType = adType;
    self.width = width;
    self.height = height;
  }
  
  return self;
}

- (void)invalidateInfo
{
  if (self.adInstance != nil) {
    // make sure ad object gets deallocated
    if (UTF8IsEqual([self.adType UTF8String], TYPE_BANNER)) {
      FBAdView *bannerAd = (FBAdView *)self.adInstance;
      bannerAd.delegate = nil;
      [bannerAd removeFromSuperview];
    }
    else if (UTF8IsEqual([self.adType UTF8String], TYPE_INTERSTITIAL)) {
      FBInterstitialAd *interstitialAd = (FBInterstitialAd *)self.adInstance;
      interstitialAd.delegate = nil;
    }
    
    self.adInstance = nil;
  }
}

- (void)dealloc
{
  [self invalidateInfo];
}

@end

// ----------------------------------------------------------------------------


CORONA_EXPORT int luaopen_plugin_fbAudienceNetwork(lua_State *L)
{
  return FBAudienceNetworkPaidLibrary::Open(L);
}

CORONA_EXPORT int luaopen_plugin_fbAudienceNetwork_paid(lua_State *L)
{
  return FBAudienceNetworkPaidLibrary::Open(L);
}
