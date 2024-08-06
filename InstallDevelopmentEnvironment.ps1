# Browsers
choco install firefox -fy
choco install googlechrome -fy
choco install tor-browser -fy

# Container
choco install docker-desktop -fy

# Version Control System
choco install git -fy
choco install winmerge -fy
choco install gitextensions -fy
choco install gh -fy

# IDE and essential development
choco install nodejs -fy
choco install dotnet-sdk -fy
choco install notepadplusplus -fy
choco install vscode -fy
choco install visualstudio2022professional -fy --params "--locale en-US"
choco install jetbrainstoolbox -fy # consider adding '--ia "/D=C:\new\path"' as otherwise the toolbox will be installed to %LOCALAPPDATA%

# Additional development tools
choco install nunit-console-runner -fy
choco install nuget.commandline -fy
choco install nugetpackageexplorer -fy

# Shell / Terminal
choco install microsoft-windows-terminal -fy
choco install powershell-core -fy
choco install firacode -fy
choco install firacodenf -fy
choco install oh-my-posh

# Web development / network analysis
choco install fiddler -fy
choco install postman -fy
choco install wireshark -fy
choco install winpcap -fy

# Cloud tools
choco install awscli -fy
choco install kustomize -fy

# Database Tools
choco install sql-server-management-studio -fy
choco install pgadmin4 -fy
choco install sqlitebrowser -fy

# Helpers
choco install 7zip -fy
choco install agentransack -fy
choco install ditto -fy
choco install eraser -fy
choco install joplin -fy
choco install keepass -fy
choco install keepass-plugin-kpscript -fy
choco install paint.net -fy
choco install pdfcreator -fy
choco install powertoys -fy
choco install screenpresso -fy
choco install sysinternals -fy
choco install veracrypt -fy
choco install vlc -fy
choco install windirstat -fy
choco install winscp -fy

# Others
choco install stretchly -fy

Install-Module PSReadLine -AllowPrerelease -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module posh-git -Scope CurrentUser
Install-Module Terminal-Icons -Repository PSGallery
