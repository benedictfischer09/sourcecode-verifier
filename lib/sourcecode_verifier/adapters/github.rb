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
        @subdirectory = nil # Will be set if this is a monorepo subdirectory
      end

      def download_and_extract(target_dir, version)
        FileUtils.mkdir_p(target_dir)
        tag = find_matching_tag(version)
        download_source_archive(target_dir, tag)
      end

      private

      def discover_github_repo
        # First try to get repo info from RubyGems API
        rubygems_api_url = "https://rubygems.org/api/v1/gems/#{gem_name}.json"
        SourcecodeVerifier.logger.debug "Fetching gem info from: #{rubygems_api_url}"
        response = HTTParty.get(rubygems_api_url)
        
        if response.success?
          gem_info = JSON.parse(response.body)
          SourcecodeVerifier.logger.debug "Got gem info for #{gem_name}"
          
          github_url = find_github_url_in_gem_info(gem_info)
          
          if github_url
            SourcecodeVerifier.logger.debug "Found GitHub URL: #{github_url}"
            return extract_repo_from_url(github_url)
          else
            SourcecodeVerifier.logger.debug "No GitHub URL found in gem metadata, trying fallback search methods..."
            
            # Try GitHub search first
            begin
              github_repo = search_github_repositories(gem_name)
              if github_repo
                SourcecodeVerifier.logger.debug "Found repository via GitHub search: #{github_repo}"
                return github_repo
              end
            rescue => e
              SourcecodeVerifier.logger.debug "GitHub search failed: #{e.message}"
            end
            
            # Try Google search as final fallback
            begin
              github_repo = search_via_google(gem_name)
              if github_repo
                SourcecodeVerifier.logger.debug "Found repository via Google search: #{github_repo}"
                return github_repo
              end
            rescue => e
              SourcecodeVerifier.logger.debug "Google search failed: #{e.message}"
            end
            
            raise Error, "Could not discover GitHub repository for gem '#{gem_name}'. Please provide github_repo option."
          end
        else
          raise Error, "Failed to fetch gem information from RubyGems API for '#{gem_name}'"
        end
      end

      def find_github_url_in_gem_info(gem_info)
        # Check top-level fields first
        urls_to_check = [
          gem_info['source_code_uri'],
          gem_info['homepage_uri'], 
          gem_info['project_uri']
        ]
        
        # Check metadata fields (often more accurate)
        if gem_info['metadata'].is_a?(Hash)
          metadata = gem_info['metadata']
          urls_to_check += [
            metadata['source_code_uri'],
            metadata['homepage_uri'],
            metadata['project_uri'],
            metadata['bug_tracker_uri'],
            metadata['changelog_uri'],
            metadata['documentation_uri']
          ]
        end
        
        # Find first GitHub URL (prioritize GitHub, but could be extended for GitLab, etc.)
        github_url = urls_to_check.compact.find do |url|
          url.is_a?(String) && url.include?('github.com')
        end
        
        # If no GitHub URL found, log what URLs we did find for debugging
        unless github_url
          other_urls = urls_to_check.compact.select { |url| url.is_a?(String) }
          if other_urls.any?
            SourcecodeVerifier.logger.debug "No GitHub URL found, available URLs: #{other_urls.join(', ')}"
          else
            SourcecodeVerifier.logger.debug "No source URLs found in gem metadata"
          end
        end
        
        github_url
      end

      def extract_repo_from_url(url)
        # Extract owner/repo from various GitHub URL formats
        # Handle: https://github.com/owner/repo, git://github.com/owner/repo.git, 
        #         https://github.com/owner/repo/tree/branch, etc.
        match = url.match(%r{github\.com[/:]([^/]+)/([^/\s]+)})
        if match
          owner = match[1]
          repo = match[2]
          
          # Check for subdirectory paths (e.g., /tree/branch/subdirectory)
          if url.match(%r{/tree/[^/]+/(.+)$})
            subdirectory_match = url.match(%r{/tree/[^/]+/(.+)$})
            @subdirectory = subdirectory_match[1] if subdirectory_match
            SourcecodeVerifier.logger.debug "Detected monorepo subdirectory: #{@subdirectory}"
          end
          
          # Clean up paths and fragments, but preserve valid repo names
          repo = repo.split(/[#?]/).first           # Remove fragments/query params
          repo = repo.sub(%r{/(tree|blob|releases|issues).*$}, '') # Remove GitHub path suffixes
          repo = repo.sub(/\.git$/, '')            # Remove .git suffix only
          
          "#{owner}/#{repo}"
        else
          raise Error, "Could not extract repository information from GitHub URL: #{url}"
        end
      end

      def find_matching_tag(version)
        client = Octokit::Client.new(access_token: options[:github_token])
        
        begin
          tags = client.tags(github_repo)
          tag_names = tags.map(&:name)
          
          SourcecodeVerifier.logger.debug "Looking for version #{version} in #{tag_names.size} tags"
          
          # Try different tag patterns in order of preference
          tag_patterns = [
            version,                           # exact: 1.0.0
            "v#{version}",                     # v-prefix: v1.0.0  
            "#{gem_name}-#{version}",          # gem-prefix: gem-1.0.0
            "#{gem_name}_#{version}",          # gem_underscore: gem_1.0.0
            "#{gem_name}/#{version}",          # gem/version: gem/1.0.0
            "release-#{version}",              # release-prefix: release-1.0.0
            "#{version}-release"               # version-suffix: 1.0.0-release
          ]
          
          # Try exact matches first
          tag_patterns.each do |pattern|
            exact_match = tags.find { |tag| tag.name == pattern }
            if exact_match
              SourcecodeVerifier.logger.debug "Found exact tag match: #{exact_match.name}"
              return exact_match.name
            end
          end
          
          # Try regex matches for more flexible matching
          version_regex = Regexp.escape(version)
          flexible_patterns = [
            /^v?#{version_regex}$/,                    # v1.0.0 or 1.0.0
            /^#{gem_name}[-_]?v?#{version_regex}$/,    # gem-v1.0.0, gem_1.0.0, gem-1.0.0
            /^v?#{version_regex}[-_].*$/,              # 1.0.0-anything
            /.*[-_]v?#{version_regex}$/,               # anything-1.0.0
            /^v?#{version_regex}[^\d]/,                # 1.0.0 followed by non-digit
          ]
          
          flexible_patterns.each do |pattern|
            matches = tags.select { |tag| tag.name.match?(pattern) }
            if matches.any?
              match = matches.first
              SourcecodeVerifier.logger.debug "Found regex tag match: #{match.name} (pattern: #{pattern})"
              return match.name
            end
          end
          
          raise Error, "Could not find matching tag for version '#{version}' in repository '#{github_repo}'. Available tags: #{tag_names.first(20).join(', ')}#{tag_names.size > 20 ? '...' : ''}"
          
        rescue Octokit::Error => e
          raise Error, "Failed to fetch tags from GitHub repository '#{github_repo}': #{e.message}"
        end
      end

      def download_source_archive(target_dir, tag)
        Dir.mktmpdir("github_download") do |temp_dir|
          archive_url = "https://github.com/#{github_repo}/archive/refs/tags/#{tag}.zip"
          archive_path = File.join(temp_dir, "#{tag}.zip")
          
          response = HTTParty.get(archive_url, follow_redirects: true)
          
          if response.success?
            File.open(archive_path, 'wb') do |file|
              file.write(response.body)
            end
            
            extract_archive(archive_path, target_dir)
          else
            raise Error, "Failed to download source archive from GitHub: #{response.code} #{response.message}"
          end
        end
      end

      def extract_archive(archive_path, target_dir)
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
              
              # If this is a monorepo subdirectory, only extract files from that subdirectory
              if @subdirectory
                subdirectory_prefix = "#{@subdirectory}/"
                if relative_path.start_with?(subdirectory_prefix)
                  # Remove the subdirectory prefix to get the final relative path
                  relative_path = relative_path.sub(/^#{Regexp.escape(subdirectory_prefix)}/, '')
                elsif relative_path == @subdirectory
                  # Handle the subdirectory itself (if it's a file)
                  relative_path = ''
                else
                  # Skip files not in the target subdirectory
                  next
                end
                next if relative_path.empty?
              end
              
              target_path = File.join(target_dir, relative_path)
              
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
              target_path = File.join(target_dir, entry.name)
              
              if entry.directory?
                FileUtils.mkdir_p(target_path)
              else
                FileUtils.mkdir_p(File.dirname(target_path))
                entry.extract(target_path)
              end
            end
          end
        end
        
        target_dir
      end

      def search_github_repositories(gem_name)
        # Search GitHub repositories using the search API
        # This doesn't require authentication for basic searches
        search_url = "https://api.github.com/search/repositories"
        
        # Try multiple search strategies
        search_queries = [
          "#{gem_name} language:ruby",                    # Most specific
          "ruby #{gem_name}",                            # More general
          gem_name,                                      # Broadest
          "#{gem_name.gsub(/[-_]/, ' ')} language:ruby"  # Handle dashed/underscored names
        ]
        
        search_queries.each do |query|
          SourcecodeVerifier.logger.debug "Searching GitHub with query: #{query}"
          
          response = HTTParty.get(search_url, 
            query: { q: query, sort: 'relevance', per_page: 10 },
            headers: { 'User-Agent' => 'sourcecode-verifier' }
          )
          
          if response.success?
            results = JSON.parse(response.body)
            
            if results['items'] && results['items'].any?
              # Look for exact name matches first
              exact_match = results['items'].find { |repo| 
                repo_name = repo['name'].downcase
                gem_name_normalized = gem_name.downcase
                
                # Check various name patterns
                repo_name == gem_name_normalized ||
                repo_name == gem_name_normalized.gsub(/[-_]/, '') ||
                repo_name.gsub(/[-_]/, '') == gem_name_normalized.gsub(/[-_]/, '') ||
                repo_name.include?(gem_name_normalized) ||
                gem_name_normalized.include?(repo_name)
              }
              
              if exact_match
                return exact_match['full_name']
              end
              
              # If no exact match, try the first relevant result
              # but only if it has good indicators (Ruby language, gem-like name)
              first_result = results['items'].first
              if first_result['language'] == 'Ruby' || 
                 first_result['description']&.downcase&.include?('gem') ||
                 first_result['description']&.downcase&.include?('ruby')
                
                SourcecodeVerifier.logger.debug "Using best guess from search: #{first_result['full_name']}"
                return first_result['full_name']
              end
            end
          else
            SourcecodeVerifier.logger.debug "GitHub search API returned error: #{response.code}"
            # Don't raise error, try next query or next search method
          end
        end
        
        nil # No repository found
      end

      def search_via_google(gem_name)
        # Use Google search to find GitHub repositories
        # This is a last resort fallback method
        search_query = "#{gem_name} ruby gem site:github.com"
        google_url = "https://www.google.com/search"
        
        SourcecodeVerifier.logger.debug "Searching Google for: #{search_query}"
        
        response = HTTParty.get(google_url,
          query: { q: search_query, num: 10 },
          headers: { 
            'User-Agent' => 'Mozilla/5.0 (compatible; sourcecode-verifier)'
          }
        )
        
        if response.success?
          html_body = response.body
          
          # Extract GitHub URLs from search results using regex
          # Look for github.com URLs in the HTML
          github_urls = html_body.scan(%r{https?://github\.com/([^/\s"]+/[^/\s"]+)}).map(&:first)
          
          github_urls.each do |repo_path|
            # Clean up the repo path
            repo_path = repo_path.gsub(/[#?].*$/, '') # Remove fragments/queries
            repo_path = repo_path.sub(/\.git$/, '')   # Remove .git suffix
            
            # Skip obviously non-repository paths
            next if repo_path.include?('/releases') || 
                   repo_path.include?('/issues') || 
                   repo_path.include?('/wiki') ||
                   repo_path.include?('/tree') ||
                   repo_path.include?('/blob')
            
            # Simple relevance check - prefer repos with gem name in them
            repo_name = repo_path.split('/').last.downcase
            gem_name_normalized = gem_name.downcase
            
            if repo_name.include?(gem_name_normalized) || 
               gem_name_normalized.include?(repo_name) ||
               repo_name.gsub(/[-_]/, '') == gem_name_normalized.gsub(/[-_]/, '')
              
              SourcecodeVerifier.logger.debug "Found potential match via Google: #{repo_path}"
              return repo_path
            end
          end
          
          # If no exact match found, return the first GitHub repo found (if any)
          if github_urls.any?
            first_repo = github_urls.first
            SourcecodeVerifier.logger.debug "Using first Google result as fallback: #{first_repo}"
            return first_repo
          end
        else
          SourcecodeVerifier.logger.debug "Google search failed: #{response.code}"
        end
        
        nil # No repository found
      end
    end
  end
end