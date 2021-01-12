//
//  FBAudienceNetworkPaidLibrary.h
//  Facebook Audience Network Plugin
//
//  Copyright (c) 2015 CoronaLabs Inc. All rights reserved.
//

#ifndef _FBAudienceNetworkPaidLibrary_H__
#define _FBAudienceNetworkPaidLibrary_H__

#include "CoronaLua.h"
#include "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_fbAudienceNetwork_paid( lua_State *L );
CORONA_EXPORT int luaopen_plugin_fbAudienceNetwork( lua_State *L );

#endif // _FBAudienceNetworkPaidLibrary_H__
