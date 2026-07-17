@{
    RootModule        = 'modules\DevDepot.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a3f1c0de-1d2e-4b6a-9c7f-devdepot00001'
    Author            = 'DevDepot contributors'
    CompanyName       = 'DevDepot'
    Copyright         = '(c) DevDepot contributors. MIT License.'
    Description       = 'Migrate developer caches, SDKs and package repositories off the Windows system drive.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Import-DevDepotCore')
    PrivateData       = @{
        PSData = @{
            Tags         = @('Windows', 'DevOps', 'Cache', 'Migration', 'SDK', 'Cleanup')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'v0.1.0 - first usable release: transactional migration engine, state DB, 13 Java/Node/.NET/Python cache providers, analyze/install/rollback CLI.'
        }
    }
}
