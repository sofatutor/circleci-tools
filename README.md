# CircleCI Tools

CircleCI Tools is a collection of utilities designed to enhance and streamline your CircleCI workflows. This CLI provides various commands to evaluate concurrency requirements, aggregate data, upload metrics, and generate usage reports.

## Installation

To set up the project, follow these steps:

1. Clone the repository:
   ```bash
   git clone https://github.com/sofatutor/circleci-tools.git
   cd circleci-tools
   ```

2. Install the dependencies:
   ```bash
   bundle install
   ```

## Usage

The CLI provides the following commands:

- **evaluate**: Evaluate concurrency requirements for self-hosted runners.
  ```bash
  bin/circleci-metrics evaluate --org=ORG_NAME --project=PROJECT_NAME
  ```

- **aggregate**: Aggregate data from an existing jobs JSON file.
  ```bash
  bin/circleci-metrics aggregate --jobs_json=JOBS_JSON_PATH
  ```

- **upload**: Store aggregated CSV data into SQLite database for analysis.
  ```bash
  bin/circleci-metrics upload --csv_file_path=CSV_FILE_PATH
  ```

- **usage_report**: Create usage export job, download CSV, and upload to cloudwatch metrics (CircleCI/<PROJECT_NAME>)/s3
  ```bash
  bin/circleci-metrics usage_report --org_id=CIRCLECI_ORG_ID --days_ago=1 --upload --s3_bucket=CI_LOG_BUCKET
  ```

- **upload_metrics**: Upload CloudWatch metrics from CSV file.
  ```bash
  bin/circleci-metrics upload_metrics --csv_file_path=CSV_FILE_PATH
  ```

### KPI Analysis (`bin/circleci-kpis`)

Calculate CircleCI KPIs (P95 run time, success rate, cost estimates) for a project. Fetches hundreds of runs and thousands of jobs in parallel and reports aggregate metrics.

Authorize by setting `CIRCLECI_TOKEN` (or `CIRCLE_CI_API_TOKEN` / `CIRCLE_TOKEN`) or by running `circleci setup` (`brew install circleci`) which writes `~/.circleci/cli.yml`.

```
Usage: bin/circleci-kpis project [options]
    -d, --days DAYS                  Load workflows from the last N days (default: 7)
    -W, --week WEEK                  Load workflows from ISO calendar week N of the current year (overrides --days)
    -o, --org ORG                    CircleCI organization/user (default: sofatutor)
    -b, --branch BRANCH              Branch to filter (default: main)
    -a, --all                        Don't filter by branch (overrides --branch)
    -w, --workflow WORKFLOW          Workflow name (inferred for some projects on main or all branches)
    -l, --links                      Append CircleCI links to run rows (implies --verbose)
    -B, --show-branch                Append the branch name to run rows (implies --verbose)
    -v, --verbose                    Print the list of runs before aggregates
    -h, --help                       Show help
```

Examples:

```bash
bin/circleci-kpis main -vd3           # sofatutor, last 3 days, verbose
bin/circleci-kpis kids --week 22      # sofatutor-kids, calendar week 22
bin/circleci-kpis SPASS --days 14     # SPASS project, last 14 days
```

### Skipping CI-irrelevant runs (`bin/check_skip.rb`)

Decides whether the current commit changed anything CI cares about, and stops the
run if not. Consumed over raw.githubusercontent by the app repos rather than
shipped as a gem executable, because it has to run before bundler is available:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sofatutor/circleci-tools/<SHA-OR-TAG>/bin/check_skip.rb \
  -o .circleci/tools/check_skip.rb
ruby .circleci/tools/check_skip.rb && rm -f .circleci/tools/check_skip.rb
```

Pin to a SHA or tag. This script decides whether tests run at all, so an
unpinned `refs/heads/main` fetch lets one push here change CI in every consumer.

Configuration is entirely by environment:

| Variable | Purpose |
| --- | --- |
| `CI_SKIP_FILE` | Path to a gitignore-style file, one rule per line; `#` comments and blank lines ignored. |
| `CI_SKIP_PATHS` | Inline rules — comma-separated, whitespace-separated, or a JSON array. |
| `CI_SKIP_ACTION` | `cancel` (default) or `halt`. See below. |

Rules from both sources are combined. The run is skipped only when **every**
changed file matches at least one rule. With no rules at all, nothing is ever
skipped.

Matching follows gitignore conventions: `docs` and `docs/` both match the
directory and everything under it; `*` does not cross a `/`, but a pattern
containing no `/` is also tried against the basename, so `*.md` matches
`docs/guide.md`. Brace alternation works — `*.{md,mdc,markdown}`.

**`CI_SKIP_ACTION` picks how the run is stopped**, which depends on where the
step sits in the workflow:

- `cancel` — cancels the whole workflow through the CircleCI API. Use when the
  step lives inside a job that other jobs `require:`, since ending that job
  successfully would just let its dependents run. Needs `CIRCLE_CI_API_TOKEN`.
  The pipeline ends up in the *canceled* state.
- `halt` — ends only the current job, green, via `circleci-agent step halt`.
  Remaining steps in that job do not run. Use when the step lives in a gate job
  nothing depends on — notably a dynamic-config setup job, where halting means
  the continuation config is never submitted and no downstream job is created.

Anything short of a definite "skip" exits 0 and lets the build continue: an
unreachable API, a missing token, an absent `circleci-agent`, or an
undeterminable base commit all fail towards running the tests.

## Contributing

We welcome contributions to enhance the functionality of CircleCI Tools. Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes with clear commit messages.
4. Push your changes to your fork.
5. Open a pull request with a detailed description of your changes.

## License

This project is licensed under the MIT License.
