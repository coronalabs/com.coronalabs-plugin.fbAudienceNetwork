-- Facebook Audience Network plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.fbAudienceNetwork", publisherId="com.coronalabs", version=2 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local fan = require "plugin.fan"
--    fan.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The Facebook Audience Network plugin is only supported on Android & iOS devices. Please build for device")
end

function lib.init()
    showWarning("fbAudienceNetwork.init()")
end

function lib.load()
    showWarning("fbAudienceNetwork.load()")
end

function lib.isLoaded()
    showWarning("fbAudienceNetwork.isLoaded()")
end

function lib.show()
    showWarning("fbAudienceNetwork.show()")
end

function lib.hide()
    showWarning("fbAudienceNetwork.hide()")
end

function lib.getSize()
    showWarning("fbAudienceNetwork.getSize()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
