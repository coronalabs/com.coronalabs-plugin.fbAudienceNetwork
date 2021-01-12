//
//  LuaLoader.java
//  Facebook Advertising Network Paid Plugin
//
//  Copyright (c) 2015 CoronaLabs inc. All rights reserved.
//

// @formatter:off

package plugin.fbAudienceNetwork;

import android.graphics.Point;
import android.util.Log;
import android.view.Display;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;
import com.facebook.ads.Ad;
import com.facebook.ads.AdError;
import com.facebook.ads.AdListener;
import com.facebook.ads.AdSettings;
import com.facebook.ads.AdSize;
import com.facebook.ads.AdView;
import com.facebook.ads.AudienceNetworkAds;
import com.facebook.ads.InterstitialAd;
import com.facebook.ads.InterstitialAdListener;
import com.facebook.ads.RewardedVideoAd;
import com.facebook.ads.RewardedVideoAdListener;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.NamedJavaFunction;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static android.content.res.Configuration.ORIENTATION_PORTRAIT;
import static java.lang.Math.ceil;


/**
 * Implements the Lua interface for a Corona plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
@SuppressWarnings({"unused", "RedundantSuppression", "SpellCheckingInspection"})
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
    private static final String PLUGIN_NAME = "plugin.fbAudienceNetwork";
    private static final String PLUGIN_VERSION = "1.0.2";
    private static final String PLUGIN_SDK_VERSION = com.facebook.ads.BuildConfig.VERSION_NAME;

    private static final String EVENT_NAME = "adsRequest";
    private static final String PROVIDER_NAME = "fbAudienceNetwork";

    // ad types
    private static final String TYPE_BANNER = "banner";
    private static final String TYPE_INTERSTITIAL = "interstitial";
    private static final String TYPE_REWARDED = "rewardedVideo";

    // valid ad types
    private static final List<String> validAdTypes = new ArrayList<>();

    // banner sizes
    private static final String BANNER_320_50 = "BANNER_320_50";
    private static final String BANNER_HEIGHT_50 = "BANNER_HEIGHT_50";
    private static final String BANNER_HEIGHT_90 = "BANNER_HEIGHT_90";
    private static final String RECTANGLE_HEIGHT_250 = "RECTANGLE_HEIGHT_250";

    // banner alignment
    private static final String BANNER_ALIGN_TOP = "top";
    private static final String BANNER_ALIGN_CENTER = "center";
    private static final String BANNER_ALIGN_BOTTOM = "bottom";

    // valid banner positions
    private static final List<String> validBannerPositions = new ArrayList<>();

    // event phases
    private static final String PHASE_INIT = "init";
    private static final String PHASE_LOADED = "loaded";
    private static final String PHASE_REFRESHED = "refreshed";
    private static final String PHASE_FAILED = "failed";
    private static final String PHASE_CLOSED = "closed";
    private static final String PHASE_CLICKED = "clicked";
    private static final String PHASE_REWARD = "reward";


    private static final String STATUS_SUFFIX = "_status";

    // message constants
    private static final String CORONA_TAG = "Corona";
    private static final String ERROR_MSG = "ERROR: ";
    private static final String WARNING_MSG = "WARNING: ";

    // add missing event keys
    private static final String EVENT_PHASE_KEY = "phase";
    private static final String EVENT_DATA_KEY = "data";
    private static final String EVENT_TYPE_KEY = "type";
    private static final String EVENT_PLACEMENTID_KEY = "placementId";

    // ad dictionary keys
    private static final String Y_RATIO_KEY = "yRatio";    // used to calculate Corona -> UIKit coordinate ratio
    private static final String SDKREADY_KEY = "sdkReady";  // true when corona's placement id's could be retrieved

    // saved objects (apiKey, ad state, etc)
    private static final Map<String, Object> fbObjects = new HashMap<>();

    private static int coronaListener = CoronaLua.REFNIL;
    private static CoronaRuntimeTaskDispatcher coronaRuntimeTaskDispatcher = null;

    private static String functionSignature = "";

    // ----------------------------------------------------------------------------------
    // Helper classes to keep track of information not available in the SDK base classes
    // ----------------------------------------------------------------------------------

    /**
     * Creates a new Lua interface to this plugin.
     * <p>
     * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
     * That is, only one instance of this class will be created for the lifetime of the application process.
     * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
     */
    public LuaLoader() {
        // Set up this plugin to listen for Corona runtime events to be received by methods
        // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
        CoronaEnvironment.addRuntimeListener(this);
    }


    // -------------------------------------------------------
    // Plugin lifecycle events
    // -------------------------------------------------------

    /**
     * Called when this plugin is being loaded via the Lua require() function.
     * <p>
     * Note that this method will be called everytime a new CoronaActivity has been launched.
     * This means that you'll need to re-initialize this plugin here.
     * <p>
     * Warning! This method is not called on the main UI thread.
     *
     * @param L Reference to the Lua state that the require() function was called from.
     * @return Returns the number of values that the require() function will return.
     * <p>
     * Expected to return 1, the library that the require() function is loading.
     */
    @Override
    public int invoke(LuaState L) {
        // Register this plugin into Lua with the following functions.
        NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]
                {
                        new init(),
                        new load(),
                        new show(),
                        new hide(),
                        new isLoaded(),
                        new getSize(),
                };
        String libName = L.toString(1);
        L.register(libName, luaFunctions);

        // Returning 1 indicates that the Lua require() function will return the above Lua
        return 1;
    }

    /**
     * Called after the Corona runtime has been created and just before executing the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
     *                Provides a LuaState object that allows the application to extend the Lua API.
     */
    @Override
    public void onLoaded(CoronaRuntime runtime) {
        // Note that this method will not be called the first time a Corona activity has been launched.
        // This is because this listener cannot be added to the CoronaEnvironment until after
        // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
        // However, this method will be called when a 2nd Corona activity has been created.
        if (coronaRuntimeTaskDispatcher == null) {
            coronaRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);

            fbObjects.put(SDKREADY_KEY, false);

            // add validation data
            validAdTypes.add(TYPE_BANNER);
            validAdTypes.add(TYPE_INTERSTITIAL);
            validAdTypes.add(TYPE_REWARDED);

            validBannerPositions.add(BANNER_ALIGN_TOP);
            validBannerPositions.add(BANNER_ALIGN_CENTER);
            validBannerPositions.add(BANNER_ALIGN_BOTTOM);
        }
    }

    /**
     * Called just after the Corona runtime has executed the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been started.
     */
    @Override
    public void onStarted(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
     * and other Corona related operations. This can happen when another Android activity (ie: window) has
     * been displayed, when the screen has been powered off, or when the screen lock is shown.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been suspended.
     */
    @Override
    public void onSuspended(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been resumed after a suspend.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been resumed.
     */
    @Override
    public void onResumed(CoronaRuntime runtime) {
    }

    /**
     * Called just before the Corona runtime terminates.
     * <p>
     * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
     * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
     * method is called. This does not mean that the application is exiting.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that is being terminated.
     */
    @Override
    public void onExiting(final CoronaRuntime runtime) {
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        if (coronaActivity != null) {
            Runnable runnableActivity = new Runnable() {
                public void run() {
                    // clear the saved ad objects
                    for (String key : fbObjects.keySet()) {
                        Object object = fbObjects.get(key);
                        if (object instanceof CoronaAdInstance) {
                            CoronaAdInstance adInstance = (CoronaAdInstance) object;
                            adInstance.dealloc();
                        }
                    }
                    fbObjects.clear();

                    CoronaLua.deleteRef(runtime.getLuaState(), coronaListener);
                    coronaListener = CoronaLua.REFNIL;

                    validAdTypes.clear();
                    validBannerPositions.clear();

                    coronaRuntimeTaskDispatcher = null;
                }
            };

            coronaActivity.runOnUiThread(runnableActivity);
        }
    }

    // --------------------------------------------------------------------------
    // helper functions
    // --------------------------------------------------------------------------

    // log message to console
    private void logMsg(String msgType, String errorMsg) {
        String functionID = functionSignature;
        if (!functionID.isEmpty()) {
            functionID += ", ";
        }

        Log.i(CORONA_TAG, msgType + functionID + errorMsg);
    }

    // return true if SDK is properly initialized
    private boolean isSDKInitialized() {
        if (coronaListener == CoronaLua.REFNIL) {
            logMsg(ERROR_MSG, "fbAudienceNetwork.init() must be called before calling other API functions");
            return false;
        }

        // have we got our placement ids from the endpoint?
        if (!fbObjects.containsKey(SDKREADY_KEY)) {
            return false; // handle edge case where a user has exited the app just before an API call
        } else {
            if (!(boolean) fbObjects.get(SDKREADY_KEY)) {
                logMsg(ERROR_MSG, "You must wait for the 'init' event before calling other API methods");
                return false;
            }
        }

        return true;
    }

    // dispatch a Lua event to our callback (dynamic handling of properties through map)
    private void dispatchLuaEvent(final Map<String, Object> event) {
        if (coronaRuntimeTaskDispatcher != null) {
            coronaRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
                public void executeUsing(CoronaRuntime runtime) {
                    try {
                        LuaState L = runtime.getLuaState();
                        CoronaLua.newEvent(L, EVENT_NAME);
                        boolean hasErrorKey = false;

                        // add event parameters from map
                        for (String key : event.keySet()) {
                            CoronaLua.pushValue(L, event.get(key));           // push value
                            L.setField(-2, key);                              // push key

                            if (!hasErrorKey) {
                                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
                            }
                        }

                        // add error key if not in map
                        if (!hasErrorKey) {
                            L.pushBoolean(false);
                            L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
                        }

                        // add provider
                        L.pushString(PROVIDER_NAME);
                        L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

                        CoronaLua.dispatchEvent(L, coronaListener, 0);
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            });
        }
    }

    private static class CoronaAdStatus {
        boolean isLoaded;

        CoronaAdStatus() {
            this.isLoaded = false;
        }
    }

    private static class CoronaAdInstance {
        Object adInstance;
        String adType;
        float width;
        float height;

        CoronaAdInstance(Object ad, String adType) {
            this(ad, adType, 0, 0);
        }

        CoronaAdInstance(Object ad, String adType, float width, float height) {
            this.adInstance = ad;
            this.adType = adType;
            this.width = width;
            this.height = height;
        }

        // NOTE: only safe to call on the UI thread!
        void dealloc() {
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

            if ((coronaActivity != null) && (adInstance != null)) {
                if (adInstance instanceof AdView) {
                    AdView oldBanner = (AdView) adInstance;
                    oldBanner.setVisibility(View.INVISIBLE);
                    coronaActivity.getOverlayView().removeView(oldBanner);
                    oldBanner.destroy();
                } else if (adInstance instanceof InterstitialAd) {
                    InterstitialAd oldInterstitial = (InterstitialAd) adInstance;
                    oldInterstitial.destroy();
                }

                adInstance = null;
            }
        }
    }

    // -------------------------------------------------------
    // plugin implementation
    // -------------------------------------------------------

    // [Lua] fbAudienceNetwork.init(listener [, options)
    @SuppressWarnings("SpellCheckingInspection")
    private class init implements NamedJavaFunction {
        // Gets the name of the Lua function as it would appear in the Lua script
        @Override
        public String getName() {
            return "init";
        }

        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            functionSignature = "fbAudienceNetwork.init(listener [, options)";

            // prevent init from being called twice
            if (coronaListener != CoronaLua.REFNIL) {
                logMsg(WARNING_MSG, "init() should only be called once");
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 1) || (nargs > 2)) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            String hashedId = null;
            Collection<String> hashedIds = new ArrayList<>();

            // Get listener key (required)
            if (CoronaLua.isListener(L, 1, PROVIDER_NAME)) {
                coronaListener = CoronaLua.newRef(L, 1);
            } else {
                logMsg(ERROR_MSG, "listener expected, got: " + L.typeName(1));
                return 0;
            }

            // check second parameter
            if (!L.isNoneOrNil(2)) {
                if (L.type(2) == LuaType.STRING) {
                    // Single device hashed id
                    hashedId = L.toString(2);
                } else if (L.type(2) == LuaType.TABLE) {
                    boolean legacyAPI = false;

                    for (L.pushNil(); L.next(2); L.pop(1)) {
                        if (L.type(-2) != LuaType.STRING) {
                            legacyAPI = true;
                            L.pop(2);
                            break;
                        }

                        String key = L.toString(-2);

                        if (key.equals("testDevices")) {
                            if (L.type(-1) == LuaType.STRING) {
                                hashedId = L.toString(-1);
                            } else if (L.type(-1) == LuaType.TABLE) {
                                int ntypes = L.length(-1);

                                if (ntypes > 0) {
                                    for (int i = 1; i <= ntypes; i++) {
                                        L.rawGet(-1, i);

                                        if (L.type(-1) == LuaType.STRING) {
                                            hashedIds.add(L.toString(-1));
                                        } else {
                                            logMsg(ERROR_MSG, "hashedId[" + i + "] (string) expected, got: " + L.typeName(-1));
                                            return 0;
                                        }
                                        L.pop(1);
                                    }
                                } else {
                                    logMsg(ERROR_MSG, "hashedId table cannot be empty");
                                    return 0;
                                }
                            } else {
                                logMsg(ERROR_MSG, "options.hashedId (string or table) expected, got: " + L.typeName(-1));
                                return 0;
                            }
                        } else {
                            logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                            return 0;
                        }
                    }

                    if (legacyAPI) {
                        // Multiple device hashed id's
                        int ntypes = L.length(2);

                        if (ntypes > 0) {
                            for (int i = 1; i <= ntypes; i++) {
                                L.rawGet(2, i);

                                if (L.type(-1) == LuaType.STRING) {
                                    hashedIds.add(L.toString(-1));
                                } else {
                                    logMsg(ERROR_MSG, "hashedId[" + i + "] (string) expected, got: " + L.typeName(-1));
                                    return 0;
                                }
                                L.pop(1);
                            }
                        } else {
                            logMsg(ERROR_MSG, "hashedId table cannot be empty");
                            return 0;
                        }
                    }
                } else {
                    logMsg(ERROR_MSG, "hashedId (string or table) expected, got " + L.typeName(2));
                    return 0;
                }
            }

            // set test devices
            if (hashedId != null) {
                AdSettings.addTestDevice(hashedId);
            }

            if (hashedIds.size() > 0) {
                AdSettings.addTestDevices(hashedIds);
            }

            // log the plugin version to device console
            Log.i(CORONA_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

            if (coronaActivity != null) {
                coronaActivity.runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        AudienceNetworkAds
                                .buildInitSettings(coronaActivity)
                                .withInitListener(new AudienceNetworkAds.InitListener() {
                                    @Override
                                    public void onInitialized(AudienceNetworkAds.InitResult result) {
                                        coronaActivity.runOnUiThread(new Runnable() {
                                            @Override
                                            public void run() {
                                                fbObjects.put(SDKREADY_KEY, true);
                                                // send Corona Lua event
                                                Map<String, Object> coronaEvent = new HashMap<>();
                                                coronaEvent.put(EVENT_PHASE_KEY, PHASE_INIT);
                                                dispatchLuaEvent(coronaEvent);
                                            }
                                        });
                                    }
                                })
                                .initialize();

                    }
                });
            }

            return 0;
        }
    }

    // [Lua] fbAudienceNetwork.load(adUnitType, options])
    private class load implements NamedJavaFunction {
        @Override
        public String getName() {
            return "load";
        }

        @Override
        public int invoke(final LuaState L) {
            functionSignature = "fbAudienceNetwork.load(adUnitType, options])";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 2) || (nargs > 3)) { // 3 for legacy support
                logMsg(ERROR_MSG, "Expected 2 arguments, got " + nargs);
                return 0;
            }

            String adUnitType;
            String placementId = null;
            String requestedBannerSize = BANNER_HEIGHT_50;
            boolean legacyAPI = false;

            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "adUnitType (string) expected, got " + L.typeName(1));
                return 0;
            }

            if (L.type(2) == LuaType.STRING) {
                placementId = L.toString(2);
                legacyAPI = true;
            } else if (L.type(2) == LuaType.TABLE) {
                // traverse all options
                for (L.pushNil(); L.next(2); L.pop(1)) {
                    if (L.type(-2) != LuaType.STRING) {
                        logMsg(ERROR_MSG, "options must be a key/value table");
                        return 0;
                    }

                    String key = L.toString(-2);

                    if (key.equals("placementId")) {
                        if (L.type(-1) == LuaType.STRING) {
                            placementId = L.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.placementId (string) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("bannerSize")) {
                        if (L.type(-1) == LuaType.STRING) {
                            requestedBannerSize = L.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.bannerSize (string) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else {
                logMsg(ERROR_MSG, "options (table) expected, got " + L.typeName(2));
                return 0;
            }

            if (legacyAPI) {
                // check banner size
                if (!L.isNoneOrNil(3)) {
                    if (L.type(3) == LuaType.STRING) {
                        requestedBannerSize = L.toString(3);
                    } else {
                        logMsg(ERROR_MSG, "bannerSize (string) expected, got " + L.typeName(3));
                        return 0;
                    }
                }
            }

            // validation
            if (!validAdTypes.contains(adUnitType)) {
                logMsg(ERROR_MSG, "adUnitType '" + adUnitType + "' invalid");
                return 0;
            }

            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fAdUnitType = adUnitType;
            final String fPlacementId = placementId;
            final String fRequestedBannerSize = requestedBannerSize;

            // bail if no valid activity
            if (coronaActivity == null) {
                return 0;
            }

            switch (adUnitType) {
                case TYPE_BANNER: {
                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            // deallocate the old banner
                            CoronaAdInstance oldAdInstance = (CoronaAdInstance) fbObjects.get(fPlacementId);
                            if (oldAdInstance != null) {
                                if (!oldAdInstance.adType.equals(TYPE_BANNER)) {
                                    logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' is not a banner");
                                    return;
                                }

                                oldAdInstance.dealloc();
                            }

                            // calculate the Corona->device coordinate ratio.
                            // we don't use display.contentScaleY here as there are cases where it's difficult to get the proper values to use
                            // especially on Android. uses the same formula for iOS and Android for the sake of consistency.
                            // re-calculate this value on every load as the ratio can change between orientation changes
                            Point point1 = coronaActivity.convertCoronaPointToAndroidPoint(0, 0);
                            Point point2 = coronaActivity.convertCoronaPointToAndroidPoint(1000, 1000);
                            double yRatio = (double) (point2.y - point1.y) / 1000.0;
                            fbObjects.put(Y_RATIO_KEY, yRatio);

                            AdSize bannerAdSize = AdSize.BANNER_HEIGHT_50;

                            switch (fRequestedBannerSize) {
                                case BANNER_320_50:
                                    //noinspection deprecation
                                    bannerAdSize = AdSize.BANNER_320_50;
                                    break;
                                case BANNER_HEIGHT_50:
                                    bannerAdSize = AdSize.BANNER_HEIGHT_50;
                                    break;
                                case BANNER_HEIGHT_90:
                                    bannerAdSize = AdSize.BANNER_HEIGHT_90;
                                    break;
                                case RECTANGLE_HEIGHT_250:
                                    bannerAdSize = AdSize.RECTANGLE_HEIGHT_250;
                                    break;
                                default:
                                    logMsg(WARNING_MSG, "bannerSize '" + fRequestedBannerSize + "' not valid. Using default size '" + BANNER_HEIGHT_50 + "'");
                                    break;
                            }

                            // Create the banner Ad
                            AdView bannerAd = new AdView(coronaActivity, fPlacementId, bannerAdSize);
                            bannerAd.setVisibility(View.INVISIBLE);

                            // set layout params
                            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                                    FrameLayout.LayoutParams.WRAP_CONTENT,
                                    FrameLayout.LayoutParams.WRAP_CONTENT
                            );

                            // we need to add the banner to the hierarchy temporarily in order for it to get the proper size when loading
                            // we'll remove this later in show() to set the final position
                            params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                            coronaActivity.getOverlayView().addView(bannerAd, params);

                            // save ad object for future use
                            CoronaAdInstance adInstance = new CoronaAdInstance(bannerAd, fAdUnitType, bannerAd.getWidth(), bannerAd.getHeight());
                            fbObjects.put(fPlacementId, adInstance);

                            // save extra ad status information not available in ad object
                            CoronaAdStatus adStatus = new CoronaAdStatus();
                            String statusKey = fPlacementId + STATUS_SUFFIX;
                            fbObjects.put(statusKey, adStatus);

                            bannerAd.loadAd(bannerAd.buildLoadAdConfig().withAdListener(new CoronaFBANBannerAdListener()).build());
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
                case TYPE_INTERSTITIAL: {
                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            // deallocate the old interstitial
                            CoronaAdInstance oldAdInstance = (CoronaAdInstance) fbObjects.get(fPlacementId);
                            if (oldAdInstance != null) {
                                if (!oldAdInstance.adType.equals(TYPE_INTERSTITIAL)) {
                                    logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' is not an interstitial");
                                    return;
                                }

                                oldAdInstance.dealloc();
                            }

                            // create the interstitial ad
                            InterstitialAd interstitialAd = new InterstitialAd(coronaActivity, fPlacementId);
                            // save ad object for future use
                            CoronaAdInstance adInstance = new CoronaAdInstance(interstitialAd, fAdUnitType);
                            fbObjects.put(fPlacementId, adInstance);

                            // save extra ad status information not available in ad object
                            CoronaAdStatus adStatus = new CoronaAdStatus();
                            String statusKey = fPlacementId + STATUS_SUFFIX;
                            fbObjects.put(statusKey, adStatus);

                            try {
                                interstitialAd.loadAd(interstitialAd.buildLoadAdConfig().withAdListener(new CoronaFBANInterstitialAdListener()).build());
                            } catch (Exception e) {
                                Log.e("Corona", "error loading interstitial ad", e);
                            }
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
                case TYPE_REWARDED: {
                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            // deallocate the old interstitial
                            CoronaAdInstance oldAdInstance = (CoronaAdInstance) fbObjects.get(fPlacementId);
                            if (oldAdInstance != null) {
                                if (!oldAdInstance.adType.equals(TYPE_REWARDED)) {
                                    logMsg(ERROR_MSG, "placementId '" + fPlacementId + "' is not an interstitial");
                                    return;
                                }

                                oldAdInstance.dealloc();
                            }

                            // create the interstitial ad
                            RewardedVideoAd rewardedAd = new RewardedVideoAd(coronaActivity, fPlacementId);
                            // save ad object for future use
                            CoronaAdInstance adInstance = new CoronaAdInstance(rewardedAd, fAdUnitType);
                            fbObjects.put(fPlacementId, adInstance);

                            // save extra ad status information not available in ad object
                            CoronaAdStatus adStatus = new CoronaAdStatus();
                            String statusKey = fPlacementId + STATUS_SUFFIX;
                            fbObjects.put(statusKey, adStatus);

                            rewardedAd.loadAd(rewardedAd.buildLoadAdConfig().withAdListener(new CoronaFBANRewardedAdListener(fPlacementId)).build());
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
            }

            return 0;
        }
    }

    // [Lua] fbAudienceNetwork.show(adUnitType [, options])
    private class show implements NamedJavaFunction {
        @Override
        public String getName() {
            return "show";
        }

        @Override
        public int invoke(final LuaState L) {
            functionSignature = "fbAudienceNetwork.show(adUnitType [, options])";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if ((nargs < 2) || (nargs > 3)) { // 3 for legacy support
                logMsg(ERROR_MSG, "Expected 2 arguments, got " + nargs);
                return 0;
            }

            String adUnitType;
            String placementId = null;
            String yAlign = null;
            double yOffset = 0;
            boolean legacyAPI = false;

            if (L.type(1) == LuaType.STRING) {
                adUnitType = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "adUnitType (string) expected, got " + L.typeName(1));
                return 0;
            }

            if (L.type(2) == LuaType.STRING) {
                placementId = L.toString(2);
                legacyAPI = true;
            } else if (L.type(2) == LuaType.TABLE) {
                // traverse all options
                for (L.pushNil(); L.next(2); L.pop(1)) {
                    if (L.type(-2) != LuaType.STRING) {
                        logMsg(ERROR_MSG, "options must be a key/value table");
                        return 0;
                    }

                    String key = L.toString(-2);

                    if (key.equals("placementId")) {
                        if (L.type(-1) == LuaType.STRING) {
                            placementId = L.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.placementId (string) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("y")) {
                        if (L.type(-1) == LuaType.STRING) {
                            yAlign = L.toString(-1);
                        } else if (L.type(-1) == LuaType.NUMBER) {
                            yOffset = L.toNumber(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.y (string or number) expected, got: " + L.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got " + L.typeName(2));
                return 0;
            }

            if (legacyAPI) {
                if (!L.isNoneOrNil(3)) {
                    if (L.type(3) == LuaType.TABLE) {
                        // traverse and verify all options
                        for (L.pushNil(); L.next(3); L.pop(1)) {
                            String key = L.toString(-2);

                            if (key.equals("y")) {
                                if (L.type(-1) == LuaType.NUMBER) {
                                    yOffset = L.toNumber(-1);
                                } else {
                                    logMsg(ERROR_MSG, "options.y (number) expected, got: " + L.typeName(-1));
                                    return 0;
                                }
                            } else if (key.equals("yAlign")) {
                                if (L.type(-1) == LuaType.STRING) {
                                    yAlign = L.toString(-1);
                                } else {
                                    logMsg(ERROR_MSG, "options.yAlign (string) expected, got: " + L.typeName(-1));
                                    return 0;
                                }
                            } else {
                                logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                                return 0;
                            }
                        }
                    } else {
                        logMsg(ERROR_MSG, "options (table) expected, got " + L.typeName(3));
                        return 0;
                    }
                }
            }

            // validation
            if (!validAdTypes.contains(adUnitType)) {
                logMsg(ERROR_MSG, "adUnitType '" + adUnitType + "' invalid");
                return 0;
            }

            if (yAlign != null) {
                if (!validBannerPositions.contains(yAlign)) {
                    logMsg(ERROR_MSG, "yAlign '" + yAlign + "' invalid");
                    return 0;
                }
            }

            // get ad info
            final CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(placementId);
            if (adInstance == null) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' not loaded");
                return 0;
            }

            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fPlacementId = placementId;
            final String fYAlign = yAlign;
            final double fYOffset = yOffset;

            // bail if no valid activity
            if (coronaActivity == null) {
                return 0;
            }

            switch (adUnitType) {
                case TYPE_BANNER: {
                    if (!adInstance.adType.equals(TYPE_BANNER)) {
                        logMsg(ERROR_MSG, "placementId '" + placementId + "' is not a banner");
                        return 0;
                    }

                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            AdView bannerAd = (AdView) adInstance.adInstance;
                            String statusKey = bannerAd.getPlacementId() + STATUS_SUFFIX;
                            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);

                            if (adStatus == null || !adStatus.isLoaded) {
                                logMsg(ERROR_MSG, "banner placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            // remove old layout
                            if (bannerAd.getParent() != null) {
                                coronaActivity.getOverlayView().removeView(bannerAd);
                            }

                            // set final layout params
                            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                                    FrameLayout.LayoutParams.WRAP_CONTENT,
                                    FrameLayout.LayoutParams.WRAP_CONTENT
                            );

                            // set the banner position
                            if (fYAlign == null) {
                                Display display = coronaActivity.getWindowManager().getDefaultDisplay();
                                int orientation = coronaActivity.getResources().getConfiguration().orientation;
                                int orientedHeight;

                                Point size = new Point();
                                display.getSize(size);

                                if (orientation == ORIENTATION_PORTRAIT) {
                                    orientedHeight = size.y;
                                } else {
                                    //noinspection SuspiciousNameCombination
                                    orientedHeight = size.x;
                                }

                                double newBannerY = ceil(fYOffset * (double) fbObjects.get(Y_RATIO_KEY));

                                // make sure the banner frame is visible.
                                // adjust it if the user has specified 'y' which will render it partially off-screen
                                if (newBannerY >= 0) { // offset from top
                                    if (newBannerY + bannerAd.getHeight() > orientedHeight) {
                                        logMsg(WARNING_MSG, "Banner y position off screen. Adjusting position.");
                                        params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                    } else {
                                        params.gravity = Gravity.TOP | Gravity.CENTER;
                                        params.topMargin = (int) newBannerY;
                                    }
                                } else { // offset from bottom
                                    if (orientedHeight - bannerAd.getHeight() + newBannerY < 0) {
                                        logMsg(WARNING_MSG, "Banner y position off screen. Adjusting position.");
                                        params.gravity = Gravity.TOP | Gravity.CENTER;
                                    } else {
                                        params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                        params.bottomMargin = Math.abs((int) newBannerY);
                                    }
                                }
                            } else {
                                switch (fYAlign) {
                                    case BANNER_ALIGN_TOP:
                                        params.gravity = Gravity.TOP | Gravity.CENTER;
                                        break;
                                    case BANNER_ALIGN_CENTER:
                                        params.gravity = Gravity.CENTER;
                                        break;
                                    case BANNER_ALIGN_BOTTOM:
                                        params.gravity = Gravity.BOTTOM | Gravity.CENTER;
                                        break;
                                }
                            }

                            // display the banner
                            coronaActivity.getOverlayView().addView(bannerAd, params);
                            bannerAd.setVisibility(View.VISIBLE);
                            bannerAd.bringToFront();
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
                case TYPE_INTERSTITIAL: {
                    if (!adInstance.adType.equals(TYPE_INTERSTITIAL)) {
                        logMsg(ERROR_MSG, "placementId '" + placementId + "' is not an interstitial");
                        return 0;
                    }

                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            InterstitialAd interstitialAd = (InterstitialAd) adInstance.adInstance;

                            String statusKey = interstitialAd.getPlacementId() + STATUS_SUFFIX;
                            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);

                            // we're using our own adStatus.isLoaded also since the built-in one doesn't always reflect the truth
                            if ((!adStatus.isLoaded) || (!interstitialAd.isAdLoaded())) {
                                logMsg(ERROR_MSG, "interstitial placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            interstitialAd.show();
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
                case TYPE_REWARDED: {
                    if (!adInstance.adType.equals(TYPE_REWARDED)) {
                        logMsg(ERROR_MSG, "placementId '" + placementId + "' is not an interstitial");
                        return 0;
                    }

                    Runnable runnableActivity = new Runnable() {
                        public void run() {
                            RewardedVideoAd rewardedAd = (RewardedVideoAd) adInstance.adInstance;

                            String statusKey = rewardedAd.getPlacementId() + STATUS_SUFFIX;
                            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);

                            // we're using our own adStatus.isLoaded also since the built-in one doesn't always reflect the truth
                            if (adStatus == null || !adStatus.isLoaded || !rewardedAd.isAdLoaded()) {
                                logMsg(ERROR_MSG, "interstitial placementId '" + fPlacementId + "' not loaded");
                                return;
                            }

                            rewardedAd.show();
                        }
                    };

                    coronaActivity.runOnUiThread(runnableActivity);
                    break;
                }
            }

            return 0;
        }
    }

    // [Lua] fbAudienceNetwork.hide(placementId) - For banner Ads only
    private class hide implements NamedJavaFunction {
        @Override
        public String getName() {
            return "hide";
        }

        @Override
        public int invoke(LuaState L) {
            functionSignature = "fbAudienceNetwork.hide(placementId)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String placementId;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got " + L.typeName(1));
                return 0;
            }

            // get ad info
            CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(placementId);
            if (adInstance == null) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' not loaded");
                return 0;
            }

            // only banners can be hidden
            if (!adInstance.adType.equals(TYPE_BANNER)) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' is not a banner");
                return 0;
            }

            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final CoronaAdInstance fAdInstance = adInstance;
            final String fPlacementId = placementId;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        fAdInstance.dealloc();
                        fbObjects.remove(fPlacementId);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] fbAudienceNetwork.isLoaded(placementId)
    private class isLoaded implements NamedJavaFunction {
        @Override
        public String getName() {
            return "isLoaded";
        }

        @Override
        public int invoke(LuaState L) {
            functionSignature = "fbAudienceNetwork.isLoaded(placementId)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String placementId;
            boolean isAdLoaded = false;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got " + L.typeName(1));
                return 0;
            }

            // get ad info
            CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(placementId);

            if (adInstance != null) {
                switch (adInstance.adType) {
                    case TYPE_BANNER: {
                        AdView bannerAd = (AdView) adInstance.adInstance;
                        String statusKey = bannerAd.getPlacementId() + STATUS_SUFFIX;
                        CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
                        isAdLoaded = adStatus.isLoaded;
                        break;
                    }
                    case TYPE_INTERSTITIAL: {
                        InterstitialAd interstitialAd = (InterstitialAd) adInstance.adInstance;
                        String statusKey = interstitialAd.getPlacementId() + STATUS_SUFFIX;
                        CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
                        isAdLoaded = (adStatus.isLoaded && interstitialAd.isAdLoaded());
                        break;
                    }
                    case TYPE_REWARDED: {
                        RewardedVideoAd interstitialAd = (RewardedVideoAd) adInstance.adInstance;
                        String statusKey = interstitialAd.getPlacementId() + STATUS_SUFFIX;
                        CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
                        if (adStatus != null) {
                            isAdLoaded = (adStatus.isLoaded && interstitialAd.isAdLoaded());
                        }
                        break;
                    }
                }
            }

            L.pushBoolean(isAdLoaded);

            return 1;
        }
    }

    // [Lua] fbAudienceNetwork.getSize(placementId)
    private class getSize implements NamedJavaFunction {
        @Override
        public String getName() {
            return "getSize";
        }

        @Override
        public int invoke(LuaState L) {
            functionSignature = "fbAudienceNetwork.getSize(placementId)";

            if (!isSDKInitialized()) {
                return 0;
            }

            // check number of arguments
            int nargs = L.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String placementId;
            double width;
            double height;

            if (L.type(1) == LuaType.STRING) {
                placementId = L.toString(1);
            } else {
                logMsg(ERROR_MSG, "placementId (string) expected, got " + L.typeName(1));
                return 0;
            }

            // get ad info
            CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(placementId);
            if (adInstance == null) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' not loaded");
                return 0;
            }

            // getSize only works with banners
            if (!adInstance.adType.equals(TYPE_BANNER)) {
                logMsg(ERROR_MSG, "placementId '" + placementId + "' is not a banner");
                return 0;
            }

            width = Math.floor(adInstance.width / (double) fbObjects.get(Y_RATIO_KEY));
            height = Math.floor(adInstance.height / (double) fbObjects.get(Y_RATIO_KEY));

            // Push the width/height of the Ad
            L.pushNumber(Math.round(width));
            L.pushNumber(Math.round(height));

            return 2;
        }
    }

    // ----------------------------------------------------------------------------
    // delegate implementation
    // ----------------------------------------------------------------------------

    // Banner delegates

    private class CoronaFBANBannerAdListener implements AdListener {
        @Override
        public void onError(Ad ad, AdError error) {
            String statusKey = ad.getPlacementId() + STATUS_SUFFIX;
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
            if (adStatus != null) {
                adStatus.isLoaded = false;
            }

            String errorMsg = "Error Code: " + error.getErrorCode() + ". Reason: " + error.getErrorMessage();

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_BANNER);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
            coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, errorMsg);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onAdLoaded(Ad ad) {
            String statusKey = ad.getPlacementId() + STATUS_SUFFIX;
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
            final CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(ad.getPlacementId());
            if (adStatus != null) {
                adStatus.isLoaded = true;
            }

            final AdView bannerAd = (AdView) ad;
            String phase = (bannerAd.getVisibility() == View.INVISIBLE) ? PHASE_LOADED : PHASE_REFRESHED;

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, phase);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_BANNER);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            dispatchLuaEvent(coronaEvent);

            // save loaded ad size
            bannerAd.post(new Runnable() {
                @Override
                public void run() {
                    adInstance.width = bannerAd.getWidth();
                    adInstance.height = bannerAd.getHeight();
                }
            });
        }

        @Override
        public void onAdClicked(Ad ad) {
            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_BANNER);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onLoggingImpression(Ad ad) {
            // NOP
        }
    }


    private class CoronaFBANRewardedAdListener implements RewardedVideoAdListener {
        String userPlacement;

        CoronaFBANRewardedAdListener(String userPlacement) {
            this.userPlacement = userPlacement;
        }

        void FinishAd() {
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(userPlacement + STATUS_SUFFIX);
            if (adStatus != null) {
                adStatus.isLoaded = false;
            }
        }

        @Override
        public void onError(Ad ignore, AdError error) {
            FinishAd();

            String errorMsg = "Error Code: " + error.getErrorCode() + ". Reason: " + error.getErrorMessage();

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, userPlacement);
            coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
            coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, errorMsg);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onAdLoaded(Ad ignore) {
            CoronaAdStatus adInstance = (CoronaAdStatus) fbObjects.get(userPlacement + STATUS_SUFFIX);
            if (adInstance == null) return;
            adInstance.isLoaded = true;

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, userPlacement);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onAdClicked(Ad ignore) {
            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, userPlacement);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onRewardedVideoCompleted() {
            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_REWARD);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDED);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, userPlacement);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onLoggingImpression(Ad ad) {

        }

        @Override
        public void onRewardedVideoClosed() {
            FinishAd();

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, userPlacement);
            dispatchLuaEvent(coronaEvent);
        }
    }

    // ----------------------------------------------------------------------------
    // Interstitial delegates

    private class CoronaFBANInterstitialAdListener implements InterstitialAdListener {
        @Override
        public void onError(Ad ad, AdError error) {
            String statusKey = ad.getPlacementId() + STATUS_SUFFIX;
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
            if (adStatus != null)
                adStatus.isLoaded = false;

            String errorMsg = "Error Code: " + error.getErrorCode() + ". Reason: " + error.getErrorMessage();

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
            coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, errorMsg);
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onAdLoaded(Ad ad) {
            String statusKey = ad.getPlacementId() + STATUS_SUFFIX;
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
            CoronaAdInstance adInstance = (CoronaAdInstance) fbObjects.get(ad.getPlacementId());
            if (adStatus != null)
                adStatus.isLoaded = true;

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            dispatchLuaEvent(coronaEvent);

        }

        @Override
        public void onAdClicked(Ad ad) {
            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onInterstitialDisplayed(Ad ad) {
            // NOP
            // Not available on iOS
        }

        @Override
        public void onInterstitialDismissed(Ad ad) {
            String statusKey = ad.getPlacementId() + STATUS_SUFFIX;
            CoronaAdStatus adStatus = (CoronaAdStatus) fbObjects.get(statusKey);
            if (adStatus != null)
                adStatus.isLoaded = false;

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_PLACEMENTID_KEY, ad.getPlacementId());
            dispatchLuaEvent(coronaEvent);
        }

        @Override
        public void onLoggingImpression(Ad ad) {
            // NOP
        }
    }
}
