#!/usr/bin/env bash

dotfiles_detect_host() {
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    printf '%s\n' mac
  elif grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    printf '%s\n' wsl-desktop
  else
    case "$(hostname -s 2>/dev/null || hostname)" in
      raspberrypi) printf '%s\n' pi ;;
      *) hostname -s 2>/dev/null || hostname ;;
    esac
  fi
}
