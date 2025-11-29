require 'spec_helper'
require 'tmpdir'

RSpec.describe SourcecodeVerifier::Verifier do
  let(:gem_name) { 'test_gem' }
  let(:version) { '1.0.0' }
  let(:options) { { cache_dir: Dir.mktmpdir } }
  let(:verifier) { described_class.new(gem_name, version, options) }

  after do
    FileUtils.rm_rf(options[:cache_dir]) if options[:cache_dir] && Dir.exist?(options[:cache_dir])
  end

  describe '#initialize' do
    it 'sets up cache directories' do
      verifier # trigger initialization
      expect(Dir.exist?(File.join(options[:cache_dir], 'gems'))).to be true
      expect(Dir.exist?(File.join(options[:cache_dir], 'sources'))).to be true
    end

    it 'accepts custom cache directory' do
      custom_cache = Dir.mktmpdir
      custom_verifier = described_class.new(gem_name, version, cache_dir: custom_cache)
      
      expect(Dir.exist?(File.join(custom_cache, 'gems'))).to be true
      expect(Dir.exist?(File.join(custom_cache, 'sources'))).to be true
      
      FileUtils.rm_rf(custom_cache)
    end
  end

  describe '#verify' do
    it 'raises error without gem name and version' do
      expect {
        described_class.new(nil, nil).verify
      }.to raise_error(SourcecodeVerifier::Error, /Gem name and version are required/)
    end
  end

  describe '#verify_local' do
    let(:gem_path) { Dir.mktmpdir }
    let(:source_path) { Dir.mktmpdir }
    let(:local_verifier) { described_class.new(nil, nil, gem_path: gem_path, source_path: source_path) }

    after do
      FileUtils.rm_rf(gem_path)
      FileUtils.rm_rf(source_path)
    end

    it 'raises error without required paths' do
      expect {
        described_class.new(nil, nil).verify_local
      }.to raise_error(SourcecodeVerifier::Error, /Both gem_path and source_path are required/)
    end

    it 'raises error if gem path does not exist' do
      FileUtils.rm_rf(gem_path)
      expect {
        local_verifier.verify_local
      }.to raise_error(SourcecodeVerifier::Error, /Gem path does not exist/)
    end

    it 'raises error if source path does not exist' do
      FileUtils.rm_rf(source_path)
      expect {
        local_verifier.verify_local
      }.to raise_error(SourcecodeVerifier::Error, /Source path does not exist/)
    end

    it 'compares directories when paths exist' do
      # Create test files
      File.write(File.join(gem_path, 'test.rb'), 'puts "hello"')
      File.write(File.join(source_path, 'test.rb'), 'puts "hello"')

      expect_any_instance_of(SourcecodeVerifier::DiffEngine).to receive(:compare).and_return({
        identical: true,
        diff_file: '/tmp/test.diff',
        gem_only_files: [],
        source_only_files: [],
        modified_files: [],
        summary: 'Identical'
      })

      result = local_verifier.verify_local
      expect(result).to be_a(SourcecodeVerifier::Report)
    end
  end

  describe '#find_local_gem_path (private)' do
    context 'when not in bundle context' do
      it 'returns nil when no Gemfile exists' do
        # Test in a directory without Gemfile
        Dir.mktmpdir do |test_dir|
          Dir.chdir(test_dir) do
            result = verifier.send(:find_local_gem_path)
            expect(result).to be_nil
          end
        end
      end
    end

    # Note: More detailed testing would require actual bundle setup
    # which is better covered by integration tests
  end

  describe '#gem_version_matches? (private)' do
    let(:gem_path) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(gem_path)
    end

    it 'returns true when version extracted from path matches' do
      versioned_path = File.join(File.dirname(gem_path), "test_gem-1.0.0")
      FileUtils.mkdir_p(versioned_path)
      
      result = verifier.send(:gem_version_matches?, versioned_path)
      expect(result).to be true
      
      FileUtils.rm_rf(versioned_path)
    end

    it 'returns true when VERSION file matches' do
      version_file = File.join(gem_path, 'VERSION')
      File.write(version_file, '1.0.0')
      
      result = verifier.send(:gem_version_matches?, gem_path)
      expect(result).to be true
    end

    it 'returns true when gemspec version matches' do
      gemspec_file = File.join(gem_path, 'test_gem.gemspec')
      File.write(gemspec_file, 'spec.version = "1.0.0"')
      
      result = verifier.send(:gem_version_matches?, gem_path)
      expect(result).to be true
    end

    it 'returns false when no version information found' do
      result = verifier.send(:gem_version_matches?, gem_path)
      expect(result).to be false
    end

    it 'returns false when directory does not exist' do
      result = verifier.send(:gem_version_matches?, '/nonexistent/path')
      expect(result).to be false
    end
  end

  describe '#in_bundle_context? (private)' do
    it 'returns true when Gemfile exists in current directory' do
      # We're in the sourcecode-verifier directory which has a Gemfile
      expect(verifier.send(:in_bundle_context?)).to be true
    end

    # Note: Testing bundle context without Gemfile is tricky due to environment variables
    # Integration tests cover this behavior more reliably
  end
end