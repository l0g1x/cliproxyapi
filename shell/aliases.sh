# shellcheck shell=sh
# cliproxyapi — managed by ~/.cliproxyapi (https://github.com/l0g1x/cliproxyapi)
# Sourced (never executed) from ~/.zshrc or ~/.bashrc, so it has no shebang and is
# written in POSIX sh. Safe to source multiple times.
case ":$PATH:" in *":$HOME/.cliproxyapi/bin:"*) ;; *) export PATH="$HOME/.cliproxyapi/bin:$PATH" ;; esac

alias auth-claude='cpa auth claude'
alias auth-codex='cpa auth codex'
alias cliproxyapi-restart='cpa server restart'
alias cliproxyapi-logs='cpa server logs'
alias cliproxyapi-status='cpa server status'
alias cliproxyapi-models='cpa models'

# On Linux the binary lives inside the container; on macOS brew already provides `cliproxyapi`.
if [ "$(uname -s)" = Linux ]; then
  alias cliproxyapi='cpa server exec'
fi
