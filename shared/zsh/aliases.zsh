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

# Claude Code: launch an always-on remote-control session whose title is
# "<host> / <dir>", so every device is identifiable in the claude.ai/code and
# mobile session list. The explicit --name skips Claude's auto-generated title,
# which otherwise reflects only the last message and hides which machine a
# session runs on. The host prefix is forced to a curated device name
# (mac/desktop/minipc/minipc2/pi) so it reads cleanly in the session list,
# regardless of the box's actual hostname; ${PWD:t} is the current directory's
# basename. An explicit --name/-n from the caller wins.
cl() {
  local host
  case "${DOTFILES_HOST:-}" in
    mac)         host=mac ;;
    wsl-desktop) host=desktop ;;
    minipc)      host=minipc ;;
    minipc2)     host=minipc2 ;;
    pi)          host=pi ;;
    *)           host="${DOTFILES_HOST:-$(hostname -s 2>/dev/null || hostname)}" ;;
  esac
  local title="${host:+$host / }${PWD:t}"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --name|--name=*|-n)
        claude --dangerously-skip-permissions --remote-control "$@"
        return
        ;;
    esac
  done
  claude --dangerously-skip-permissions --remote-control --name "$title" "$@"
}
