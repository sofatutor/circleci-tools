require 'aws-sdk-s3'
require 'logger'

module CircleciTools
  class S3UploadService
    def initialize(bucket_name, logger: Logger.new(STDOUT))
      @bucket_name = bucket_name
      @logger = logger
      @s3_client = Aws::S3::Client.new
    end

    def upload_file(file_path, s3_key)
      @logger.info("Uploading #{file_path} to S3 bucket #{@bucket_name} with key #{s3_key}...")
      @s3_client.put_object(bucket: @bucket_name, key: "circleci/#{s3_key}", body: File.read(file_path))
      @logger.info("Uploaded #{file_path} to S3 bucket #{@bucket_name} with key #{s3_key}.")
    rescue Aws::S3::Errors::ServiceError => e
      @logger.error("Failed to upload #{file_path} to S3: #{e.message}")
    end
  end
end
