$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

BeforeAll {
    $hookDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../hooks'))
    $validator = Join-Path $hookDirectory 'EnsureConventionalCommitMessage.ps1'
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
}

Describe 'Commit message subject validation' {
    It '<Name>' -ForEach @(
        @{ Name = 'AcceptsBasicSubject'; Message = 'feat: add thing'; ExpectedExit = 0 }
        @{ Name = 'AcceptsScopedSubject'; Message = 'fix(git): validate subject'; ExpectedExit = 0 }
        @{ Name = 'AcceptsBreakingSubject'; Message = 'feat(api)!: change contract'; ExpectedExit = 0 }
        @{ Name = 'AcceptsFixupSubject'; Message = 'fixup! feat: add thing'; ExpectedExit = 0 }
        @{ Name = 'AcceptsPlainBody'; Message = 'fix: correct behavior' + [Environment]::NewLine + [Environment]::NewLine + 'Plain rationale.'; ExpectedExit = 0 }
        @{ Name = 'RejectsInvalidSubject'; Message = 'update stuff'; ExpectedExit = 1 }
        @{ Name = 'RejectsMissingSpace'; Message = 'feat:add thing'; ExpectedExit = 1 }
        @{ Name = 'RejectsUnknownType'; Message = 'unknown: add thing'; ExpectedExit = 1 }
        @{ Name = 'RejectsUppercaseType'; Message = 'FEAT: add thing'; ExpectedExit = 1 }
        @{ Name = 'RejectsLeadingWhitespace'; Message = ' feat: add thing'; ExpectedExit = 1 }
        @{ Name = 'RejectsEmptyMessage'; Message = ''; ExpectedExit = 1 }
        @{ Name = 'RejectsInvalidSubjectWithValidBody'; Message = 'update stuff' + [Environment]::NewLine + [Environment]::NewLine + 'feat: body line'; ExpectedExit = 1 }
        @{ Name = 'RejectsEmptySubjectWithValidBody'; Message = [Environment]::NewLine + 'feat: body line'; ExpectedExit = 1 }
    ) {
        $messageFile = Join-Path $TestDrive 'message.txt'
        [IO.File]::WriteAllText($messageFile, $Message)

        $PSNativeCommandUseErrorActionPreference = $false
        $output = @(& $pwsh -NoLogo -NoProfile -File $validator $messageFile 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be $ExpectedExit
        if ($ExpectedExit -ne 0) {
            ($output -join [Environment]::NewLine) | Should -Match 'does not match the Conventional Commit rules'
        }
    }
}

Describe 'Git commit-message hook integration' {
    It '<Name>' -ForEach @(
        @{ Name = 'GitAcceptsValidSubject'; Message = 'chore: verify hook'; ExpectedExit = 0 }
        @{ Name = 'GitRejectsInvalidSubjectWithValidBody'; Message = 'update stuff' + [Environment]::NewLine + [Environment]::NewLine + 'feat: body line'; ExpectedExit = 1 }
    ) {
        $repository = Join-Path $TestDrive $Name
        & git init --quiet --initial-branch=fixture $repository
        $messageFile = Join-Path $TestDrive "$Name.txt"
        [IO.File]::WriteAllText($messageFile, $Message)

        $PSNativeCommandUseErrorActionPreference = $false
        $output = @(& git -C $repository -c "core.hooksPath=$hookDirectory" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --allow-empty --file $messageFile 2>&1)
        $exitCode = $LASTEXITCODE
        $null = & git -C $repository rev-parse --verify HEAD 2>$null
        $headExit = $LASTEXITCODE

        $exitCode | Should -Be $ExpectedExit
        if ($ExpectedExit -eq 0) {
            $headExit | Should -Be 0
        } else {
            $headExit | Should -Not -Be 0
            ($output -join [Environment]::NewLine) | Should -Match 'does not match the Conventional Commit rules'
        }
    }
}
