#!/usr/bin/env bash
# Lists Python venvs whose interpreter no longer starts, for example after brew upgrade removes the
# Cellar path a venv was copied from. Exit 1 when any venv is broken.
set -uo pipefail

roots=(
  "$HOME/.local/share/mise/installs"
  "$HOME/.local/share/uv/tools"
  "$HOME/.cache/pre-commit"
  "$HOME/Library/Caches/pypoetry/virtualenvs"
  "$HOME/Projects"
)

broken_count=0
while IFS= read -r cfg; do
  venv="${cfg%/pyvenv.cfg}"
  python_bin="$venv/bin/python"
  [ -e "$python_bin" ] || python_bin="$venv/bin/python3"
  "$python_bin" -c pass >/dev/null 2>&1 && continue
  broken_count=$((broken_count + 1))
  echo "BROKEN ${venv/#"$HOME"/\~} (home: $(sed -nE 's/^home *= *//p' "$cfg"))"
done < <(find "${roots[@]}" -maxdepth 6 -name pyvenv.cfg 2>/dev/null)

[ "$broken_count" -eq 0 ] && exit 0
echo "fix: mise tool -> mise install --force <tool>@<version> | repo .venv -> rm -rf .venv, reinstall | pre-commit -> pre-commit clean"
exit 1
