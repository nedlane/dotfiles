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
