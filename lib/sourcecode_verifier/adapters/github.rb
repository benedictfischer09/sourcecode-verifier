require 'base64'
require 'octokit'
require 'httparty'
require 'zip'
require 'fileutils'
require 'json'

module SourcecodeVerifier
  module Adapters
    class Github
      include HTTParty

      attr_reader :gem_name, :options, :github_repo

      def initialize(gem_name, options = {})
        @gem_name = gem_name
        @options = options
        @github_repo = options[:github_repo] || discover_github_repo
      end

      def download_and_extract(temp_dir, version)
        tag = find_matching_tag(version)
        download_source_archive(temp_dir, tag)
      end

      private

      def discover_github_repo
        # First try to get repo info from RubyGems API
        rubygems_api_url = "https://rubygems.org/api/v1/gems/#{gem_name}.json"
        response = HTTParty.get(rubygems_api_url)
        
        if response.success?
          gem_info = JSON.parse(response.body)
          
          # Try various fields that might contain GitHub URL
          github_url = gem_info['homepage_uri'] || 
                      gem_info['source_code_uri'] ||
                      gem_info['project_uri']
          
          if github_url && github_url.include?('github.com')
            extract_repo_from_url(github_url)
          else
            raise Error, "Could not discover GitHub repository for gem '#{gem_name}'. Please provide github_repo option."
          end
        else
          raise Error, "Failed to fetch gem information from RubyGems API for '#{gem_name}'"
        end
      end

      def extract_repo_from_url(url)
        # Extract owner/repo from various GitHub URL formats
        match = url.match(%r{github\.com[/:]([\w\-\.]+)/([\w\-\.]+)})
        if match
          "#{match[1]}/#{match[2].sub(/\.git$/, '')}"
        else
          raise Error, "Could not extract repository information from GitHub URL: #{url}"
        end
      end

      def find_matching_tag(version)
        client = Octokit::Client.new(access_token: options[:github_token])
        
        begin
          tags = client.tags(github_repo)
          
          # Try to find exact match first
          exact_match = tags.find { |tag| tag.name == version || tag.name == "v#{version}" }
          return exact_match.name if exact_match
          
          # Try to find close matches
          version_matches = tags.select do |tag|
            tag.name.match?(/^v?#{Regexp.escape(version)}($|[^\d])/)
          end
          
          if version_matches.any?
            version_matches.first.name
          else
            raise Error, "Could not find matching tag for version '#{version}' in repository '#{github_repo}'. Available tags: #{tags.map(&:name).join(', ')}"
          end
        rescue Octokit::Error => e
          raise Error, "Failed to fetch tags from GitHub repository '#{github_repo}': #{e.message}"
        end
      end

      def download_source_archive(temp_dir, tag)
        archive_url = "https://github.com/#{github_repo}/archive/refs/tags/#{tag}.zip"
        archive_path = File.join(temp_dir, "#{tag}.zip")
        
        response = HTTParty.get(archive_url, follow_redirects: true)
        
        if response.success?
          File.open(archive_path, 'wb') do |file|
            file.write(response.body)
          end
          
          extract_archive(archive_path, temp_dir)
        else
          raise Error, "Failed to download source archive from GitHub: #{response.code} #{response.message}"
        end
      end

      def extract_archive(archive_path, temp_dir)
        source_dir = File.join(temp_dir, 'source_files')
        
        Zip::File.open(archive_path) do |zip_file|
          # GitHub archives have a top-level directory, we want to extract its contents
          top_level_dirs = zip_file.entries.map(&:name).map { |name| name.split('/').first }.uniq
          
          if top_level_dirs.size == 1
            top_level_dir = top_level_dirs.first
            
            zip_file.each do |entry|
              # Skip the top-level directory itself
              next if entry.name == "#{top_level_dir}/"
              
              # Remove the top-level directory from the path
              relative_path = entry.name.sub(/^#{Regexp.escape(top_level_dir)}\//, '')
              next if relative_path.empty?
              
              target_path = File.join(source_dir, relative_path)
              
              if entry.directory?
                FileUtils.mkdir_p(target_path)
              else
                FileUtils.mkdir_p(File.dirname(target_path))
                entry.extract(target_path)
              end
            end
          else
            # Fallback: extract everything as-is
            zip_file.each do |entry|
              target_path = File.join(source_dir, entry.name)
              
              if entry.directory?
                FileUtils.mkdir_p(target_path)
              else
                FileUtils.mkdir_p(File.dirname(target_path))
                entry.extract(target_path)
              end
            end
          end
        end
        
        source_dir
      end
    end
  end
end