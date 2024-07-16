# Configure PowerShell

Do the following to use the settings from this directory:
- Set environment variable `MU88_DOTFILES` for current user to the directory of this cloned repo.
- Add the following to your PowerShell profile (e.g. via `code $PROFILE`):

```powershell
if ($env:MU88_DOTFILES) {
    $mu88_profileScript = Join-Path $env:MU88_DOTFILES (Join-Path "PowerShell" "Microsoft.PowerShell_profile.ps1")
    & $mu88_profileScript
}
```