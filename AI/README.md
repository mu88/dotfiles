# AI setup on Linux

Run the AI setup using PowerShell to configure Copilot, OpenCode, and RTK:

```powershell
./AI/Configure.ps1
```

The setup appends login environment settings to `~/.profile`, preserving existing content. It uses `MU88_DOTFILES` if set, otherwise the checkout containing the script. The checkout path must not contain a comma because Copilot uses commas to separate instruction directories. Install the tools separately.

Log in again before starting Copilot CLI or OpenCode from a terminal. The shell inherits these settings from the login session. Check the actual Mint desktop separately: graphical sessions and terminals started outside the login session may not inherit `~/.profile`. An already running OpenCode service retains its previous environment.

## SOFA

SOFA uses an unlocked Secret Service keyring and `secret-tool` (`libsecret-tools`). To add the API key, run the following in a terminal and enter it at the password prompt, not in the command line or chat:

```sh
secret-tool store --label='SOFA API key' application sofa credential api-key
```

This updates an existing entry with the same attributes; check the keyring first if an entry might already exist. The AI setup does not install `secret-tool` or store credentials.
