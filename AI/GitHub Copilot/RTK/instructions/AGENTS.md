# RTK command filtering

RTK automatically rewrites supported shell commands through a hook.
This is intentional; do not retry successful commands because of the rewrite.
Use ordinary commands without manually adding an rtk prefix.
Do not prefix PowerShell cmdlets with rtk.
When unfiltered diagnostic output is needed, use rtk bypass followed by the original command.
