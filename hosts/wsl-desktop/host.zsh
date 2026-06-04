# hosts/wsl-desktop/host.zsh — WSL2 desktop overlay. Sourced before oh-my-zsh.sh.

# --- ROS2 (Humble) + EUFS workspace ---
export EUFS_MASTER="$HOME/ros2_ws/src"
[[ -f /opt/ros/humble/setup.zsh ]]        && source /opt/ros/humble/setup.zsh
[[ -f "$HOME/ros2_ws/install/setup.zsh" ]] && source "$HOME/ros2_ws/install/setup.zsh"

# --- CUDA 12.9 ---
if [[ -d /usr/local/cuda-12.9 ]]; then
  export PATH="/usr/local/cuda-12.9/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/cuda-12.9/lib64:${LD_LIBRARY_PATH:-}"
fi

# --- desktop aliases ---
# `cl` is now shared (shared/zsh/aliases.zsh).
alias eufs="LIBGL_ALWAYS_SOFTWARE=1 ros2 launch eufs_launcher eufs_launcher.launch.py"

# --- machine identity (consumed by shared/zsh/zshrc) ---
# Purple accent; prompt shows the real hostname.
export DOTFILES_ACCENT=141
