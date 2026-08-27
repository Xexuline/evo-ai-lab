# Bash completion for evo-model. Install under:
# ~/.local/share/bash-completion/completions/evo-model

_evo_model_completion() {
  local current command profiles
  current=${COMP_WORDS[COMP_CWORD]}
  command=${COMP_WORDS[1]:-}

  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W 'list status start stop restart logs help' -- "$current") )
    return 0
  fi

  case "$command" in
    start)
      (( COMP_CWORD == 2 )) || return 0
      profiles=$(command evo-model list 2>/dev/null) || return 0
      profiles=$(awk '{print $1}' <<<"$profiles")
      COMPREPLY=( $(compgen -W "$profiles" -- "$current") )
      ;;
    logs)
      (( COMP_CWORD == 2 )) || return 0
      COMPREPLY=( $(compgen -W '-f --follow' -- "$current") )
      ;;
  esac
}

complete -F _evo_model_completion evo-model
