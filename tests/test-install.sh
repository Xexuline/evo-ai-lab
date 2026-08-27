#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

TEST_HOME="$TEMP_DIR/home"
FAKE_BIN="$TEMP_DIR/bin"
SYSTEMCTL_LOG="$TEMP_DIR/systemctl.log"
mkdir -p "$FAKE_BIN" "$TEMP_DIR/other-directory"

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVO_MODEL_TEST_SYSTEMCTL_LOG"
EOF
chmod +x "$FAKE_BIN/systemctl"

run_installer() {
  (
    cd "$TEMP_DIR/other-directory"
    HOME="$TEST_HOME" EVO_MODEL_TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG" PATH="$FAKE_BIN:$PATH" \
      "$ROOT_DIR/install.sh"
  )
}

run_installer > "$TEMP_DIR/first-install-output"

CLI_DESTINATION="$TEST_HOME/.local/bin/evo-model"
PROFILE_DESTINATION_DIR="$TEST_HOME/.local/share/evo-model/models"
UNIT_DESTINATION="$TEST_HOME/.config/systemd/user/evo-model.service"
COMPLETION_DESTINATION="$TEST_HOME/.local/share/bash-completion/completions/evo-model"

[[ -x "$CLI_DESTINATION" ]]
[[ "$(stat -c '%a' "$CLI_DESTINATION")" == 755 ]]
[[ -f "$UNIT_DESTINATION" && "$(stat -c '%a' "$UNIT_DESTINATION")" == 644 ]]
[[ -f "$COMPLETION_DESTINATION" && "$(stat -c '%a' "$COMPLETION_DESTINATION")" == 644 ]]
for profile in "$ROOT_DIR"/config/models/*.conf; do
  installed_profile="$PROFILE_DESTINATION_DIR/${profile##*/}"
  [[ -f "$installed_profile" && "$(stat -c '%a' "$installed_profile")" == 644 ]]
  cmp -s "$profile" "$installed_profile"
done
grep -Fxq -- '--user daemon-reload' "$SYSTEMCTL_LOG"

# A second run updates known files but preserves profiles not owned by the repo.
printf 'LOCAL_PROFILE=preserve\n' > "$PROFILE_DESTINATION_DIR/local-custom.conf"
printf 'outdated\n' > "$CLI_DESTINATION"
run_installer > "$TEMP_DIR/second-install-output"
cmp -s "$ROOT_DIR/scripts/evo-model" "$CLI_DESTINATION"
[[ -f "$PROFILE_DESTINATION_DIR/local-custom.conf" ]]

echo "evo-model installer tests passed"
