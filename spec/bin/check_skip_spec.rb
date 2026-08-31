require_relative '../../bin/check_skip'

RSpec.describe CheckSkip do
  subject(:checker) { described_class.new }

  describe '#path_matches?' do
    it 'matches a directory rule against the directory itself' do
      expect(checker.path_matches?('docs', 'docs/')).to be true
    end

    it 'matches a directory rule against nested files' do
      expect(checker.path_matches?('docs/guides/a.txt', 'docs')).to be true
    end

    it 'does not match a directory rule against a same-prefixed sibling' do
      expect(checker.path_matches?('docsite/a.txt', 'docs')).to be false
    end

    it 'matches a bare glob against a basename at any depth' do
      expect(checker.path_matches?('docs/guides/a.md', '*.md')).to be true
    end

    it 'expands brace alternation' do
      expect(checker.path_matches?('a/b/c.markdown', '*.{md,mdc,markdown}')).to be true
    end

    it 'keeps * from crossing a slash for anchored globs' do
      expect(checker.path_matches?('app/models/a.rb', 'app/*.rb')).to be false
    end

    it 'does not match an unrelated file' do
      expect(checker.path_matches?('app/models/user.rb', '*.md')).to be false
    end
  end

  describe '#all_skipped?' do
    it 'is false when there are no rules' do
      expect(checker.all_skipped?(['README.md'], [])).to be false
    end

    it 'is true only when every file matches some rule' do
      expect(checker.all_skipped?(['README.md', 'docs/a.txt'], ['*.md', 'docs'])).to be true
    end

    it 'is false when one file is unmatched' do
      expect(checker.all_skipped?(['README.md', 'app/a.rb'], ['*.md', 'docs'])).to be false
    end
  end

  describe '#skip_paths_from_env' do
    it 'splits a comma separated list' do
      expect(checker.skip_paths_from_env('docs, *.md')).to eq(['docs', '*.md'])
    end

    it 'splits on whitespace when there is no comma' do
      expect(checker.skip_paths_from_env("docs\n*.md")).to eq(['docs', '*.md'])
    end

    it 'parses a JSON array' do
      expect(checker.skip_paths_from_env('["docs", "*.md"]')).to eq(['docs', '*.md'])
    end

    it 'returns an empty list for a blank value' do
      expect(checker.skip_paths_from_env(nil)).to eq([])
    end
  end

  describe '#skip_paths_from_file' do
    it 'ignores blank lines and comments' do
      allow(File).to receive(:file?).with('.skip').and_return(true)
      allow(File).to receive(:read).with('.skip').and_return("# a comment\n\ndocs/\n*.md\n")

      expect(checker.skip_paths_from_file('.skip')).to eq(['docs/', '*.md'])
    end

    it 'returns an empty list when the file is missing' do
      expect(checker.skip_paths_from_file('does/not/exist')).to eq([])
    end
  end
end
