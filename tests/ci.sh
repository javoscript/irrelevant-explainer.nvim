#!/usr/bin/env bash
# Run from the repository root: bash tests/ci.sh base|integration|secrets.
# Downloads belong to workflow setup; these commands also work offline locally.
set -euo pipefail

mode=${1:-}
case "$mode" in
  base|integration|secrets) ;;
  *) echo 'Usage: bash tests/ci.sh base|integration|secrets' >&2; exit 2 ;;
esac
test -f tests/run.lua || { echo 'Run from the repository root' >&2; exit 2; }
scratch=$(mktemp -d "${TMPDIR:-/tmp}/irrelevant-explainer-ci.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

if [[ "$mode" == secrets ]]; then
  scanner=${IRRELEVANT_EXPLAINER_GITLEAKS:-gitleaks}
  [[ "$("$scanner" version)" == '8.30.1' ]] || { echo 'Gitleaks 8.30.1 required' >&2; exit 1; }
  [[ "$(git rev-parse --is-shallow-repository)" == false ]] || { echo 'Full history required' >&2; exit 1; }
  git rev-list --objects --all --missing=print > "$scratch/objects"
  if grep '^?' "$scratch/objects" > /dev/null; then
    echo 'Missing historical objects; fetch complete history before scanning' >&2
    exit 1
  fi
  # Export current tracked + nonignored untracked files, including additions not
  # yet staged. Tracked files remain in scope even if an ignore rule matches.
  # Deleted paths are absent from the candidate but covered by the history scan.
  python3 - "$scratch/candidate" <<'PY'
import os
import pathlib
import shutil
import subprocess
import sys

target = pathlib.Path(sys.argv[1])
target.mkdir()
paths = subprocess.check_output([
    "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
]).split(b"\0")
for raw in sorted(set(paths) - {b""}):
    source = pathlib.Path(os.fsdecode(raw))
    if not source.exists() and not source.is_symlink():
        continue
    destination = target / source
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        # Git stores the link text, not the possibly private external target.
        destination.write_bytes(os.fsencode(os.readlink(source)))
    elif source.is_file():
        shutil.copyfile(source, destination)
    else:
        raise SystemExit(f"Unsupported candidate entry (e.g. submodule): {source}")
PY
  # Force bundled default rules, no repository/env config or inline/ignore-file
  # suppression. Keep output redacted and do not write/upload finding reports.
  unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
  printf '[extend]\nuseDefault = true\n' > "$scratch/gitleaks.toml"
  : > "$scratch/empty.ignore"
  flags=(--config "$scratch/gitleaks.toml" --gitleaks-ignore-path "$scratch/empty.ignore"
    --ignore-gitleaks-allow --redact=100 --no-banner --no-color)
  status=0
  "$scanner" dir "${flags[@]}" "$scratch/candidate" || status=1
  "$scanner" git "${flags[@]}" --log-opts='--all --full-history --root' . || status=1
  exit "$status"
fi

nvim=${IRRELEVANT_EXPLAINER_NVIM:-nvim}
command -v python3 > /dev/null
git --version
python3 --version
"$nvim" --version | sed -n '1,3p'
# Never read an installed personal runtime or persist into a user's cache.
export XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data"
export XDG_STATE_HOME="$scratch/state" XDG_CACHE_HOME="$scratch/cache"
export IRRELEVANT_EXPLAINER_TEST_CACHE_ROOT="$XDG_CACHE_HOME"
mkdir -p "$XDG_CACHE_HOME"
export IRRELEVANT_EXPLAINER_TEST='tests/*_test.lua'
unset IRRELEVANT_EXPLAINER_DIFFVIEW_CHILD IRRELEVANT_EXPLAINER_COMMAND_CHILD

if [[ "$mode" == integration ]]; then
  : "${IRRELEVANT_EXPLAINER_DIFFVIEW_PATH:?Set the pinned Diffview runtime path}"
  : "${IRRELEVANT_EXPLAINER_PLENARY_PATH:?Set the pinned Plenary runtime path}"
  for dependency in "$IRRELEVANT_EXPLAINER_DIFFVIEW_PATH/lua/diffview" "$IRRELEVANT_EXPLAINER_PLENARY_PATH/lua/plenary"; do
    [[ -d "$dependency" ]] || { echo "Missing integration runtime: $dependency" >&2; exit 1; }
  done
  # Separate editor: preflight must not invalidate tests asserting lazy loading.
  "$nvim" --headless -u NONE -i NONE -n -c 'lua local ok, err = pcall(function() vim.opt.runtimepath:append(vim.env.IRRELEVANT_EXPLAINER_DIFFVIEW_PATH); vim.opt.runtimepath:append(vim.env.IRRELEVANT_EXPLAINER_PLENARY_PATH); require("plenary.async"); assert(require("diffview").setup, "Diffview bootstrap failed"); require("diffview.lib") end); if not ok then print(err); vim.cmd("cquit 1") end' -c 'qa!'
else
  export IRRELEVANT_EXPLAINER_DIFFVIEW_PATH="$scratch/absent-diffview"
  export IRRELEVANT_EXPLAINER_PLENARY_PATH="$scratch/absent-plenary"
fi

"$nvim" --headless -u NONE -i NONE -n -c 'luafile tests/run.lua' 2>&1 | tee "$scratch/tests.log"
grep -Eq '[1-9][0-9]* passed, 0 failed' "$scratch/tests.log" || { echo 'No successful test summary' >&2; exit 1; }
if [[ "$mode" == integration ]] && grep -Eiq 'SKIP.*(Diffview|integration|missing (dependency|runtime))' "$scratch/tests.log"; then
  echo 'Required integration coverage was skipped' >&2
  exit 1
fi
