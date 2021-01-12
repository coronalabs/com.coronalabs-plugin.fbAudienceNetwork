local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest = 
        {
            permissions = {},
            usesPermissions =
            {
            },
            usesFeatures = 
            {
            },
            applicationChildElements =
            {
            }
        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.android.support.annotations"] = "com.coronalabs",
        }
    }
}

return metadata
