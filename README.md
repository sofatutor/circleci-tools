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

## Contributing

We welcome contributions to enhance the functionality of CircleCI Tools. Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes with clear commit messages.
4. Push your changes to your fork.
5. Open a pull request with a detailed description of your changes.

## License

This project is licensed under the MIT License.
