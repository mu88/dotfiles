# Browsers
choco install firefox -y
choco install googlechrome -y
choco install tor-browser -y

# Container
choco install docker-desktop -y

# Version Control System
choco install git -y
choco install winmerge -y
choco install gitextensions -y
choco install gh -y

# IDE and essential development
choco install nodejs -y
choco install dotnet-sdk -y
choco install notepadplusplus -y
choco install vscode -y
choco install visualstudio2022professional -y --params "--locale en-US"
choco install jetbrainstoolbox -y # consider adding '--ia "/D=C:\new\path"' as otherwise the toolbox will be installed to %LOCALAPPDATA%

# Additional development tools
choco install nunit-console-runner -y
choco install nuget.commandline -y
choco install nugetpackageexplorer -y

# Shell / Terminal
choco install microsoft-windows-terminal -y
choco install powershell-core -y
choco install firacode -y
choco install firacodenf -y
choco install oh-my-posh

# Web development / network analysis
choco install fiddler -y
choco install postman -y
choco install wireshark -y
choco install winpcap -y

# Cloud tools
choco install awscli -y
choco install kustomize -y

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
Install-Module Terminal-Icons -Repository PSGallery
