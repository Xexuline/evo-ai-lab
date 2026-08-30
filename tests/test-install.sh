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
REMOTE_CLI_DESTINATION="$TEST_HOME/.local/bin/evo-model-remote"
PROFILE_DESTINATION_DIR="$TEST_HOME/.local/share/evo-model/models"
UNIT_DESTINATION="$TEST_HOME/.config/systemd/user/evo-model@.service"
COMPLETION_DESTINATION="$TEST_HOME/.local/share/bash-completion/completions/evo-model"

[[ -x "$CLI_DESTINATION" ]]
[[ "$(stat -c '%a' "$CLI_DESTINATION")" == 755 ]]
[[ -x "$REMOTE_CLI_DESTINATION" ]]
[[ "$(stat -c '%a' "$REMOTE_CLI_DESTINATION")" == 755 ]]
cmp -s "$ROOT_DIR/scripts/evo-model-remote" "$REMOTE_CLI_DESTINATION"
[[ -f "$UNIT_DESTINATION" && "$(stat -c '%a' "$UNIT_DESTINATION")" == 644 ]]
grep -Fxq 'ExecStart=%h/.local/bin/evo-model run-selected %i' "$UNIT_DESTINATION"
[[ -f "$COMPLETION_DESTINATION" && "$(stat -c '%a' "$COMPLETION_DESTINATION")" == 644 ]]
for profile in "$ROOT_DIR"/config/models/*.conf; do
  installed_profile="$PROFILE_DESTINATION_DIR/${profile##*/}"
  [[ -f "$installed_profile" && "$(stat -c '%a' "$installed_profile")" == 644 ]]
  cmp -s "$profile" "$installed_profile"
done
grep -Fxq -- '--user daemon-reload' "$SYSTEMCTL_LOG"

# A second run updates known files, removes obsolete .conf files, and preserves
# non-profile files in the managed directory.
printf 'LOCAL_PROFILE=obsolete\n' > "$PROFILE_DESTINATION_DIR/local-custom.conf"
printf 'keep\n' > "$PROFILE_DESTINATION_DIR/notes.txt"
printf 'outdated\n' > "$CLI_DESTINATION"
printf 'outdated\n' > "$REMOTE_CLI_DESTINATION"
run_installer > "$TEMP_DIR/second-install-output"
cmp -s "$ROOT_DIR/scripts/evo-model" "$CLI_DESTINATION"
cmp -s "$ROOT_DIR/scripts/evo-model-remote" "$REMOTE_CLI_DESTINATION"
[[ ! -e "$PROFILE_DESTINATION_DIR/local-custom.conf" ]]
[[ -f "$PROFILE_DESTINATION_DIR/notes.txt" ]]

# A repository profile added later appears after installation, and disappears
# again when it is removed from that repository's source of truth.
SOURCE_COPY="$TEMP_DIR/source-copy"
mkdir -p "$SOURCE_COPY"
cp "$ROOT_DIR/install.sh" "$SOURCE_COPY/install.sh"
cp -R "$ROOT_DIR/scripts" "$ROOT_DIR/config" "$ROOT_DIR/systemd" "$ROOT_DIR/completions" "$SOURCE_COPY/"
chmod +x "$SOURCE_COPY/install.sh"
cat > "$SOURCE_COPY/config/models/test-added.conf" <<'EOF'
PROFILE_NAME=test-added
EOF
(
  cd "$TEMP_DIR/other-directory"
  HOME="$TEST_HOME" EVO_MODEL_TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG" PATH="$FAKE_BIN:$PATH" \
    "$SOURCE_COPY/install.sh"
)
[[ -f "$PROFILE_DESTINATION_DIR/test-added.conf" ]]
rm -f -- "$SOURCE_COPY/config/models/test-added.conf"
(
  cd "$TEMP_DIR/other-directory"
  HOME="$TEST_HOME" EVO_MODEL_TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG" PATH="$FAKE_BIN:$PATH" \
    "$SOURCE_COPY/install.sh"
)
[[ ! -e "$PROFILE_DESTINATION_DIR/test-added.conf" ]]

if HOME="$TEST_HOME" EVO_MODEL_TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
  EVO_MODEL_TEST_PROFILE_DESTINATION="$TEMP_DIR/wrong-profile-directory" PATH="$FAKE_BIN:$PATH" \
  "$ROOT_DIR/install.sh" >/dev/null 2>&1; then
  echo "expected non-standard profile destination to be rejected" >&2
  exit 1
fi
[[ ! -e "$TEMP_DIR/wrong-profile-directory" ]]

echo "evo-model installer tests passed"
