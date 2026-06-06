# shared/zsh/env.zsh — environment shared by every machine (guarded, so a path
# that doesn't exist on a given host is simply skipped).

# Preferred editor (lighter one over SSH).
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

export GPG_TTY=$(tty)

# ~/bin, ~/.local/bin and cargo
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# nvm
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# luarocks
[[ -d "$HOME/.luarocks/bin" ]] && export PATH="$HOME/.luarocks/bin:$PATH"

# WSL: re-add the Windows interop dirs to PATH. WSL normally appends these, but
# with systemd=true this distro inherits the static /etc/environment PATH and
# the append never lands, so explorer.exe & co. go missing. We add them back,
# appended (so Linux tools still win). Guarded to WSL — this file is shared with
# non-WSL machines. `typeset -U path` dedupes, keeping it idempotent and cheap.
if [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
  typeset -U path
  for _win in /mnt/c/Windows /mnt/c/Windows/System32; do
    [[ -d "$_win" ]] && path+=("$_win")
  done
  unset _win

  # Open a path (default: cwd) in Windows Explorer. explorer.exe returns
  # non-zero even on success, so swallow it.
  explorer() { /mnt/c/Windows/explorer.exe "${1:-.}"; return 0; }
  alias open=explorer
fi

# zoxide
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi
