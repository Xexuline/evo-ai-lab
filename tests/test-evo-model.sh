#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

PROFILE_DIR="$TEMP_DIR/profiles"
STATE_DIR="$TEMP_DIR/state"
FAKE_BIN="$TEMP_DIR/bin"
mkdir -p "$PROFILE_DIR"
MODEL_FILE="$TEMP_DIR/model.gguf"
DRAFT_FILE="$TEMP_DIR/draft.gguf"
touch "$MODEL_FILE"
touch "$DRAFT_FILE"

write_profile() {
  local name=$1
  sed -e "s|@MODEL@|$MODEL_FILE|g" -e "s|@DRAFT@|$DRAFT_FILE|g" > "$PROFILE_DIR/$name.conf"
}

write_profile good <<'EOF'
PROFILE_NAME=good
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=65536
GPU_LAYERS=999
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=2
SPEC_DRAFT_P_MIN=0.8
HOST=127.0.0.1
PORT=8080
EOF

run_manager() { EVO_MODEL_PROFILE_DIR="$PROFILE_DIR" EVO_MODEL_STATE_DIR="$STATE_DIR" "$ROOT_DIR/scripts/evo-model" "$@"; }

run_manager --validate-profile good >/dev/null

# The deployed qwen38 profile has no external draft; both repository profiles
# validate against the real GGUF files without contacting systemd.
EVO_MODEL_PROFILE_DIR="$ROOT_DIR/config/models" EVO_MODEL_STATE_DIR="$STATE_DIR" "$ROOT_DIR/scripts/evo-model" --validate-profile qwen38-q4 >/dev/null
EVO_MODEL_PROFILE_DIR="$ROOT_DIR/config/models" EVO_MODEL_STATE_DIR="$STATE_DIR" "$ROOT_DIR/scripts/evo-model" --validate-profile qwen36-mtp >/dev/null

write_profile external-draft <<'EOF'
PROFILE_NAME=external-draft
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=65536
GPU_LAYERS=999
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
DRAFT_MODEL_PATH=@DRAFT@
DRAFT_GPU_LAYERS=999
SPEC_DRAFT_N_MAX=2
SPEC_DRAFT_P_MIN=0.8
HOST=127.0.0.1
PORT=8080
EOF
run_manager --validate-profile external-draft >/dev/null

write_profile missing-draft <<'EOF'
PROFILE_NAME=missing-draft
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
DRAFT_MODEL_PATH=/does/not/exist.gguf
DRAFT_GPU_LAYERS=0
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if run_manager --validate-profile missing-draft >/dev/null 2>&1; then
  echo "expected missing draft model to fail" >&2
  exit 1
fi

write_profile relative-draft <<'EOF'
PROFILE_NAME=relative-draft
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
DRAFT_MODEL_PATH=draft.gguf
DRAFT_GPU_LAYERS=0
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if run_manager --validate-profile relative-draft >/dev/null 2>&1; then
  echo "expected relative draft model path to fail" >&2
  exit 1
fi

write_profile bad-key <<'EOF'
PROFILE_NAME=bad-key
MODEL_PATH=@MODEL@
UNSAFE=$(printf should-not-run)
EOF
if run_manager --validate-profile bad-key >/dev/null 2>&1; then
  echo "expected unknown profile key to fail" >&2
  exit 1
fi

write_profile missing-model <<'EOF'
PROFILE_NAME=missing-model
MODEL_PATH=/does/not/exist.gguf
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if run_manager --validate-profile missing-model >/dev/null 2>&1; then
  echo "expected missing model to fail" >&2
  exit 1
fi

mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/systemctl"

# With no stable user installation, direct repository execution selects
# config/models. systemctl is simulated because `list` only reads its state.
repo_profiles=$(HOME="$TEMP_DIR/repo-home" XDG_DATA_HOME="$TEMP_DIR/no-installed-data" PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/evo-model" list)
grep -Fxq 'qwen38-q4' <<<"$repo_profiles"
grep -Fxq 'qwen36-mtp' <<<"$repo_profiles"

# Simulate a Snap-like XDG_DATA_HOME. The stable per-user installation must win
# over both it and the repository-relative fallback.
INSTALLED_BIN="$TEMP_DIR/installed/bin"
INSTALLED_HOME="$TEMP_DIR/installed-home"
INSTALLED_MODELS="$INSTALLED_HOME/.local/share/evo-model/models"
SNAP_DATA="$TEMP_DIR/fake-snap/.local/share"
mkdir -p "$INSTALLED_BIN" "$INSTALLED_MODELS"
cp "$ROOT_DIR/scripts/evo-model" "$INSTALLED_BIN/evo-model"
chmod +x "$INSTALLED_BIN/evo-model"
sed 's/^PROFILE_NAME=good$/PROFILE_NAME=qwen38-q4/' "$PROFILE_DIR/good.conf" > "$INSTALLED_MODELS/qwen38-q4.conf"
installed_profiles=$(HOME="$INSTALLED_HOME" XDG_DATA_HOME="$SNAP_DATA" PATH="$FAKE_BIN:$PATH" "$INSTALLED_BIN/evo-model" list)
grep -Fxq 'qwen38-q4' <<<"$installed_profiles"
HOME="$INSTALLED_HOME" XDG_DATA_HOME="$SNAP_DATA" "$INSTALLED_BIN/evo-model" --validate-profile qwen38-q4 >/dev/null

# The explicit override has priority over the stable installed layout.
OVERRIDE_MODELS="$TEMP_DIR/override-models"
mkdir -p "$OVERRIDE_MODELS"
sed 's/^PROFILE_NAME=good$/PROFILE_NAME=override/' "$PROFILE_DIR/good.conf" > "$OVERRIDE_MODELS/override.conf"
EVO_MODEL_PROFILE_DIR="$OVERRIDE_MODELS" HOME="$INSTALLED_HOME" XDG_DATA_HOME="$SNAP_DATA" "$INSTALLED_BIN/evo-model" --validate-profile override >/dev/null

# Even an installed script with neither profile directory can show help.
EMPTY_BIN="$TEMP_DIR/empty/bin"
mkdir -p "$EMPTY_BIN"
cp "$ROOT_DIR/scripts/evo-model" "$EMPTY_BIN/evo-model"
chmod +x "$EMPTY_BIN/evo-model"
HOME="$TEMP_DIR/empty-home" XDG_DATA_HOME="$TEMP_DIR/empty-data" "$EMPTY_BIN/evo-model" --help >/dev/null

cat > "$FAKE_BIN/distrobox" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "list" ]]; then
  cat <<'TABLE'
ID | NAME | STATUS | IMAGE
abc123 | llama-vulkan-radv | Up | example/radv
def456 | llama-vulkan | Up | example/vulkan
TABLE
elif [[ "$1" == "enter" ]]; then
  printf '%s\n' "$@" > "$EVO_MODEL_TEST_ARGS"
fi
EOF
chmod +x "$FAKE_BIN/distrobox"

mkdir -p "$STATE_DIR"
printf 'good\n' > "$STATE_DIR/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/no-draft-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected
if grep -Fxq -- '--spec-draft-model' "$TEMP_DIR/no-draft-args" || grep -Fxq -- '--spec-draft-ngl' "$TEMP_DIR/no-draft-args"; then
  echo "profile without draft unexpectedly passed draft arguments" >&2
  exit 1
fi

printf 'external-draft\n' > "$STATE_DIR/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/draft-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected
cat > "$TEMP_DIR/expected-draft-args" <<EOF
enter
llama-vulkan-radv
--
llama-server
-m
$MODEL_FILE
-ngl
999
-c
65536
-np
1
--spec-type
draft-mtp
--spec-draft-model
$DRAFT_FILE
--spec-draft-ngl
999
--spec-draft-n-max
2
--spec-draft-p-min
0.8
--host
127.0.0.1
--port
8080
EOF
diff -u "$TEMP_DIR/expected-draft-args" "$TEMP_DIR/draft-args"

cat > "$FAKE_BIN/ss" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${EVO_MODEL_TEST_SS_ARGS:-}" ]]; then
  printf '%s\n' "$*" > "$EVO_MODEL_TEST_SS_ARGS"
fi
case "${EVO_MODEL_TEST_SS_MODE:-free}" in
  free) ;;
  occupied) printf 'LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:*\n' ;;
  similar) printf 'LISTEN 0 4096 0.0.0.0:18080 0.0.0.0:*\n' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$FAKE_BIN/ss"

PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime good >/dev/null
EVO_MODEL_TEST_SS_MODE=free PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
EVO_MODEL_TEST_SS_MODE=similar PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
if EVO_MODEL_TEST_SS_MODE=occupied PATH="$FAKE_BIN:$PATH" run_manager --check-port good >"$TEMP_DIR/port-error" 2>&1; then
  echo "expected an occupied port to fail" >&2
  exit 1
fi
grep -q 'port 8080 is already in use' "$TEMP_DIR/port-error"
EVO_MODEL_TEST_SS_MODE=free EVO_MODEL_TEST_SS_ARGS="$TEMP_DIR/ss-args" PATH="$FAKE_BIN:$PATH" run_manager --check-port good >/dev/null
grep -Fq 'sport = :8080' "$TEMP_DIR/ss-args"

write_profile partial-container <<'EOF'
PROFILE_NAME=partial-container
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-ra
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime partial-container >/dev/null 2>&1; then
  echo "expected a partial container name to fail" >&2
  exit 1
fi

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" show "* ]]; then
  printf '123\n'
  exit 0
fi
if [[ " $* " == *" is-active "* ]]; then
  printf 'active\n'
fi
exit 0
EOF
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/curl"
mkdir -p "$STATE_DIR"
printf 'good\n' > "$STATE_DIR/selected-profile"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: ready"* ]]
[[ "$status_output" == *"Listen: 127.0.0.1:8080"* ]]
[[ "$status_output" == *"Health endpoint: http://127.0.0.1:8080/v1/models"* ]]

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"another-model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/curl"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: not ready"* ]]

# Transient curl failures stay silent while each poll reports elapsed time. The
# counter makes the successful response arrive only after multiple failures.
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
counter_file="${EVO_MODEL_TEST_CURL_COUNTER:?}"
count=0
[[ -f "$counter_file" ]] && count=$(<"$counter_file")
count=$((count + 1))
printf '%s\n' "$count" > "$counter_file"
if [[ "$count" -lt 3 ]]; then
  printf 'curl: transient test failure\n' >&2
  exit 7
fi
printf '{"data":[{"id":"model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/curl"
EVO_MODEL_TEST_CURL_COUNTER="$TEMP_DIR/curl-counter" PATH="$FAKE_BIN:$PATH" run_manager start good >"$TEMP_DIR/loading-output" 2>&1
if grep -q 'curl: transient test failure' "$TEMP_DIR/loading-output"; then
  echo "transient curl error was shown to the user" >&2
  exit 1
fi
mapfile -t waiting_times < <(sed -n 's/^Waiting for API\.\.\. \([0-9][0-9]*\)s$/\1/p' "$TEMP_DIR/loading-output")
[[ ${#waiting_times[@]} -ge 2 ]]
[[ "${waiting_times[1]}" -gt "${waiting_times[0]}" ]]
grep -Eq '^Model loaded in [0-9]+s$' "$TEMP_DIR/loading-output"

# restart reuses the same waiting path and reports the load completion too.
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/curl"
PATH="$FAKE_BIN:$PATH" run_manager restart >"$TEMP_DIR/restart-output" 2>&1
grep -Eq '^Model loaded in [0-9]+s$' "$TEMP_DIR/restart-output"

# A continuously unavailable API reaches the timeout without exposing curl
# diagnostics or waiting for the production timeout.
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl: timeout test failure\n' >&2
exit 7
EOF
chmod +x "$FAKE_BIN/curl"
if PATH="$FAKE_BIN:$PATH" EVO_MODEL_HEALTH_TIMEOUT=1 run_manager start good >"$TEMP_DIR/timeout-output" 2>&1; then
  echo "expected health check timeout to fail" >&2
  exit 1
fi
grep -q 'Model did not become ready after ' "$TEMP_DIR/timeout-output"
if grep -q 'curl: timeout test failure' "$TEMP_DIR/timeout-output"; then
  echo "timeout exposed transient curl diagnostics" >&2
  exit 1
fi

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"model.gguf"}]}'
EOF
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
counter_file="${EVO_MODEL_TEST_COUNTER:?}"
if [[ "$*" == *"is-active"* ]]; then
  count=0
  [[ -f "$counter_file" ]] && count=$(<"$counter_file")
  count=$((count + 1))
  printf '%s\n' "$count" > "$counter_file"
  # start: active; wait loop: active; health before curl: active;
  # health after curl: inactive.
  [[ "$count" -lt 4 ]]
  exit
fi
exit 0
EOF
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/curl"
if EVO_MODEL_TEST_COUNTER="$TEMP_DIR/systemctl-count" PATH="$FAKE_BIN:$PATH" EVO_MODEL_HEALTH_TIMEOUT=5 run_manager start good >"$TEMP_DIR/health-output" 2>&1; then
  echo "expected health check to fail after the service becomes inactive" >&2
  exit 1
fi
if grep -q 'API ready' "$TEMP_DIR/health-output"; then
  echo "health check accepted an API after service shutdown" >&2
  exit 1
fi

echo "evo-model profile validation tests passed"
