#!/usr/bin/env bash

_artenv_list_commands() {
  command artenv commands 2>/dev/null
}

_artenv_list_envs() {
  [[ -n "${ARTENV_ROOT:-}" && -d "${ARTENV_ROOT}/envs" ]] || return 0
  command ls -1 "${ARTENV_ROOT}/envs" 2>/dev/null
}

_artenv_completion() {
  local cur cmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmd="${COMP_WORDS[1]:-}"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$(_artenv_list_commands)" -- "${cur}") )
    return 0
  fi

  case "${cmd}" in
    shell|default|info|doctor)
      COMPREPLY=( $(compgen -W "$(_artenv_list_envs)" -- "${cur}") )
      return 0
      ;;
    *)
      COMPREPLY=()
      return 0
      ;;
  esac
}

complete -F _artenv_completion artenv
