#!/usr/bin/env bash

set -euo pipefail

readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CLI_SOURCE="$REPO_DIR/scripts/evo-model"
readonly PROFILE_SOURCE_DIR="$REPO_DIR/config/models"
readonly UNIT_SOURCE="$REPO_DIR/systemd/evo-model.service"
readonly COMPLETION_SOURCE="$REPO_DIR/completions/evo-model.bash"
readonly CLI_DESTINATION="$HOME/.local/bin/evo-model"
readonly EXPECTED_PROFILE_DESTINATION_DIR="$HOME/.local/share/evo-model/models"
# Test-only override: any path other than the expected user-local directory is
# rejected before installation or deletion.
readonly PROFILE_DESTINATION_DIR="${EVO_MODEL_TEST_PROFILE_DESTINATION:-$EXPECTED_PROFILE_DESTINATION_DIR}"
readonly UNIT_DESTINATION="$HOME/.config/systemd/user/evo-model.service"
readonly COMPLETION_DESTINATION="$HOME/.local/share/bash-completion/completions/evo-model"

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
ok() { printf '[OK] %-16s %s\n' "$1" "$2"; }

[[ -f "$CLI_SOURCE" ]] || die "missing required file: $CLI_SOURCE"
[[ -d "$PROFILE_SOURCE_DIR" ]] || die "missing required directory: $PROFILE_SOURCE_DIR"
[[ -f "$UNIT_SOURCE" ]] || die "missing required file: $UNIT_SOURCE"
[[ -f "$COMPLETION_SOURCE" ]] || die "missing required file: $COMPLETION_SOURCE"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required for daemon-reload"
[[ "$PROFILE_DESTINATION_DIR" == "$EXPECTED_PROFILE_DESTINATION_DIR" ]] \
  || die "refusing to manage profiles outside: $EXPECTED_PROFILE_DESTINATION_DIR"

shopt -s nullglob
profiles=("$PROFILE_SOURCE_DIR"/*.conf)
(( ${#profiles[@]} > 0 )) || die "no profile files found in: $PROFILE_SOURCE_DIR"

printf 'Installing evo-model...\n\n'
mkdir -p \
  "$(dirname -- "$CLI_DESTINATION")" \
  "$PROFILE_DESTINATION_DIR" \
  "$(dirname -- "$UNIT_DESTINATION")" \
  "$(dirname -- "$COMPLETION_DESTINATION")"

install -m 755 "$CLI_SOURCE" "$CLI_DESTINATION"
ok "CLI" "$CLI_DESTINATION"

# This directory is managed by install.sh. Remove only profile files in this
# exact directory; never remove the directory itself or other file types.
installed_profiles=("$PROFILE_DESTINATION_DIR"/*.conf)
for profile in "${installed_profiles[@]}"; do
  rm -f -- "$profile"
done
for profile in "${profiles[@]}"; do
  install -m 644 "$profile" "$PROFILE_DESTINATION_DIR/${profile##*/}"
done
ok "Profiles" "${#profiles[@]} installed"

install -m 644 "$COMPLETION_SOURCE" "$COMPLETION_DESTINATION"
ok "Bash completion" "$COMPLETION_DESTINATION"

install -m 644 "$UNIT_SOURCE" "$UNIT_DESTINATION"
ok "systemd unit" "$UNIT_DESTINATION"

systemctl --user daemon-reload
ok "systemd" "daemon-reload"

printf '\nInstallation complete.\n\nAvailable profiles:\n'
for profile in "${profiles[@]}"; do
  printf '  %s\n' "${profile##*/}" | sed 's/\.conf$//'
done
printf '\nOpen a new Bash shell, or run:\n  source %s\n' "$COMPLETION_DESTINATION"
