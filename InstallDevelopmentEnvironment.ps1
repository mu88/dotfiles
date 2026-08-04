choco feature enable --name=useRememberedArgumentsForUpgrades 

[Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "true", [System.EnvironmentVariableTarget]::User)

# Browsers
choco install firefox -y
choco install googlechrome -y
choco install tor-browser -y

# Container
choco install docker-desktop -y
choco install go-containerregistry -y

# Version Control System
choco install git -y
choco install winmerge -y
choco install gitextensions -y
choco install gh -y
gh extension install github/gh-stack

# AI
choco install github-copilot-cli -y
copilot skill install github/gh-stack
copilot plugin marketplace add dotnet/modernize-dotnet
copilot plugin install modernize-dotnet@modernize-dotnet-plugins
copilot plugin marketplace add dotnet/skills
copilot plugin install dotnet@dotnet-agent-skills
copilot plugin install dotnet-advanced@dotnet-agent-skills
copilot plugin install dotnet-ai@dotnet-agent-skills
copilot plugin install dotnet-aspnetcore@dotnet-agent-skills
copilot plugin install dotnet-blazor@dotnet-agent-skills
copilot plugin install dotnet-data@dotnet-agent-skills
copilot plugin install dotnet-diag@dotnet-agent-skills
copilot plugin install dotnet-msbuild@dotnet-agent-skills
copilot plugin install dotnet-nuget@dotnet-agent-skills
copilot plugin install dotnet-upgrade@dotnet-agent-skills
copilot plugin install dotnet-template-engine@dotnet-agent-skills
copilot plugin install dotnet-test@dotnet-agent-skills
copilot plugin install dotnet-test-migration@dotnet-agent-skills
copilot plugin install dotnet11@dotnet-agent-skills

# IDE and essential development
choco install nodejs -y
choco install dotnet-sdk -y
choco install notepadplusplus -y
choco install vscode -y
choco install visualstudio2026professional -y --params "--locale en-US --add Microsoft.VisualStudio.Workload.NetCrossPlat --add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.ManagedDesktop"
choco install jetbrainstoolbox -y # consider adding '--ia "/D=C:\new\path"' as otherwise the toolbox will be installed to %LOCALAPPDATA%

# Additional development tools
choco install act-cli -y
choco install msbuild-structured-log-viewer -y
choco install nunit-console-runner -y
choco install nuget.commandline -y
choco install nugetpackageexplorer -y

# Shell / Terminal
choco install microsoft-windows-terminal -y
choco install powershell-core -y
choco install firacode -y
choco install firacodenf -y
choco install oh-my-posh -y
choco install terminal-icons.powershell -y
choco install psmux -y

# Web development / network analysis
choco install fiddler -y
choco install postman -y
choco install wireshark -y
choco install winpcap -y

# Cloud tools
choco install awscli -y
choco install kustomize -y
choco install az.powershell -y
choco install azd -y
choco install azure-cli -y

# Database Tools
choco install sql-server-management-studio -y
choco install pgadmin4 -y
choco install sqlitebrowser -y

# Helpers
choco install 7zip -y
choco install agentransack -y
choco install ditto -y
choco install eraser -y
choco install joplin -y
choco install keepass -y
choco install keepass-plugin-kpscript -y
choco install bitwarden --ia '/allusers' -y
[Environment]::SetEnvironmentVariable("BITWARDEN_NO_UPDATER", "1", [System.EnvironmentVariableTarget]::User)
[Environment]::SetEnvironmentVariable("ELECTRON_NO_UPDATER", "1", [System.EnvironmentVariableTarget]::User)
choco install bitwarden-cli --ia '/allusers' -y
choco install paint.net -y
choco install pdfcreator -y
choco install powertoys -y
choco install screenpresso -y
choco install sysinternals -y
choco install veracrypt -y
choco install vlc -y
choco install windirstat -y
choco install winscp -y

# Others
choco install stretchly -y

Install-Module PSReadLine -AllowPrerelease -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module posh-git -Scope CurrentUser
