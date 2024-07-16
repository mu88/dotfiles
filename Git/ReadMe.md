# Configure Git

Do the following to use the settings from this directory:
- Add the following to your global Git config (e.g. via ` code $Env:UserProfile/.gitconfig`):

```lang-ini
[include]
	path = <<path to cloned dotfiles repo>>/Git/.gitconfig
```