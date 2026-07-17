@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # Providers intentionally emit a hashtable as their last statement.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    Rules = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; Kind = 'space'; IndentationSize = 4 }
    }
}
