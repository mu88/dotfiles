$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Clear-Host

# Helper: Get GitHub token
function Get-GitHubToken {
	$token = gh auth token 2>$null
	if (-not $token) {
		Write-Error "Could not retrieve GitHub token via gh CLI."
		exit 1
	}
	return $token
}

function Disable-Wiki {
	param($repo)
	Write-Host "Disabling Wikis..."
	gh api -X PATCH "/repos/$repo" -f has_wiki=false
}

function Enable-Issues {
	param($repo)
	Write-Host "Enabling Issues..."
	gh api -X PATCH "/repos/$repo" -f has_issues=true
}

function Enable-Discussions {
	param($repo)
	Write-Host "Enabling Discussions..."
	gh api -X PATCH "/repos/$repo" -f has_discussions=true
}

function Configure-PRMergeSettings {
	param($repo)
	Write-Host "Configuring PR merge settings..."
	gh api -X PATCH "/repos/$repo" -f allow_merge_commit=false -f allow_squash_merge=false -f allow_rebase_merge=true
}

function Enable-UpdateBranchSuggestion {
	param($repo)
	Write-Host "Enabling 'Always suggest updating pull request branches'..."
	gh api -X PATCH "/repos/$repo" -f allow_update_branch=true
}

function Enable-AutoMerge {
	param($repo)
	Write-Host "Enabling 'Allow auto-merge'..."
	gh api -X PATCH "/repos/$repo" -f allow_auto_merge=true
}

function Enable-DeleteHeadBranches {
	param($repo)
	Write-Host "Enabling 'Automatically delete head branches'..."
	gh api -X PATCH "/repos/$repo" -f delete_branch_on_merge=true
}

function Configure-Rulesets {
	param($repo)
	$rulesetsPath = Join-Path $PSScriptRoot 'Rulesets'
	if (Test-Path $rulesetsPath) {
		$token = Get-GitHubToken
		Get-ChildItem -Path $rulesetsPath -Filter *.json | ForEach-Object {
			$rulesetJson = Get-Content $_.FullName -Raw
			Write-Host "Applying ruleset: $($_.Name) ..."
			$uri = "https://api.github.com/repos/$repo/rulesets"
			$headers = @{ Authorization = "token $token"; Accept = "application/vnd.github+json" }
			$body = $rulesetJson
			$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
			Write-Host "Ruleset $($_.Name) applied."
		}
	} else {
		Write-Warning "Rulesets folder not found. Skipping ruleset configuration."
	}
}

function Ask-EnableRenovate {
	$enableRenovate = Read-Host "Do you want to enable Renovate for this repository? (y/n)"
	if ($enableRenovate -eq 'y') {
		Write-Host "Navigate to https://github.com/settings/installations/29694880 to enable Renovate."
		Start-Process "https://github.com/settings/installations/29694880"
	}
}

function Ask-CreateSonarToken {
	param($repo)
	$enableSonar = Read-Host "Do you want to create a SonarQube token for GitHub Actions? (y/n)"
	if ($enableSonar -eq 'y') {
		$sonarToken = Read-Host -AsSecureString "Enter the SonarQube token (input hidden)"
		$plainToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sonarToken))
		Write-Host "Creating repository secret SONAR_TOKEN..."
		gh secret set SONAR_TOKEN -b "$plainToken" -R $repo
		Write-Host "SONAR_TOKEN secret created."
	}
}

# Main script logic

# Prompt for repository
$repo = Read-Host "Enter the GitHub repository (owner/repo) to configure"

# Check for gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
	Write-Error "GitHub CLI (gh) is not installed. Please install it first."
	exit 1
}

Disable-Wiki $repo
Enable-Issues $repo
Enable-Discussions $repo
Configure-PRMergeSettings $repo
Enable-UpdateBranchSuggestion $repo
Enable-AutoMerge $repo
Enable-DeleteHeadBranches $repo
Configure-Rulesets $repo
Ask-EnableRenovate
Ask-CreateSonarToken $repo

