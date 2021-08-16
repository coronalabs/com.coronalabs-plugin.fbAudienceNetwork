local metadata =
{
	plugin =
	{
		format = 'staticLibrary',
		staticLibs = { 'xml2', 'z', 'FBAudienceNetworkPlugin' },
		frameworks = { 'FBAudienceNetwork', 'FBSDKCoreKit', 'FBSDKCoreKit_Basics' },
		frameworksOptional = { 'VideoToolbox', 'Accelerate', },
		usesSwift = true,
	},
}

return metadata
