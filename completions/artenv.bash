#!/usr/bin/env bash

_artenv_list_commands() {
  command artenv commands 2>/dev/null
}

_artenv_list_envs() {
  [[ -n "${ARTENV_ROOT:-}" && -d "${ARTENV_ROOT}/envs" ]] || return 0
  local f
  for f in "${ARTENV_ROOT}/envs"/*.toml; do
    [[ -f "${f}" ]] || continue
    basename "${f}" .toml
  done
}

_artenv_list_versions() {
  [[ -n "${ARTENV_ROOT:-}" && -d "${ARTENV_ROOT}/versions" ]] || return 0
  local f
  for f in "${ARTENV_ROOT}/versions"/*.toml; do
    [[ -f "${f}" ]] || continue
    basename "${f}" .toml
  done
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
    shell|default|info)
      COMPREPLY=( $(compgen -W "$(_artenv_list_envs)" -- "${cur}") )
      return 0
      ;;
    doctor)
      COMPREPLY=( $(compgen -W "--all $(_artenv_list_envs)" -- "${cur}") )
      return 0
      ;;
    install)
      COMPREPLY=( $(compgen -W "--native --apptainer --update --list -l --help -h" -- "${cur}") )
      return 0
      ;;
    *)
      COMPREPLY=()
      return 0
      ;;
  esac
}

complete -F _artenv_completion artenv
