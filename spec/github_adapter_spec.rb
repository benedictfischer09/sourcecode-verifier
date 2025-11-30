require 'spec_helper'
require 'webmock/rspec'
require 'tmpdir'

RSpec.describe SourcecodeVerifier::Adapters::Github do
  let(:gem_name) { 'test_gem' }
  let(:options) { {} }
  let(:github_adapter) { described_class.new(gem_name, options) }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe '#initialize' do
    context 'when github_repo option is provided' do
      let(:options) { { github_repo: 'owner/repo' } }

      it 'uses the provided repository' do
        expect(github_adapter.github_repo).to eq('owner/repo')
      end
    end

    context 'when github_repo option is not provided' do
      let(:rubygems_response) do
        {
          "name" => gem_name,
          "source_code_uri" => "https://github.com/owner/test_gem"
        }.to_json
      end

      before do
        stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
          .to_return(status: 200, body: rubygems_response)
      end

      it 'discovers repository from RubyGems API' do
        expect(github_adapter.github_repo).to eq('owner/test_gem')
      end
    end
  end

  describe '#discover_github_repo (private)' do
    let(:adapter) { described_class.new(gem_name, options) }

    context 'with successful RubyGems API response' do
      context 'when source_code_uri contains GitHub URL' do
        let(:rubygems_response) do
          {
            "name" => gem_name,
            "source_code_uri" => "https://github.com/owner/test_gem"
          }.to_json
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
            .to_return(status: 200, body: rubygems_response)
        end

        it 'extracts repository from source_code_uri' do
          repo = adapter.send(:discover_github_repo)
          expect(repo).to eq('owner/test_gem')
        end
      end

      context 'when homepage_uri contains GitHub URL' do
        let(:rubygems_response) do
          {
            "name" => gem_name,
            "homepage_uri" => "https://github.com/owner/test_gem"
          }.to_json
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
            .to_return(status: 200, body: rubygems_response)
        end

        it 'extracts repository from homepage_uri' do
          repo = adapter.send(:discover_github_repo)
          expect(repo).to eq('owner/test_gem')
        end
      end

      context 'when metadata contains GitHub URL' do
        let(:rubygems_response) do
          {
            "name" => gem_name,
            "homepage_uri" => "https://example.com",
            "metadata" => {
              "source_code_uri" => "https://github.com/owner/test_gem"
            }
          }.to_json
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
            .to_return(status: 200, body: rubygems_response)
        end

        it 'extracts repository from metadata' do
          repo = adapter.send(:discover_github_repo)
          expect(repo).to eq('owner/test_gem')
        end
      end

      context 'when bug_tracker_uri contains GitHub URL' do
        let(:rubygems_response) do
          {
            "name" => gem_name,
            "metadata" => {
              "bug_tracker_uri" => "https://github.com/owner/test_gem/issues"
            }
          }.to_json
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
            .to_return(status: 200, body: rubygems_response)
        end

        it 'extracts repository from bug_tracker_uri' do
          repo = adapter.send(:discover_github_repo)
          expect(repo).to eq('owner/test_gem')
        end
      end

      context 'when no GitHub URL is found' do
        let(:rubygems_response) do
          {
            "name" => gem_name,
            "homepage_uri" => "https://example.com"
          }.to_json
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
            .to_return(status: 200, body: rubygems_response)
          
          # Stub GitHub search API to return no results (with any query params)
          stub_request(:get, /api\.github\.com\/search\/repositories/)
            .to_return(status: 200, body: { "items" => [] }.to_json)
          
          # Stub Google search to return no results (with any query params)
          stub_request(:get, /google\.com\/search/)
            .to_return(status: 200, body: "<html><body>No results</body></html>")
        end

        it 'raises an error' do
          expect {
            adapter.send(:discover_github_repo)
          }.to raise_error(SourcecodeVerifier::Error, /Could not discover GitHub repository/)
        end
      end
    end

    context 'when RubyGems API request fails' do
      before do
        stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
          .to_return(status: 404, body: 'Not Found')
      end

      it 'raises an error' do
        expect {
          adapter.send(:discover_github_repo)
        }.to raise_error(SourcecodeVerifier::Error, /Failed to fetch gem information/)
      end
    end
  end

  describe '#extract_repo_from_url (private)' do
    let(:adapter) { described_class.new(gem_name, github_repo: 'dummy/repo') }

    context 'with standard GitHub URLs' do
      it 'extracts from HTTPS URL' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo')
        expect(repo).to eq('owner/repo')
      end

      it 'extracts from SSH URL' do
        repo = adapter.send(:extract_repo_from_url, 'git@github.com:owner/repo.git')
        expect(repo).to eq('owner/repo')
      end

      it 'extracts from git:// URL' do
        repo = adapter.send(:extract_repo_from_url, 'git://github.com/owner/repo.git')
        expect(repo).to eq('owner/repo')
      end
    end

    context 'with URLs containing paths' do
      it 'extracts from URL with tree path' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo/tree/main')
        expect(repo).to eq('owner/repo')
      end

      it 'extracts from URL with issues path' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo/issues')
        expect(repo).to eq('owner/repo')
      end

      it 'extracts from URL with releases path' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo/releases/tag/v1.0.0')
        expect(repo).to eq('owner/repo')
      end
    end

    context 'with special repository names' do
      it 'preserves .rb extension in repo name' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/octokit/octokit.rb')
        expect(repo).to eq('octokit/octokit.rb')
      end

      it 'preserves .js extension in repo name' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo.js')
        expect(repo).to eq('owner/repo.js')
      end

      it 'removes .git suffix' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo.git')
        expect(repo).to eq('owner/repo')
      end
    end

    context 'with URL fragments and query params' do
      it 'removes fragments' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo#readme')
        expect(repo).to eq('owner/repo')
      end

      it 'removes query parameters' do
        repo = adapter.send(:extract_repo_from_url, 'https://github.com/owner/repo?tab=readme')
        expect(repo).to eq('owner/repo')
      end
    end

    context 'with invalid URLs' do
      it 'raises error for non-GitHub URL' do
        expect {
          adapter.send(:extract_repo_from_url, 'https://gitlab.com/owner/repo')
        }.to raise_error(SourcecodeVerifier::Error, /Could not extract repository information/)
      end

      it 'raises error for malformed GitHub URL' do
        expect {
          adapter.send(:extract_repo_from_url, 'https://github.com/')
        }.to raise_error(SourcecodeVerifier::Error, /Could not extract repository information/)
      end
    end
  end

  describe '#find_matching_tag (private)' do
    let(:options) { { github_repo: 'owner/repo' } }
    let(:adapter) { described_class.new(gem_name, options) }
    let(:version) { '1.0.0' }
    
    let(:mock_client) { instance_double(Octokit::Client) }
    let(:tags) do
      [
        double(name: '1.0.0'),
        double(name: 'v1.0.1'),
        double(name: 'test_gem-1.0.2'),
        double(name: 'test_gem-1.0.0'),
        double(name: 'release-2.0.0')
      ]
    end

    before do
      allow(Octokit::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:tags).with('owner/repo').and_return(tags)
    end

    context 'with exact version match' do
      it 'returns exact match' do
        result = adapter.send(:find_matching_tag, '1.0.0')
        expect(result).to eq('1.0.0')
      end
    end

    context 'with v-prefixed version' do
      it 'returns v-prefixed match' do
        result = adapter.send(:find_matching_tag, '1.0.1')
        expect(result).to eq('v1.0.1')
      end
    end

    context 'with gem-prefixed version' do
      it 'returns gem-prefixed match' do
        result = adapter.send(:find_matching_tag, '1.0.2')
        expect(result).to eq('test_gem-1.0.2')
      end

      it 'prefers exact match over gem-prefixed' do
        result = adapter.send(:find_matching_tag, '1.0.0')
        expect(result).to eq('1.0.0') # not 'test_gem-1.0.0'
      end
    end

    context 'when no matching tag is found' do
      let(:tags) { [double(name: '2.0.0'), double(name: 'v3.0.0')] }

      it 'raises an error with available tags' do
        expect {
          adapter.send(:find_matching_tag, '1.0.0')
        }.to raise_error(SourcecodeVerifier::Error) do |error|
          expect(error.message).to include("Could not find matching tag for version '1.0.0'")
          expect(error.message).to include("Available tags: 2.0.0, v3.0.0")
        end
      end
    end

    context 'when GitHub API call fails' do
      before do
        allow(mock_client).to receive(:tags).and_raise(Octokit::NotFound.new)
      end

      it 'raises an error' do
        expect {
          adapter.send(:find_matching_tag, '1.0.0')
        }.to raise_error(SourcecodeVerifier::Error, /Failed to fetch tags from GitHub repository/)
      end
    end
  end

  describe '#find_github_url_in_gem_info (private)' do
    let(:adapter) { described_class.new(gem_name, github_repo: 'dummy/repo') }

    context 'with top-level GitHub URLs' do
      let(:gem_info) do
        {
          'source_code_uri' => 'https://github.com/owner/repo',
          'homepage_uri' => 'https://example.com'
        }
      end

      it 'finds GitHub URL in top-level fields' do
        url = adapter.send(:find_github_url_in_gem_info, gem_info)
        expect(url).to eq('https://github.com/owner/repo')
      end
    end

    context 'with metadata GitHub URLs' do
      let(:gem_info) do
        {
          'homepage_uri' => 'https://example.com',
          'metadata' => {
            'source_code_uri' => 'https://github.com/owner/repo'
          }
        }
      end

      it 'finds GitHub URL in metadata' do
        url = adapter.send(:find_github_url_in_gem_info, gem_info)
        expect(url).to eq('https://github.com/owner/repo')
      end
    end

    context 'with multiple GitHub URLs' do
      let(:gem_info) do
        {
          'source_code_uri' => 'https://github.com/owner/repo1',
          'metadata' => {
            'source_code_uri' => 'https://github.com/owner/repo2'
          }
        }
      end

      it 'returns first GitHub URL found' do
        url = adapter.send(:find_github_url_in_gem_info, gem_info)
        expect(url).to eq('https://github.com/owner/repo1')
      end
    end

    context 'with no GitHub URLs' do
      let(:gem_info) do
        {
          'homepage_uri' => 'https://example.com',
          'metadata' => {
            'documentation_uri' => 'https://docs.example.com'
          }
        }
      end

      it 'returns nil' do
        url = adapter.send(:find_github_url_in_gem_info, gem_info)
        expect(url).to be_nil
      end
    end

    context 'with non-string URLs' do
      let(:gem_info) do
        {
          'source_code_uri' => nil,
          'homepage_uri' => 123,
          'metadata' => {
            'source_code_uri' => 'https://github.com/owner/repo'
          }
        }
      end

      it 'ignores non-string values' do
        url = adapter.send(:find_github_url_in_gem_info, gem_info)
        expect(url).to eq('https://github.com/owner/repo')
      end
    end
  end

  describe '#download_and_extract' do
    let(:options) { { github_repo: 'owner/repo' } }
    let(:adapter) { described_class.new(gem_name, options) }
    let(:target_dir) { Dir.mktmpdir }
    let(:version) { '1.0.0' }
    let(:tag) { 'v1.0.0' }
    
    let(:mock_client) { instance_double(Octokit::Client) }
    let(:tags) { [double(name: tag)] }
    
    let(:zip_content) { "fake zip content" }

    after do
      FileUtils.rm_rf(target_dir)
    end

    before do
      allow(Octokit::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:tags).and_return(tags)
      
      # Mock the GitHub archive download
      stub_request(:get, "https://github.com/owner/repo/archive/refs/tags/#{tag}.zip")
        .to_return(status: 200, body: zip_content)
      
      # Mock zip extraction
      allow(adapter).to receive(:extract_archive)
    end

    it 'creates target directory' do
      expect(FileUtils).to receive(:mkdir_p).with(target_dir)
      
      adapter.download_and_extract(target_dir, version)
    end

    it 'downloads archive from GitHub' do
      adapter.download_and_extract(target_dir, version)
      
      expect(WebMock).to have_requested(:get, "https://github.com/owner/repo/archive/refs/tags/#{tag}.zip")
    end

    context 'when download fails' do
      before do
        stub_request(:get, "https://github.com/owner/repo/archive/refs/tags/#{tag}.zip")
          .to_return(status: 404, body: 'Not Found')
      end

      it 'raises an error' do
        expect {
          adapter.download_and_extract(target_dir, version)
        }.to raise_error(SourcecodeVerifier::Error, /Failed to download source archive/)
      end
    end
  end

  describe 'integration scenarios' do
    let(:adapter) { described_class.new('faraday', {}) }

    context 'with real faraday gem data structure' do
      let(:faraday_response) do
        {
          "name" => "faraday",
          "homepage_uri" => "https://lostisland.github.io/faraday",
          "metadata" => {
            "homepage_uri" => "https://lostisland.github.io/faraday",
            "changelog_uri" => "https://github.com/lostisland/faraday/releases/tag/v2.14.0",
            "bug_tracker_uri" => "https://github.com/lostisland/faraday/issues",
            "source_code_uri" => "https://github.com/lostisland/faraday"
          }
        }.to_json
      end

      before do
        stub_request(:get, "https://rubygems.org/api/v1/gems/faraday.json")
          .to_return(status: 200, body: faraday_response)
      end

      it 'successfully discovers repository' do
        expect(adapter.github_repo).to eq('lostisland/faraday')
      end
    end

    context 'with addressable gem tag pattern' do
      let(:options) { { github_repo: 'sporkmonger/addressable' } }
      let(:adapter) { described_class.new('addressable', options) }
      let(:mock_client) { instance_double(Octokit::Client) }
      let(:tags) { [double(name: 'addressable-2.8.8'), double(name: 'addressable-2.8.7')] }

      before do
        allow(Octokit::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:tags).and_return(tags)
      end

      it 'finds gem-prefixed tag' do
        result = adapter.send(:find_matching_tag, '2.8.8')
        expect(result).to eq('addressable-2.8.8')
      end
    end
  end
end