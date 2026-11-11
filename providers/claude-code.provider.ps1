# Claude Code - per-user config, session transcripts, file-history snapshots,
# plugins and downloads under ~/.claude (transcripts grow without bound until
# `cleanupPeriodDays` prunes them).
#
# CLAUDE_CONFIG_DIR exists but Claude Desktop does not honour it, so the folder
# is relocated with a junction that both apps follow. Claude Desktop and Claude
# Code share the `claude` process name and keep transcripts open while running:
# migration is refused until every instance is closed.
#
# The CLI binary itself lives under ~/.local and is covered by `user-local`;
# Claude Desktop's own data sits in its MSIX package folder, which Windows moves
# with Settings > Apps > Move.
@{
    Id          = 'claude-code'
    Name        = 'Claude Code'
    Category    = 'AI'
    Description = 'Claude Code config, session transcripts, file history and plugins under ~/.claude.'
    Version     = '1.0.0'
    Detect      = @{ Commands = @('claude'); Paths = @('%USERPROFILE%\.claude') }
    Metadata    = @{ BlockingProcesses = @('claude') }
    Mappings    = @(
        @{ Source = '%USERPROFILE%\.claude'; TargetSubPath = 'ai\claude-code'; Strategy = 'Junction' }
    )
}
