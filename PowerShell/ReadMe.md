# Configure PowerShell

Do the following to use the settings from this directory:
- Add the following to your PowerShell profile (e.g. via `code $PROFILE`):

```powershell
if ($env:MU88_DOTFILES) {
    $mu88_profileScript = Join-Path $env:MU88_DOTFILES (Join-Path "PowerShell" "Microsoft.PowerShell_profile.ps1")
    & $mu88_profileScript
}
```