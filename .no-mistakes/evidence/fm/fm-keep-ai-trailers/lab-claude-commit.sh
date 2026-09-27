#!/usr/bin/env bash
# Live lab: real fm-spawn emits the claude launch; the real Claude CLI runs it in a private tmux pane
# (lab socket, private CLAUDE_CONFIG_DIR holding a copy of the machine login) and commits a file.
set -u
ROOT=$PWD; . "$ROOT/tests/fixtures.sh"; fail() { echo "FAIL: $*"; exit 1; }
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); mkdir -p "$LAB/tmux"
cleanup() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null; chmod -R u+w "$LAB"; rm -rf "$LAB"; }; trap cleanup EXIT
T() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab "$@"; }
run_case() {  # <label> <keep>
  local label=$1 keep=$2; local H="$LAB/$label/home" PROJ="$LAB/$label/proj" WT="$LAB/$label/wt" ID="claude-$label-z1" CC="$LAB/$label/cc" fakebin out i
  "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null; fm_test_spawn_home "$H" claude
  fm_git_worktree "$PROJ" "$WT" "fm/$ID"
  git -C "$WT" config user.name 'Lab Captain'; git -C "$WT" config user.email lab@example.invalid
  mkdir -p "$CC"; cp ~/.claude/.credentials.json "$CC/"; chmod 600 "$CC/.credentials.json"
  printf '{"hasCompletedOnboarding":true,"theme":"dark"}\n' > "$CC/.claude.json"; printf '{"skipDangerousModePermissionPrompt":true}\n' > "$CC/settings.json"
  [ "$keep" = 1 ] && : > "$H/config/keep-ai-trailers"
  fm_test_spawn_brief "$H" "$ID" "Lab verification only: create a file named lab.txt containing the word hello, then git add it and git commit it with the message 'chore: add lab file' using your default commit conventions. Do nothing else, do not push, and then stop."
  fakebin=$(make_spawn_fakebin "$LAB/$label/fake")
  out=$(FM_TEST_CLAUDE_CONFIG_DIR="$CC" FM_FAKE_LAUNCH_LOG="$LAB/$label/launch.sh" fm_test_run_spawn "$H" "$WT" "$fakebin" "$ID" "$PROJ" claude --model sonnet --mode local-only --yolo on 2>&1) || fail "spawn: $out"
  echo "== [$label] keep-ai-trailers=$keep"
  echo "-- --settings JSON in emitted claude launch: $(grep -o "\-\-settings '[^']*'" "$LAB/$label/launch.sh")"
  echo "-- core.hooksPath override exported: $(grep -q GIT_CONFIG_KEY_0=core.hooksPath "$LAB/$label/launch.sh" && echo yes || echo no)"
  T new-session -d -s "$label" -x 160 -y 45 -c "$WT" "env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 FM_HOME='$H' CLAUDE_CONFIG_DIR='$CC' bash -c \"\$(cat '$LAB/$label/launch.sh')\"; sleep 600"
  for i in $(seq 1 360); do
    [ "$(git -C "$WT" rev-list --count HEAD)" -gt 1 ] && break
    scr=$(T capture-pane -p -t "$label")
    if printf '%s' "$scr" | grep -q 'Yes, I accept'; then T send-keys -t "$label" Down; sleep 0.3; T send-keys -t "$label" Enter
    elif printf '%s' "$scr" | grep -qE 'Do you trust|Yes, I trust'; then T send-keys -t "$label" Enter; fi
    sleep 1
  done
  T capture-pane -p -t "$label" > "$LAB/$label/pane.txt"; cp "$LAB/$label/pane.txt" "$EVDIR/claude-$label-pane.txt"
  echo "-- resulting commit message:"; git -C "$WT" log -1 --format=%B; echo
  T kill-session -t "$label"
}
run_case keep 1
run_case default 0
