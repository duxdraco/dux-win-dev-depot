# Installation

## Requirements

- **PowerShell 7.0+** (`pwsh`). Windows PowerShell 5.1 is not supported.
- **Windows 10 or 11.**
- Administrator rights are only needed for machine-scope environment variables (optional).

Check your PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

If you don't have PowerShell 7, install it with winget:

```powershell
winget install Microsoft.PowerShell
```

## Get DevDepot

Clone the repository — there is no build step:

```powershell
git clone https://github.com/duxdraco/dux-win-dev-depot.git
cd dux-win-dev-depot
```

Alternatively, download the latest packaged release from the
[Releases page](https://github.com/duxdraco/dux-win-dev-depot/releases) and extract it.

## Execution policy

If script execution is restricted, allow it for the current process only (this does not
change your machine-wide policy):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Verify

```powershell
pwsh -File .\DevDepot.ps1 version
pwsh -File .\DevDepot.ps1 analyze   # read-only
```

`analyze` never changes anything — it's a safe way to confirm DevDepot runs and to see what
it would migrate. Continue to the [Quick start](quick-start.md).
