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
MMPROJ_FILE="$TEMP_DIR/mmproj.gguf"
touch "$MODEL_FILE"
touch "$DRAFT_FILE"
touch "$MMPROJ_FILE"

write_profile() {
  local name=$1
  sed -e "s|@MODEL@|$MODEL_FILE|g" -e "s|@DRAFT@|$DRAFT_FILE|g" -e "s|@MMPROJ@|$MMPROJ_FILE|g" > "$PROFILE_DIR/$name.conf"
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

# Validate every repository profile using fixture GGUF paths, so the suite
# does not depend on models installed on the developer's machine.
for repository_profile in "$ROOT_DIR"/config/models/*.conf; do
  profile_name=${repository_profile##*/}
  profile_name=${profile_name%.conf}
  sed -e "s|^MODEL_PATH=.*|MODEL_PATH=$MODEL_FILE|" \
      -e "s|^DRAFT_MODEL_PATH=.*|DRAFT_MODEL_PATH=$DRAFT_FILE|" \
      -e "s|^MMPROJ_PATH=.*|MMPROJ_PATH=$MMPROJ_FILE|" \
      "$repository_profile" > "$PROFILE_DIR/$profile_name.conf"
  run_manager --validate-profile "$profile_name" >/dev/null
done

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
MMPROJ_PATH=@MMPROJ@
SPEC_DRAFT_N_MAX=2
SPEC_DRAFT_P_MIN=0.8
HOST=127.0.0.1
PORT=8080
EOF
run_manager --validate-profile external-draft >/dev/null

write_profile context-two <<'EOF'
PROFILE_NAME=context-two
MODEL_PATH=@MODEL@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=131072
GPU_LAYERS=999
PARALLEL_SLOTS=2
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=2
SPEC_DRAFT_P_MIN=0.8
HOST=127.0.0.1
PORT=8080
EOF
run_manager --validate-profile context-two >/dev/null

write_profile no-spec <<'EOF'
PROFILE_NAME=no-spec
MODEL_PATH=@MODEL@
MMPROJ_PATH=@MMPROJ@
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
run_manager --validate-profile no-spec >/dev/null

write_profile missing-mmproj <<'EOF'
PROFILE_NAME=missing-mmproj
MODEL_PATH=@MODEL@
MMPROJ_PATH=/does/not/exist.gguf
BACKEND=RADV/Vulkan
CONTAINER=llama-vulkan-radv
CONTEXT_SIZE=1
GPU_LAYERS=0
PARALLEL_SLOTS=1
SPEC_DRAFT_N_MAX=0
SPEC_DRAFT_P_MIN=0
HOST=127.0.0.1
PORT=1
EOF
if run_manager --validate-profile missing-mmproj >/dev/null 2>&1; then
  echo "expected missing multimodal projector to fail" >&2
  exit 1
fi

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
abc124 | llama-vulkan-worker | Up | example/worker
abc125 | llama-vulkan-test | Up | example/test
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

printf 'no-spec\n' > "$STATE_DIR/worker/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/no-spec-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected
grep -Fxq -- '--mmproj' "$TEMP_DIR/no-spec-args"
if grep -Fq -- '--spec-' "$TEMP_DIR/no-spec-args"; then
  echo "profile without SPEC_TYPE unexpectedly passed speculative arguments" >&2
  exit 1
fi

printf 'external-draft\n' > "$STATE_DIR/worker/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/draft-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected
cat > "$TEMP_DIR/expected-draft-args" <<EOF
enter
llama-vulkan-worker
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
--mmproj
$MMPROJ_FILE
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

# Flash uses its experimental runtime and exactly the requested server flags.
sed -e "s|^MODEL_PATH=.*|MODEL_PATH=$MODEL_FILE|" -e "s|^DRAFT_MODEL_PATH=.*|DRAFT_MODEL_PATH=$DRAFT_FILE|" "$ROOT_DIR/config/models/qwen38-flash.conf" > "$PROFILE_DIR/qwen38-flash.conf"
run_manager --validate-profile qwen38-flash >/dev/null
mkdir -p "$STATE_DIR/agent"
printf 'qwen38-flash\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/flash-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected agent
python3 - "$TEMP_DIR/flash-args" "$MODEL_FILE" "$DRAFT_FILE" <<'PYTEST'
import sys
from pathlib import Path
assert Path(sys.argv[1]).read_text().splitlines() == [
    "enter", "llama-vulkan-test", "--", "/home/evo/strix-llama.cpp/build/bin/llama-server",
    "-m", sys.argv[2], "-ngl", "99", "-c", "131072", "-np", "1",
    "--spec-type", "draft-mtp", "--spec-draft-model", sys.argv[3],
    "--spec-draft-n-max", "2",
    "-fa", "on", "-b", "2048", "-ub", "512",
    "--cache-type-k", "q8_0", "--cache-type-v", "q8_0",
    "--lazy-mode", "off", "--jinja", "--reasoning", "on",
    "--reasoning-preserve", "--host", "0.0.0.0", "--port", "8081",
]
PYTEST
PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime agent qwen38-flash | grep -Fxq 'Runtime available for agent: llama-vulkan-test'
for setting in FLASH_ATTN=invalid BATCH_SIZE=0 UBATCH_SIZE=-1 CACHE_TYPE_K=invalid CACHE_TYPE_V=invalid LAZY_MODE=invalid JINJA=invalid REASONING=invalid REASONING_PRESERVE=invalid RUNTIME_CONTAINER=/invalid SERVER_PATH=relative/path SPEC_DRAFT_ADAPTIVE=invalid SPEC_DRAFT_N_MIN=-1 SPEC_DRAFT_N_MIN=4 SPEC_DRAFT_N_MIN=1.5; do
  sed -e 's/^PROFILE_NAME=.*/PROFILE_NAME=bad-flash/' -e "/^${setting%%=*}=/d" "$PROFILE_DIR/qwen38-flash.conf" > "$PROFILE_DIR/bad-flash.conf"
  printf '%s\n' "$setting" >> "$PROFILE_DIR/bad-flash.conf"
  if run_manager --validate-profile bad-flash >/dev/null 2>&1; then
    echo "expected invalid setting to fail: $setting" >&2
    exit 1
  fi
done
sed -e 's/^PROFILE_NAME=.*/PROFILE_NAME=missing-runtime/' -e 's/^RUNTIME_CONTAINER=.*/RUNTIME_CONTAINER=missing-container/' "$PROFILE_DIR/qwen38-flash.conf" > "$PROFILE_DIR/missing-runtime.conf"
if PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime agent missing-runtime >/dev/null 2>&1; then
  echo "expected missing runtime container to fail" >&2
  exit 1
fi
# Adaptive decoding remains available independently of the Flash defaults.
sed 's/^PROFILE_NAME=.*/PROFILE_NAME=adaptive/' "$PROFILE_DIR/qwen38-flash.conf" > "$PROFILE_DIR/adaptive.conf"
printf 'SPEC_DRAFT_ADAPTIVE=on\nSPEC_DRAFT_N_MIN=2\n' >> "$PROFILE_DIR/adaptive.conf"
printf 'adaptive\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/adaptive-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected agent
python3 - "$TEMP_DIR/adaptive-args" <<'PYTEST'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_text().splitlines()
assert "--spec-draft-adaptive" in args
assert args[args.index("--spec-draft-n-min") + 1] == "2"
PYTEST
sed -e 's/^PROFILE_NAME=.*/PROFILE_NAME=orphan-ngl/' -e '/^DRAFT_MODEL_PATH=/d' "$PROFILE_DIR/external-draft.conf" > "$PROFILE_DIR/orphan-ngl.conf"
if run_manager --validate-profile orphan-ngl >/dev/null 2>&1; then
  echo "expected draft GPU layers without a draft model to fail" >&2
  exit 1
fi
# Optional flags can be disabled explicitly; paths remain a single argument
# even with spaces and shell metacharacters (profiles are data, never shell).
python3 - "$PROFILE_DIR" "$TEMP_DIR" <<'PYTEST'
from pathlib import Path
import sys
profiles = Path(sys.argv[1])
s = (profiles / "qwen38-flash.conf").read_text()
s = s.replace("PROFILE_NAME=qwen38-flash", "PROFILE_NAME=flash-off")
s += "SPEC_DRAFT_ADAPTIVE=off\n"
for key in ("FLASH_ATTN", "JINJA", "REASONING", "REASONING_PRESERVE", "SPEC_DRAFT_ADAPTIVE"):
    s = s.replace(key + "=on", key + "=off")
s = s.replace("LAZY_MODE=off", "LAZY_MODE=on")
s = s.replace("SERVER_PATH=/home/evo/strix-llama.cpp/build/bin/llama-server",
              "SERVER_PATH=" + sys.argv[2] + "/custom build/$(touch injected)")
(profiles / "flash-off.conf").write_text(s)
PYTEST
printf 'flash-off\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/off-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected agent
python3 - "$TEMP_DIR/off-args" "$TEMP_DIR" <<'PYTEST'
from pathlib import Path
import sys
args = Path(sys.argv[1]).read_text().splitlines()
assert args[3] == sys.argv[2] + "/custom build/$(touch injected)"
for flag, value in (("-fa", "off"), ("--reasoning", "off"), ("--lazy-mode", "on")):
    assert args[args.index(flag) + 1] == value
assert "--spec-draft-adaptive" not in args
assert "--no-jinja" in args
assert "--jinja" not in args
assert "--reasoning-preserve" not in args
PYTEST

# Removing all new options restores the default executable and instance
# container, with no speculative flags or unused draft settings required.
sed -e 's/^PROFILE_NAME=.*/PROFILE_NAME=minimal/' \
    -e '/^\(SPEC_\|DRAFT_\)/d' \
    -e '/^\(FLASH_ATTN\|BATCH_SIZE\|UBATCH_SIZE\|CACHE_TYPE_K\|CACHE_TYPE_V\|LAZY_MODE\|JINJA\|REASONING\|REASONING_PRESERVE\|RUNTIME_CONTAINER\|SERVER_PATH\)=/d' \
    "$PROFILE_DIR/qwen38-flash.conf" > "$PROFILE_DIR/minimal.conf"
printf 'minimal\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/minimal-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected agent
python3 - "$TEMP_DIR/minimal-args" "$MODEL_FILE" <<'PYTEST'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_text().splitlines() == [
    "enter", "llama-vulkan-radv", "--", "llama-server", "-m", sys.argv[2],
    "-ngl", "99", "-c", "131072", "-np", "1",
    "--host", "0.0.0.0", "--port", "8081",
]
PYTEST

# N_MAX remains mandatory with SPEC_TYPE; P_MIN may use the runtime default.
# Both are validated whenever supplied.
for key in SPEC_DRAFT_N_MAX SPEC_DRAFT_P_MIN; do
  sed -e 's/^PROFILE_NAME=.*/PROFILE_NAME=missing-spec-setting/' \
      -e "/^$key=/d" "$PROFILE_DIR/good.conf" > "$PROFILE_DIR/missing-spec-setting.conf"
  if [[ $key == SPEC_DRAFT_P_MIN ]]; then
    run_manager --validate-profile missing-spec-setting >/dev/null
  elif run_manager --validate-profile missing-spec-setting >/dev/null 2>&1; then
    echo "expected missing $key with SPEC_TYPE to fail" >&2
    exit 1
  fi
  sed 's/^PROFILE_NAME=.*/PROFILE_NAME=invalid-spec-setting/' "$PROFILE_DIR/minimal.conf" > "$PROFILE_DIR/invalid-spec-setting.conf"
  printf '%s=invalid\n' "$key" >> "$PROFILE_DIR/invalid-spec-setting.conf"
  if run_manager --validate-profile invalid-spec-setting >/dev/null 2>&1; then
    echo "expected invalid $key without SPEC_TYPE to fail" >&2
    exit 1
  fi
done

# New draft controls require speculative decoding rather than being ignored.
for setting in SPEC_DRAFT_ADAPTIVE=on SPEC_DRAFT_N_MIN=2; do
  sed 's/^PROFILE_NAME=.*/PROFILE_NAME=orphan-draft/' "$PROFILE_DIR/minimal.conf" > "$PROFILE_DIR/orphan-draft.conf"
  printf '%s\n' "$setting" >> "$PROFILE_DIR/orphan-draft.conf"
  if run_manager --validate-profile orphan-draft >/dev/null 2>&1; then
    echo "expected draft option without SPEC_TYPE to fail: $setting" >&2
    exit 1
  fi
done

# Duplicate optional keys must fail instead of silently overriding values.
sed 's/^PROFILE_NAME=.*/PROFILE_NAME=duplicate-server/' "$PROFILE_DIR/qwen38-flash.conf" > "$PROFILE_DIR/duplicate-server.conf"
printf 'SERVER_PATH=/another/server\n' >> "$PROFILE_DIR/duplicate-server.conf"
if run_manager --validate-profile duplicate-server >/dev/null 2>&1; then
  echo "expected duplicate SERVER_PATH to fail" >&2
  exit 1
fi
rm "$STATE_DIR/agent/selected-profile"

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

legacy_runtime_output=$(PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime good)
grep -Fxq 'Runtime available for worker: llama-vulkan-worker' <<<"$legacy_runtime_output"
worker_runtime_output=$(PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime worker good)
grep -Fxq 'Runtime available for worker: llama-vulkan-worker' <<<"$worker_runtime_output"
agent_runtime_output=$(PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime agent good)
grep -Fxq 'Runtime available for agent: llama-vulkan-radv' <<<"$agent_runtime_output"
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
# Runtime validation resolves the container from the instance, not profile
# metadata, so this valid-but-unavailable profile container does not matter.
PATH="$FAKE_BIN:$PATH" run_manager --validate-runtime partial-container >/dev/null

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
printf 'good\n' > "$STATE_DIR/worker/selected-profile"
printf 'qwen38-flash\n' > "$STATE_DIR/agent/selected-profile"
PATH="$FAKE_BIN:$PATH" run_manager status --json > "$TEMP_DIR/flash-status.json"
python3 - "$TEMP_DIR/flash-status.json" <<'PYTEST'
import json, sys
with open(sys.argv[1]) as f:
    instances = json.load(f)["instances"]
assert instances["agent"]["container"] == "llama-vulkan-test"
assert instances["worker"]["container"] == "llama-vulkan-worker"
assert instances["agent"]["port"] == 8081
PYTEST
rm "$STATE_DIR/agent/selected-profile"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: ready"* ]]
[[ "$status_output" == *"Listen: 127.0.0.1:8080"* ]]
[[ "$status_output" == *"Health endpoint: http://127.0.0.1:8080/v1/models"* ]]
expected_status=$(printf 'Instance: worker\nProfile: good\nService: active\nAPI: ready\nBackend: RADV/Vulkan\nContainer: llama-vulkan-worker\nModel: %s\nContext: 65536\nParallel slots: 1\nHost: 127.0.0.1\nPort: 8080\nListen: 127.0.0.1:8080\nHealth endpoint: http://127.0.0.1:8080/v1/models\nPID: 123\n\nInstance: agent\nProfile: (none selected)\nService: active\nAPI: not applicable\nContainer: llama-vulkan-radv\n' "$MODEL_FILE")
[[ "$status_output" == "$expected_status" ]]

# The JSON interface preserves a fixed root schema, uses JSON numbers for the
# capacity fields, and represents unavailable selected-profile data as null.
printf 'context-two\n' > "$STATE_DIR/worker/selected-profile"
mkdir -p "$STATE_DIR/agent"
printf 'external-draft\n' > "$STATE_DIR/agent/selected-profile"
PATH="$FAKE_BIN:$PATH" run_manager status --json > "$TEMP_DIR/status.json"
python3 - "$TEMP_DIR/status.json" "$MMPROJ_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as status_file:
    status = json.load(status_file)

instances = status["instances"]
assert set(instances) == {"worker", "agent"}
worker = instances["worker"]
agent = instances["agent"]
assert worker["context_total"] == 131072
assert worker["parallel_slots"] == 2
assert worker["context_per_slot"] == 65536
assert agent["context_total"] == 65536
assert agent["parallel_slots"] == 1
assert agent["context_per_slot"] == 65536
assert worker["mmproj"] is None
assert agent["mmproj"] == sys.argv[2]
for instance in instances.values():
    for field in ("context_total", "parallel_slots", "context_per_slot", "port", "pid"):
        assert isinstance(instance[field], int), (field, instance[field])
assert worker["draft_model"] is None
PY
PATH="$FAKE_BIN:$PATH" run_manager status worker --json > "$TEMP_DIR/worker-status.json"
python3 - "$TEMP_DIR/worker-status.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as status_file:
    assert set(json.load(status_file)["instances"]) == {"worker"}
PY
rm -f -- "$STATE_DIR/agent/selected-profile"
PATH="$FAKE_BIN:$PATH" run_manager status agent --json > "$TEMP_DIR/unselected-agent-status.json"
grep -Fq '"profile": null' "$TEMP_DIR/unselected-agent-status.json"
grep -Fq '"context_total": null' "$TEMP_DIR/unselected-agent-status.json"
printf 'good\n' > "$STATE_DIR/worker/selected-profile"

printf 'external-draft\n' > "$STATE_DIR/worker/selected-profile"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"Draft model: draft.gguf"* ]]
[[ "$status_output" == *"MMProj: mmproj.gguf"* ]]
printf 'good\n' > "$STATE_DIR/worker/selected-profile"

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"data":[{"id":"another-model.gguf"}]}'
EOF
chmod +x "$FAKE_BIN/curl"
status_output=$(PATH="$FAKE_BIN:$PATH" run_manager status)
[[ "$status_output" == *"API: not-ready"* ]]

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

# Named instances keep selections separate, override the profile port, and
# retain the old global selection as worker state on first use.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
printf 'good\n' > "$STATE_DIR/selected-profile"
EVO_MODEL_TEST_COUNTER="$TEMP_DIR/migration-count" PATH="$FAKE_BIN:$PATH" run_manager status worker > "$TEMP_DIR/worker-status"
[[ -f "$STATE_DIR/worker/selected-profile" && ! -e "$STATE_DIR/selected-profile" ]]
mkdir -p "$STATE_DIR/agent"
printf 'external-draft\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/agent-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected agent
grep -Fxq 'llama-vulkan-radv' "$TEMP_DIR/agent-args"
grep -Fxq -- '8081' "$TEMP_DIR/agent-args"
EVO_MODEL_TEST_ARGS="$TEMP_DIR/worker-args" PATH="$FAKE_BIN:$PATH" run_manager run-selected worker
grep -Fxq 'llama-vulkan-worker' "$TEMP_DIR/worker-args"
if grep -q 'llama-vulkan-radv' "$TEMP_DIR/worker-args"; then
  echo "worker used agent container" >&2
  exit 1
fi
grep -Fxq 'good' "$STATE_DIR/worker/selected-profile"
grep -Fxq 'external-draft' "$STATE_DIR/agent/selected-profile"
printf 'good\n' > "$STATE_DIR/agent/selected-profile"
same_profile_list=$(PATH="$FAKE_BIN:$PATH" run_manager list)
grep -Fxq 'good                     selected:worker,agent' <<<"$same_profile_list"
printf 'external-draft\n' > "$STATE_DIR/agent/selected-profile"
EVO_MODEL_TEST_COUNTER="$TEMP_DIR/two-status-count" PATH="$FAKE_BIN:$PATH" run_manager status > "$TEMP_DIR/two-status"
grep -Fq 'Instance: worker' "$TEMP_DIR/two-status"
grep -Fq 'Instance: agent' "$TEMP_DIR/two-status"
grep -Fq 'Port: 8080' "$TEMP_DIR/two-status"
grep -Fq 'Port: 8081' "$TEMP_DIR/two-status"
grep -Fq 'Container: llama-vulkan-worker' "$TEMP_DIR/two-status"
grep -Fq 'Container: llama-vulkan-radv' "$TEMP_DIR/two-status"
if PATH="$FAKE_BIN:$PATH" run_manager status invalid >/dev/null 2>&1; then
  echo "expected invalid instance to fail" >&2
  exit 1
fi

# Instance operations must only address their own systemd unit, lock, and
# journal. A worker lock must not prevent a legitimate agent operation.
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVO_MODEL_TEST_SYSTEMCTL_LOG"
if [[ "$*" == *"is-active"* ]]; then
  exit 0
fi
if [[ "$*" == *"show"* ]]; then
  printf '123\n'
fi
EOF
cat > "$FAKE_BIN/journalctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$EVO_MODEL_TEST_JOURNAL_LOG"
EOF
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/journalctl"
printf 'good\n' > "$STATE_DIR/worker/selected-profile"
printf 'external-draft\n' > "$STATE_DIR/agent/selected-profile"

EVO_MODEL_TEST_SYSTEMCTL_LOG="$TEMP_DIR/worker-stop.log" PATH="$FAKE_BIN:$PATH" \
  run_manager stop worker >/dev/null
grep -Fxq -- '--user stop evo-model@worker.service' "$TEMP_DIR/worker-stop.log"
if grep -q 'agent' "$TEMP_DIR/worker-stop.log"; then
  echo "worker stop addressed agent service" >&2
  exit 1
fi

mkdir -p "$STATE_DIR/worker"
exec 8>"$STATE_DIR/worker/manager.lock"
flock -n 8
if PATH="$FAKE_BIN:$PATH" run_manager stop worker >/dev/null 2>&1; then
  echo "expected worker operation to respect worker lock" >&2
  exit 1
fi
EVO_MODEL_TEST_SYSTEMCTL_LOG="$TEMP_DIR/agent-stop.log" PATH="$FAKE_BIN:$PATH" \
  run_manager stop agent >/dev/null
flock -u 8
exec 8>&-
grep -Fxq -- '--user stop evo-model@agent.service' "$TEMP_DIR/agent-stop.log"

EVO_MODEL_TEST_JOURNAL_LOG="$TEMP_DIR/worker-journal.log" PATH="$FAKE_BIN:$PATH" \
  run_manager logs worker >/dev/null
grep -Fxq -- '--user -u evo-model@worker.service --no-pager' "$TEMP_DIR/worker-journal.log"
EVO_MODEL_TEST_JOURNAL_LOG="$TEMP_DIR/agent-journal.log" PATH="$FAKE_BIN:$PATH" \
  run_manager logs agent -f >/dev/null
grep -Fxq -- '--user -u evo-model@agent.service -f' "$TEMP_DIR/agent-journal.log"

EVO_MODEL_TEST_SYSTEMCTL_LOG="$TEMP_DIR/worker-start.log" PATH="$FAKE_BIN:$PATH" \
  run_manager start worker good >/dev/null
grep -Fxq -- '--user start evo-model@worker.service' "$TEMP_DIR/worker-start.log"
if grep -q 'evo-model@agent.service' "$TEMP_DIR/worker-start.log"; then
  echo "worker start addressed agent service" >&2
  exit 1
fi
EVO_MODEL_TEST_SYSTEMCTL_LOG="$TEMP_DIR/agent-restart.log" PATH="$FAKE_BIN:$PATH" \
  run_manager restart agent >/dev/null
grep -Fxq -- '--user stop evo-model@agent.service' "$TEMP_DIR/agent-restart.log"
grep -Fxq -- '--user start evo-model@agent.service' "$TEMP_DIR/agent-restart.log"
if grep -q 'evo-model@worker.service' "$TEMP_DIR/agent-restart.log"; then
  echo "agent restart addressed worker service" >&2
  exit 1
fi

echo "evo-model profile validation tests passed"
