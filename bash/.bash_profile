# Bash login shell entrypoint for macOS
# Terminal.app opens login shells by default, which read .bash_profile but not .bashrc
# Source .bashrc so all config lives in one place.

[[ -r ~/.bashrc ]] && source ~/.bashrc


# Added by Antigravity CLI installer
export PATH="/Users/mcasa_atlantis/.local/bin:$PATH"
