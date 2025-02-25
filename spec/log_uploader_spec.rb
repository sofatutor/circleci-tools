require 'spec_helper'
require 'log_uploader'

RSpec.describe CircleciTools::LogUploader do
  let(:uploader) { described_class.new('test_log_group') }

  describe '#upload_file' do
    it 'uploads a file successfully' do
      csv_file_path = 'path/to/test_file.csv' # Mock or provide a sample file path
      expect { uploader.upload_file(csv_file_path) }.not_to raise_error
    end
  end

  # Add more tests for other methods in LogUploader
end
