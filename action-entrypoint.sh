#!/usr/bin/env bash
set -euo pipefail

read_input() {
  local underscore_name="$1"
  local hyphen_name="$2"
  local default_value="$3"
  local value="${!underscore_name:-}"

  if [ -z "${value// }" ] && [ -n "$hyphen_name" ]; then
    value="$(printenv "$hyphen_name" 2>/dev/null || true)"
  fi

  if [ -z "${value// }" ]; then
    value="$default_value"
  fi

  printf '%s' "$value"
}

project_path="$(read_input INPUT_PROJECT_PATH INPUT_PROJECT-PATH .)"
mode="$(read_input INPUT_MODE '' scan)"
install_project_deps="$(read_input INPUT_INSTALL_PROJECT_DEPS INPUT_INSTALL-PROJECT-DEPS false)"
plan_output_file="$(read_input INPUT_PLAN_OUTPUT_FILE INPUT_PLAN-OUTPUT-FILE bunkai-updates.json)"
apply_update_id="$(read_input INPUT_APPLY_UPDATE_ID INPUT_APPLY-UPDATE-ID '')"
perlcritic_severity="$(read_input INPUT_PERLCRITIC_SEVERITY INPUT_PERLCRITIC-SEVERITY 1)"
perlcritic_paths="$(read_input INPUT_PERLCRITIC_PATHS INPUT_PERLCRITIC-PATHS '')"
sarif_output="$(read_input INPUT_SARIF_OUTPUT INPUT_SARIF-OUTPUT '')"
test_command="$(read_input INPUT_TEST_COMMAND INPUT_TEST-COMMAND '')"

if [ "${install_project_deps,,}" = "true" ]; then
  cpanm --installdeps --with-develop "$project_path"
fi

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
