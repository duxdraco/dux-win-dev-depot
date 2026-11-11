# OpenAI Codex CLI - config, SQLite state/log databases and temp workspaces
# under ~/.codex. Relocated with a junction (like the other AI providers) rather
# than CODEX_HOME, so no environment change is needed. The SQLite files are held
# open (WAL) while Codex runs, so migration is refused until it is closed.
@{
    Id          = 'codex'
    Name        = 'OpenAI Codex CLI'
    Category    = 'AI'
    Description = 'Codex CLI config, state and log databases, skills and temp workspaces under ~/.codex.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @('codex'); Paths = @('%USERPROFILE%\.codex') }
    Metadata    = @{ BlockingProcesses = @('codex') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.codex'; TargetSubPath = 'ai\codex'; Strategy = 'Junction' }
    )
}
