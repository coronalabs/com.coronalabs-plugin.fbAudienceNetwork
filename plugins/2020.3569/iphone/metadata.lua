local metadata =
{
	plugin =
	{
		format = 'staticLibrary',
		staticLibs = {"FBAudienceNetworkPlugin", "z", },
		frameworks = { 'Accounts', "FBAudienceNetwork", 'FBSDKCoreKit',  'FBSDKLoginKit', 'FBSDKShareKit', 'FBSDKCoreKit_Basics', "FBAEMKit", "Accelerate"},
		frameworksOptional = { "AdSupport", },
		delegates = { },
		usesSwift = true,
	},
}

return metadata
