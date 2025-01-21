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

## Contributing

We welcome contributions to enhance the functionality of CircleCI Tools. Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes with clear commit messages.
4. Push your changes to your fork.
5. Open a pull request with a detailed description of your changes.

## License

This project is licensed under the MIT License.
