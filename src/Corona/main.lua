--
--  main.lua
--  Facebook Audience Network Sample App
--
--  Copyright (c) 2017 Corona Labs Inc. All rights reserved.
--

local fban = require("plugin.fbAudienceNetwork.paid")
local widget = require("widget")
local json = require("json")

local appStatus = {
    customYTest = false,                -- adds UI elements to test custom Y positioning
    useAndroidImmersive = false,        -- sets android ui visibility to immersiveSticky to test hidden UI bar
    useLegacyAPI = false                -- use legacy API for function calls
}

--------------------------------------------------------------------------
-- set up UI
--------------------------------------------------------------------------

display.setStatusBar( display.HiddenStatusBar )
display.setDefault( "background", 1 )
if appStatus.useAndroidImmersive then
    native.setProperty( "androidSystemUiVisibility", "immersiveSticky")
end

local fbanLogo = display.newImage( "fbanlogo.png" )
fbanLogo.anchorY = 0
fbanLogo:scale( 0.17, 0.17 )

local setRed = function(self)
    self:setFillColor(1,0,0)
end

local setGreen = function(self)
    self:setFillColor(0,1,0)
end

local r1
local r2
local oldOrientation

if (appStatus.customYTest) then
    r1 = display.newRect(0,0,50,50)
    r1.anchorX, r1.anchorY = 0, 0
    setRed(r1)
    r2 = display.newRect(0,0,50,50)
    r2.anchorX, r2.anchorY = 1, 1
    setRed(r2)
end

local subTitle = display.newText {
    text = "plugin for Corona SDK",
    font = display.systemFont,
    fontSize = 14
}
subTitle:setTextColor( 66/255, 88/255, 148/255 )

eventDataTextBox = native.newTextBox( display.contentCenterX, display.contentHeight - 50, display.contentWidth - 10, 100)
eventDataTextBox.placeholder = "Event data will appear here"
eventDataTextBox.hasBackground = false

local processEventTable = function(event)
    local logString = json.prettify(event):gsub("\\","")
    logString = "\nPHASE: "..event.phase.." - - - - - - - - - \n" .. logString
    print(logString)
    eventDataTextBox.text = logString .. eventDataTextBox.text
end

-- --------------------------------------------------------------------------
-- -- plugin implementation
-- --------------------------------------------------------------------------

-- forward declarations
local appId = "n/a"
local adUnits = {}
local platformName = system.getInfo("platformName")
local testMode = true
local testModeButton
local showTestWarning = true
local iReady
local bReady
local rReady
local bannerLine

local placementIds = {
    banner       = "407318409718485_429989937451332",   -- Kirill's FB placements
    banner2      = "407318409718485_429989787451347",
    interstitial = "407318409718485_429989387451387",
    rewarded = "407318409718485_719665225150467",
}

print("Placements: "..json.prettify(placementIds))

local fbanListener = function(event)
    processEventTable(event)

    if (event.phase == "loaded") then
        if (event.type == "interstitial") then
            setGreen(iReady)
        elseif (event.type == "banner") then
            setGreen(bReady)
        elseif (event.type == "rewardedVideo") then
            setGreen(rReady)
        end
    end
end

local deviceHashes = {
    "84e999bc18567d4e1eea4dd8dec0a68f6737c080", -- Devpod 6G (Ingemar)
    "0250249fe64b912160b99ed0522aad1e55ac3de1", -- Devphone 4s (Ingemar)
    "a4b089b24169f73201c876b4c5244dc5",         -- Galaxy S III (Ingemar)
    "b9309f2a8c53527a1a77dec4eb832966" ,         -- Nexus 7
}

-- initialize FBAN
if (appStatus.useLegacyAPI) then
    fban.init(fbanListener, deviceHashes)
else
    fban.init(fbanListener, {testDevices=deviceHashes})
end

local interstitialBG = display.newRect(0,0,320,30)

local interstitialLabel = display.newText {
    text = "I N T E R S T I T I A L",
    font = display.systemFontBold,
    fontSize = 18,
}
interstitialLabel:setTextColor(1)

local loadInterstitialButton = widget.newButton {
    label = "Load",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(iReady)
        if (appStatus.useLegacyAPI) then
            fban.load("interstitial", placementIds.interstitial)
        else
            fban.load("interstitial", {placementId=placementIds.interstitial})
        end
    end
}

local showInterstitialButton = widget.newButton {
    label = "Show",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(iReady)
        print("interstitial is loaded: ", fban.isLoaded(placementIds.interstitial))
        if (appStatus.useLegacyAPI) then
            fban.show("interstitial", placementIds.interstitial)
        else
            fban.show("interstitial", {placementId=placementIds.interstitial})
        end
    end
}



local rewardedBG = display.newRect(0,0,320,30)

local rewardedLabel = display.newText {
    text = "R E W A R D E D",
    font = display.systemFontBold,
    fontSize = 18,
}
rewardedLabel:setTextColor(1)

local loadrewardedButton = widget.newButton {
    label = "Load",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(rReady)
        if (appStatus.useLegacyAPI) then
            fban.load("rewardedVideo", placementIds.rewarded)
        else
            fban.load("rewardedVideo", {placementId=placementIds.rewarded})
        end
    end
}

local showrewardedButton = widget.newButton {
    label = "Show",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(rReady)
        print("rewarded is loaded: ", fban.isLoaded(placementIds.rewarded))
        if (appStatus.useLegacyAPI) then
            fban.show("rewardedVideo", placementIds.rewarded)
        else
            fban.show("rewardedVideo", {placementId=placementIds.rewarded})
        end
    end
}



local bannerBG = display.newRect(0,0,320,30)

local bannerLabel = display.newText {
    text = "B A N N E R",
    font = display.systemFontBold,
    fontSize = 18,
}
bannerLabel:setTextColor(1)

local loadBannerButton = widget.newButton {
    label = "Load",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(bReady)
        if (appStatus.useLegacyAPI) then
            fban.load("banner", placementIds.banner, "BANNER_HEIGHT_50")
        else
            fban.load("banner", {placementId=placementIds.banner, bannerSize="BANNER_HEIGHT_50"})
        end
    end
}

local hideBannerButton = widget.newButton {
    label = "Hide",
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        setRed(bReady)
        fban.hide(placementIds.banner)
    end
}

local showBannerButtonT = widget.newButton {
    label = "Top",
    fontSize = 14,
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        print("Banner is loaded: ", fban.isLoaded(placementIds.banner))
        print("Banner size: ", fban.getSize(placementIds.banner))
        if appStatus.customYTest then
            if (appStatus.useLegacyAPI) then
                fban.show("banner", placementIds.banner, {y=50})
            else
                fban.show("banner", {placementId=placementIds.banner, y=50})
            end
        else
            if (appStatus.useLegacyAPI) then
                fban.show("banner", placementIds.banner, {yAlign="top"})
            else
                fban.show("banner", {placementId=placementIds.banner, y="top"})
            end
        end
    end
}

local showBannerButtonB = widget.newButton {
    label = "Bottom",
    fontSize = 14,
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        print("Banner is loaded: ", fban.isLoaded(placementIds.banner))
        print("Banner size: ", fban.getSize(placementIds.banner))
        if appStatus.customYTest then
            if (appStatus.useLegacyAPI) then
                fban.show("banner", placementIds.banner, {y=-50})
            else
                fban.show("banner", {placementId=placementIds.banner, y=-50})
            end
        else
            if (appStatus.useLegacyAPI) then
                fban.show("banner", placementIds.banner, {yAlign="bottom"})
            else
                fban.show("banner", {placementId=placementIds.banner, y="bottom"})
            end
        end
    end
}

local showBannerButtonBLine = widget.newButton {
    label = "Under Line",
    fontSize = 14,
    width = 100,
    height = 40,
    labelColor = { default={ 0, 0, 0 }, over={ 0.7, 0.7, 0.7 } },
    onRelease = function(event)
        print("Banner is loaded: ", fban.isLoaded(placementIds.banner))
        print("Banner size: ", fban.getSize(placementIds.banner))
        if (appStatus.useLegacyAPI) then
            fban.show("banner", placementIds.banner, {y=72+math.abs(display.screenOriginY)})
        else
            fban.show("banner", {placementId=placementIds.banner, y=72+math.abs(display.screenOriginY)})
        end
    end
}

iReady = display.newCircle(10, 10, 6)
iReady.strokeWidth = 2
iReady:setStrokeColor(0)
setRed(iReady)

rReady = display.newCircle(10, 10, 6)
rReady.strokeWidth = 2
rReady:setStrokeColor(0)
setRed(rReady)

bReady = display.newCircle(10, 10, 6)
bReady.strokeWidth = 2
bReady:setStrokeColor(0)
setRed(bReady)

-- --------------------------------------------------------------------------
-- -- device orientation handling
-- --------------------------------------------------------------------------

local layoutDisplayObjects = function(orientation)
    fbanLogo.x, fbanLogo.y = display.contentCenterX, 0

    if (appStatus.customYTest) then
        r1.x = display.screenOriginX
        r1.y = display.screenOriginY
        r2.x = display.actualContentWidth + display.screenOriginX
        r2.y = display.actualContentHeight + display.screenOriginY
    end

    subTitle.x = display.contentCenterX
    subTitle.y = 60

    bannerLine = display.newLine( display.screenOriginX, 72, display.actualContentWidth, 72)
    bannerLine.strokeWidth = 2
    bannerLine:setStrokeColor(1,0,0)

    if (orientation == "portrait") then
        eventDataTextBox.x = display.contentCenterX
        eventDataTextBox.y = display.contentHeight - 50
        eventDataTextBox.width = display.contentWidth - 10
    else
        -- put it waaaay offscreen
        eventDataTextBox.y = 2000
    end

    interstitialBG.x, interstitialBG.y = display.contentCenterX, 150
    interstitialBG:setFillColor(66/255, 88/255, 148/255)

    interstitialLabel.x = display.contentCenterX
    interstitialLabel.y = 150

    iReady.x = display.contentCenterX + 140
    iReady.y = 150
    setRed(iReady)

    loadInterstitialButton.x = display.contentCenterX - 50
    loadInterstitialButton.y = interstitialLabel.y + 40

    showInterstitialButton.x = display.contentCenterX + 50
    showInterstitialButton.y = interstitialLabel.y + 40


    rewardedBG.x, rewardedBG.y = display.contentCenterX, 80
    rewardedBG:setFillColor(66/255, 88/255, 148/255)

    rewardedLabel.x = display.contentCenterX
    rewardedLabel.y = 80

    rReady.x = display.contentCenterX + 140
    rReady.y = 80
    setRed(rReady)

    loadrewardedButton.x = display.contentCenterX - 50
    loadrewardedButton.y = rewardedLabel.y + 40

    showrewardedButton.x = display.contentCenterX + 50
    showrewardedButton.y = rewardedLabel.y + 40

    bannerBG.x, bannerBG.y = display.contentCenterX, 220
    bannerBG:setFillColor(66/255, 88/255, 148/255 )

    bannerLabel.x = display.contentCenterX
    bannerLabel.y = 220

    bReady.x = display.contentCenterX + 140
    bReady.y = 220
    setRed(bReady)

    loadBannerButton.x = display.contentCenterX - 50
    loadBannerButton.y = bannerLabel.y + 40

    hideBannerButton.x = display.contentCenterX + 50
    hideBannerButton.y = bannerLabel.y + 40

    showBannerButtonB.x = display.contentCenterX
    showBannerButtonB.y = bannerLabel.y + 80

    showBannerButtonT.x = display.contentCenterX - 100
    showBannerButtonT.y = bannerLabel.y + 80

    showBannerButtonBLine.x = display.contentCenterX + 100
    showBannerButtonBLine.y = bannerLabel.y + 80
end

local onOrientationChange = function(event)
    local eventType = event.type
    local orientation = eventType:starts("landscape") and "landscape" or eventType

    if (orientation == "portrait") or (orientation == "landscape") then
        if (oldOrientation == nil) then
            oldOrientation = orientation
        else
            if (orientation ~= oldOrientation) then
                oldOrientation = orientation
                fban.hide(placementIds.banner)
                layoutDisplayObjects(eventType)
            end
        end
    end
end

Runtime:addEventListener("orientation", onOrientationChange)

-- initial layout
layoutDisplayObjects(system.orientation)
