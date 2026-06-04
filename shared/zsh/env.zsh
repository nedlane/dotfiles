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

# zoxide
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi
