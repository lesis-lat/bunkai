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
github_token="$(read_input INPUT_GITHUB_TOKEN INPUT_GITHUB-TOKEN '')"
create_prs="$(read_input INPUT_CREATE_PRS INPUT_CREATE-PRS true)"
close_resolved_prs="$(read_input INPUT_CLOSE_RESOLVED_PRS INPUT_CLOSE-RESOLVED-PRS true)"
dedupe_updates="$(read_input INPUT_DEDUPE_UPDATES INPUT_DEDUPE-UPDATES true)"
pr_branch_prefix="$(read_input INPUT_PR_BRANCH_PREFIX INPUT_PR-BRANCH-PREFIX bunkai)"
pr_labels="$(read_input INPUT_PR_LABELS INPUT_PR-LABELS dependencies,security)"

get_gh_token() {
  if [ -n "${github_token// }" ]; then
    printf '%s' "$github_token"
    return
  fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    printf '%s' "$GITHUB_TOKEN"
    return
  fi
  printf '%s' ''
}

print_orchestrate_pr_body() {
  local issue_id="$1"
  local module="$2"
  local current_version="$3"
  local target_version="$4"
  local reason="$5"
  local advisory_id="$6"
  cat <<EOF
Automated by Bunkai.

Issue ID: \`$issue_id\`
Module: \`$module\`
Current version: \`${current_version:-unversioned}\`
Target version: \`$target_version\`
Reason: \`$reason\`
Advisory: \`${advisory_id:-n/a}\`
EOF
}

run_orchestrate() {
  local gh_token
  gh_token="$(get_gh_token)"

  local scan_exit=0
  if [ -n "$sarif_output" ]; then
    perl /app/bunkai.pl --path "$project_path" --sarif "$sarif_output" || scan_exit=$?
  else
    perl /app/bunkai.pl --path "$project_path" || scan_exit=$?
  fi

  perl /app/bunkai.pl --path "$project_path" --plan-updates "$plan_output_file"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'plan-output-file=%s\n' "$plan_output_file" >>"$GITHUB_OUTPUT"
  fi

  if [ "${create_prs,,}" = "true" ] || [ "${close_resolved_prs,,}" = "true" ]; then
    if [ -z "${GITHUB_REPOSITORY:-}" ]; then
      echo "Error: GITHUB_REPOSITORY is required for orchestrate PR operations." >&2
      exit 1
    fi
    if [ -z "$gh_token" ]; then
      echo "Error: github-token input (or GITHUB_TOKEN env) is required for orchestrate PR operations." >&2
      exit 1
    fi
  fi

  local cpanfile_path="$project_path/cpanfile"
  if [ ! -f "$cpanfile_path" ]; then
    echo "Warning: cpanfile not found at '$cpanfile_path'; skipping PR operations." >&2
    return "$scan_exit"
  fi

  local updates_json='[]'
  if [ -f "$plan_output_file" ]; then
    if [ "${dedupe_updates,,}" = "true" ]; then
      updates_json="$(jq -c '
        .issues // []
        | sort_by(.module, .target_version, (.reason != "vulnerability_fix"))
        | group_by(.module + "|" + (.target_version // ""))
        | map((map(select(.reason == "vulnerability_fix"))[0]) // .[0])
      ' "$plan_output_file")"
    else
      updates_json="$(jq -c '.issues // []' "$plan_output_file")"
    fi
  fi

  if [ "${create_prs,,}" = "true" ]; then
    export GH_TOKEN="$gh_token"
    local base_branch="${GITHUB_REF_NAME:-main}"
    local branch_prefix="$pr_branch_prefix"
    local label_csv="$pr_labels"
    local cpanfile_rel="$cpanfile_path"
    cpanfile_rel="${cpanfile_rel#./}"

    local original_cpanfile
    original_cpanfile="$(cat "$cpanfile_path")"

    if [ -n "${GITHUB_WORKSPACE:-}" ]; then
      git config --global --add safe.directory "$GITHUB_WORKSPACE"
    fi
    git fetch origin "$base_branch"
    git checkout -B "$base_branch" "origin/$base_branch"

    while IFS=$'\t' read -r issue_id module current_version target_version reason advisory_id; do
      if [ -z "${issue_id// }" ]; then
        continue
      fi

      printf '%s' "$original_cpanfile" >"$cpanfile_path"

      perl /app/bunkai.pl --path "$project_path" --apply-update-id "$issue_id" >/tmp/bunkai-apply.log 2>&1 || true

      if cmp -s "$cpanfile_path" <(printf '%s' "$original_cpanfile"); then
        continue
      fi

      local branch_name="${branch_prefix}/${issue_id}"
      git checkout "$base_branch"
      git checkout -B "$branch_name" "$base_branch"
      git add "$cpanfile_rel"

      if git diff --cached --quiet -- "$cpanfile_rel"; then
        git checkout "$base_branch"
        continue
      fi

      git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        commit -m "chore(deps): apply Bunkai fix $issue_id"

      # Another workflow run may update the same branch between fetch and push.
      # Retry with --force so the orchestrator can converge branch state.
      if ! git push --force-with-lease origin "$branch_name"; then
        git push --force origin "$branch_name"
      fi

      local pr_title="chore(deps): Bunkai fix for ${module} (${reason})"
      local pr_body
      pr_body="$(print_orchestrate_pr_body "$issue_id" "$module" "$current_version" "$target_version" "$reason" "$advisory_id")"

      local existing_pr_number
      existing_pr_number="$(gh pr list \
        --repo "$GITHUB_REPOSITORY" \
        --state open \
        --head "$branch_name" \
        --json number \
        --jq '.[0].number // empty')"

      local pr_number="$existing_pr_number"
      if [ -n "$existing_pr_number" ]; then
        gh pr edit "$existing_pr_number" \
          --repo "$GITHUB_REPOSITORY" \
          --title "$pr_title" \
          --body "$pr_body"
      else
        gh pr create \
          --repo "$GITHUB_REPOSITORY" \
          --base "$base_branch" \
          --head "$branch_name" \
          --title "$pr_title" \
          --body "$pr_body"
        pr_number="$(gh pr list \
          --repo "$GITHUB_REPOSITORY" \
          --state open \
          --head "$branch_name" \
          --json number \
          --jq '.[0].number // empty')"
      fi

      if [ -n "${label_csv// }" ]; then
        IFS=',' read -r -a labels_array <<<"$label_csv"
        for label in "${labels_array[@]}"; do
          label="${label#"${label%%[![:space:]]*}"}"
          label="${label%"${label##*[![:space:]]}"}"
          if [ -n "$label" ]; then
            gh pr edit "$pr_number" --repo "$GITHUB_REPOSITORY" --add-label "$label" || true
          fi
        done
      fi

      git checkout "$base_branch"
    done < <(
      jq -r '.[] | [
        (.id // ""),
        (.module // ""),
        (.current_version // ""),
        (.target_version // ""),
        (.reason // ""),
        (.advisory_id // "")
      ] | @tsv' <<<"$updates_json"
    )
  fi

  if [ "${close_resolved_prs,,}" = "true" ]; then
    export GH_TOKEN="$gh_token"
    local active_branches
    active_branches="$(
      jq -r --arg prefix "$pr_branch_prefix" '.[] | .id // empty | "\($prefix)/\(.)"' <<<"$updates_json"
    )"

    while IFS=$'\t' read -r pr_number pr_branch; do
      if [ -z "${pr_number// }" ] || [ -z "${pr_branch// }" ]; then
        continue
      fi
      if ! grep -Fxq "$pr_branch" <<<"$active_branches"; then
        gh pr comment "$pr_number" --repo "$GITHUB_REPOSITORY" \
          --body "Closing automatically: this Bunkai issue is not present in the latest scan plan."
        gh pr close "$pr_number" --repo "$GITHUB_REPOSITORY" --delete-branch || true
      fi
    done < <(
      gh pr list \
        --repo "$GITHUB_REPOSITORY" \
        --state open \
        --limit 200 \
        --json number,headRefName \
        --jq '.[] | select(.headRefName | startswith("'"$pr_branch_prefix"'/")) | [.number, .headRefName] | @tsv'
    )
  fi

  return "$scan_exit"
}

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
  orchestrate)
    run_orchestrate
    ;;
  *)
    echo "Error: unsupported mode '$mode'. Use scan, plan, apply, update, or orchestrate." >&2
    exit 1
    ;;
esac
