#!/usr/bin/env bash
# shellcheck disable=SC2207  # word-splitting of compgen output is intentional in completions

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

_artenv_list_templates() {
  command artenv templates ls 2>/dev/null
}

_artenv_completion() {
  local cur prev cmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]:-}"
  cmd="${COMP_WORDS[1]:-}"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$(_artenv_list_commands)" -- "${cur}") )
    return 0
  fi

  case "${cmd}" in
    version)
      # `artenv version <sub> [target]`
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "ls register remove archive unarchive info edit install current -h" -- "${cur}") )
      else
        case "${COMP_WORDS[2]:-}" in
          remove|archive|unarchive|info|edit)
            COMPREPLY=( $(compgen -W "$(_artenv_list_versions)" -- "${cur}") )
            ;;
          install)
            COMPREPLY=( $(compgen -W "--native --apptainer --update --list -l --help -h" -- "${cur}") )
            ;;
          *)
            COMPREPLY=()
            ;;
        esac
      fi
      return 0
      ;;
    templates)
      # `artenv templates <sub>`
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "ls repos update -h" -- "${cur}") )
      else
        COMPREPLY=()
      fi
      return 0
      ;;
    new)
      # complete template names after -t/--template; dirs after --repo; flags
      # when the current word starts with a dash.
      if [[ "${prev}" == "-t" || "${prev}" == "--template" ]]; then
        COMPREPLY=( $(compgen -W "$(_artenv_list_templates)" -- "${cur}") )
      elif [[ "${prev}" == "--repo" ]]; then
        COMPREPLY=( $(compgen -d -- "${cur}") )
      elif [[ "${cur}" == -* ]]; then
        COMPREPLY=( $(compgen -W "-t --template --multiuser --repo -h --help" -- "${cur}") )
      else
        COMPREPLY=()
      fi
      return 0
      ;;
    register|register-env)
      # `artenv register <new-env> [flags]`. The env name is new (not-yet-
      # existing) so it gets no completion, but the flags and their values do.
      if [[ "${prev}" == "--version" ]]; then
        COMPREPLY=( $(compgen -W "$(_artenv_list_versions)" -- "${cur}") )
      elif [[ "${prev}" == "--work" || "${prev}" == "--repos" ]]; then
        COMPREPLY=( $(compgen -d -- "${cur}") )
      elif [[ "${cur}" == -* ]]; then
        COMPREPLY=( $(compgen -W "--version --work --repos --multiuser --singleuser -h --help" -- "${cur}") )
      else
        COMPREPLY=()
      fi
      return 0
      ;;
    register-version)
      # register-version takes a new (not-yet-existing) name; offer no completion
      COMPREPLY=()
      return 0
      ;;
    remove|archive|unarchive|remove-env|archive-env|unarchive-env|shell|default|info|edit)
      COMPREPLY=( $(compgen -W "$(_artenv_list_envs)" -- "${cur}") )
      return 0
      ;;
    remove-version|archive-version|unarchive-version)
      COMPREPLY=( $(compgen -W "$(_artenv_list_versions)" -- "${cur}") )
      return 0
      ;;
    doctor)
      COMPREPLY=( $(compgen -W "--all --orphans $(_artenv_list_envs)" -- "${cur}") )
      return 0
      ;;
    install)
      COMPREPLY=( $(compgen -W "--native --apptainer --update --list -l --help -h" -- "${cur}") )
      return 0
      ;;
    upgrade)
      COMPREPLY=( $(compgen -W "-h --help" -- "${cur}") )
      return 0
      ;;
    *)
      COMPREPLY=()
      return 0
      ;;
  esac
}

complete -F _artenv_completion artenv
