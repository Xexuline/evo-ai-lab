# Bash completion for evo-model. Install under:
# ~/.local/share/bash-completion/completions/evo-model

_evo_model_completion() {
  local current command profiles instances
  current=${COMP_WORDS[COMP_CWORD]}
  command=${COMP_WORDS[1]:-}

  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W 'list status start stop restart logs help' -- "$current") )
    return 0
  fi

  case "$command" in
    start)
      instances='worker agent'
      if (( COMP_CWORD == 2 )); then
        COMPREPLY=( $(compgen -W "$instances" -- "$current") )
        profiles=$(command evo-model list 2>/dev/null) || return 0
        COMPREPLY+=( $(compgen -W "$(awk '{print $1}' <<<"$profiles")" -- "$current") )
        return 0
      fi
      (( COMP_CWORD == 3 )) || return 0
      [[ ${COMP_WORDS[2]} == worker || ${COMP_WORDS[2]} == agent ]] || return 0
      profiles=$(command evo-model list 2>/dev/null) || return 0
      profiles=$(awk '{print $1}' <<<"$profiles")
      COMPREPLY=( $(compgen -W "$profiles" -- "$current") )
      ;;
    status|stop|restart)
      (( COMP_CWORD == 2 )) || return 0
      COMPREPLY=( $(compgen -W 'worker agent' -- "$current") )
      ;;
    logs)
      if (( COMP_CWORD == 2 )); then
        COMPREPLY=( $(compgen -W 'worker agent -f --follow' -- "$current") )
      elif (( COMP_CWORD == 3 )) && [[ ${COMP_WORDS[2]} == worker || ${COMP_WORDS[2]} == agent ]]; then
        COMPREPLY=( $(compgen -W '-f --follow' -- "$current") )
      fi
      ;;
  esac
}

complete -F _evo_model_completion evo-model
