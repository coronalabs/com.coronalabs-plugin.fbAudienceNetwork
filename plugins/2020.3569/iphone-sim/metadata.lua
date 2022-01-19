local metadata =
{
	plugin =
	{
		format = 'staticLibrary',
		staticLibs = {"FBAudienceNetworkPlugin"},
		frameworks = { 'Accounts', "FBAudienceNetwork", 'FBSDKCoreKit',  'FBSDKLoginKit', 'FBSDKShareKit', 'FBSDKCoreKit_Basics', "FBAEMKit", "Accelerate"},
		frameworksOptional = {},
		delegates = { },
		usesSwift = true,
	},
}

return metadata
