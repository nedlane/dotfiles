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

# Claude Code.
alias cl='claude'
