require 'spec_helper'
require 's3_upload_service'

RSpec.describe CircleciTools::S3UploadService do
  let(:service) { described_class.new('test_bucket') }

  describe '#upload_file' do
    it 'uploads a file successfully' do
      file_path = 'path/to/test_file.csv' # Mock or provide a sample file path
      expect { service.upload_file(file_path, 'test_key') }.not_to raise_error
    end
  end

  # Add more tests for other methods in S3UploadService
end
