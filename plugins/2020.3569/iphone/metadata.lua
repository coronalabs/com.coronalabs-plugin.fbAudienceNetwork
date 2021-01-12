local metadata =
{
	plugin =
	{
		format = 'staticLibrary',
		staticLibs = { 'xml2', 'FBAudienceNetworkPlugin' },
		frameworks = { 'FBAudienceNetwork', 'FBSDKCoreKit', },
		frameworksOptional = { 'VideoToolbox', 'Accelerate', },
		usesSwift = true,
	},
}

return metadata
