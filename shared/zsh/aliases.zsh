# shared/zsh/aliases.zsh — shell-agnostic aliases shared by every machine.

alias zshconfig="nvim ~/.zshrc"
alias sourcezsh="source ~/.zshrc"

# fuzzy cd into any subdir of $HOME
alias f='~ && cd $(fd --type d --hidden --exclude .git --exclude node_modules --exclude .cache --exclude .npm --exclude bin --exclude .cargo | fzf)'

# tmux
alias tn="tmux new -s"
alias td="tmux detach"
alias th="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/lib/tmuxHelper.sh"

# misc
alias p3="python3"
alias texpdf="latexmk -pdf"
# Prefer the Compose v2 subcommand everywhere, even where a legacy
# docker-compose shim is muscle-memory.
alias docker-compose="docker compose"

# Claude Code: launch an always-on remote-control session whose title is
# "<host> / <dir>", so every device is identifiable in the claude.ai/code and
# mobile session list. The naming/auth semantics live in the standalone
# shared/bin/claude-launch (also used by claude-worker for orchestrated
# sessions); `cl` is just the interactive shorthand. An explicit --name/-n
# from the caller wins over the injected title.
cl() {
  "${DOTFILES_DIR:-$HOME/dotfiles}/shared/bin/claude-launch" "$@"
}

# Claude Code via a client's proxy (work engagements). Credentials live in
# ~/.config/claude-work/env — OUTSIDE the dotfiles repo, chmod 600 — and are
# exported only for the launched process, never into the calling shell. On
# first run the function prompts for both values (key input hidden, so it also
# stays out of shell history) and writes the file itself. To rotate or remove:
# edit or delete that file.
clw() {
  local envfile="${XDG_CONFIG_HOME:-$HOME/.config}/claude-work/env"
  if [[ ! -r "$envfile" ]]; then
    echo "clw: first run — storing proxy credentials in $envfile"
    local key url
    read -rs "key?ANTHROPIC_API_KEY (input hidden): "; echo
    read -r "url?ANTHROPIC_BASE_URL: "
    if [[ -z "$key" || -z "$url" ]]; then
      echo "clw: both values are required; nothing saved" >&2
      return 1
    fi
    mkdir -p "${envfile:h}"
    (umask 077; printf 'ANTHROPIC_API_KEY=%s\nANTHROPIC_BASE_URL=%s\n' \
      "$key" "$url" > "$envfile")
  fi
  # Subshell so the secrets are exported only around the exec, not leaked
  # into the interactive shell's environment.
  (
    set -a; source "$envfile"; set +a
    exec claude --permission-mode auto "$@"
  )
}
