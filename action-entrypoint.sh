set -euo pipefail

project_path="${INPUT_PROJECT_PATH:-.}"
perlcritic_severity="${INPUT_PERLCRITIC_SEVERITY:-1}"
perlcritic_paths="${INPUT_PERLCRITIC_PATHS:-lib bunkai.pl}"
sarif_output="${INPUT_SARIF_OUTPUT:-}"
test_command="${INPUT_TEST_COMMAND:-PERL5OPT=-MDevel::Cover=-db,coverage_db,-silent,1 prove -lvr tests/
cover -report text
cover -test}"

cpanm --installdeps --with-develop "$project_path"

perlcritic --severity "$perlcritic_severity" $perlcritic_paths

bash -lc "$test_command"

if [ -n "$sarif_output" ]; then
  perl /app/bunkai.pl --path "$project_path" --sarif "$sarif_output"
  exit 0
fi

perl /app/bunkai.pl --path "$project_path"
