# The commit message has to be loaded from a Git-internal file
$commitMessage = Get-Content $args[0]

$conventionalCommitRegex = "(?-i)^(fixup! )?(build|ci|docs|feat|fix|perf|refactor|style|test|chore|revert|BREAKING CHANGE)(\([\w\-]+\))?!?:\s(\w+-\d+)?\s?[a-z]{1}.*"

if ($commitMessage -match $conventionalCommitRegex) {
    exit 0;
}

Write-Host "The commit message does not match the Conventional Commit rules"

exit 1