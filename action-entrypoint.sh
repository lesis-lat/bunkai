#!/usr/bin/env bash
set -euo pipefail

project_path="${INPUT_PROJECT_PATH:-.}"
mode="${INPUT_MODE:-scan}"
plan_output_file="${INPUT_PLAN_OUTPUT_FILE:-bunkai-updates.json}"
apply_update_id="${INPUT_APPLY_UPDATE_ID:-}"
perlcritic_severity="${INPUT_PERLCRITIC_SEVERITY:-1}"
perlcritic_paths="${INPUT_PERLCRITIC_PATHS:-}"
sarif_output="${INPUT_SARIF_OUTPUT:-}"
test_command="${INPUT_TEST_COMMAND:-}"

cpanm --installdeps --with-develop "$project_path"

if [ -n "${perlcritic_paths// }" ]; then
  # Split configured paths into separate CLI args.
  read -r -a perlcritic_paths_array <<<"$perlcritic_paths"
  (
    cd "$project_path"
    perlcritic --severity "$perlcritic_severity" "${perlcritic_paths_array[@]}"
  )
fi

if [ -n "${test_command// }" ]; then
  (
    cd "$project_path"
    bash -lc "$test_command"
  )
fi

case "$mode" in
  scan)
    if [ -n "$sarif_output" ]; then
      perl /app/bunkai.pl --path "$project_path" --sarif "$sarif_output"
    else
      perl /app/bunkai.pl --path "$project_path"
    fi
    ;;
  plan)
    perl /app/bunkai.pl --path "$project_path" --plan-updates "$plan_output_file"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      printf 'plan-output-file=%s\n' "$plan_output_file" >>"$GITHUB_OUTPUT"
    fi
    ;;
  apply)
    if [ -z "${apply_update_id// }" ]; then
      echo "Error: INPUT_APPLY_UPDATE_ID is required when mode=apply." >&2
      exit 1
    fi
    perl /app/bunkai.pl --path "$project_path" --apply-update-id "$apply_update_id"
    ;;
  update)
    perl /app/bunkai.pl --path "$project_path" --update-cpanfile
    ;;
  *)
    echo "Error: unsupported mode '$mode'. Use scan, plan, apply, or update." >&2
    exit 1
    ;;
esac
