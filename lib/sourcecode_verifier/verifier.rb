require 'tmpdir'
require 'fileutils'

module SourcecodeVerifier
  class Verifier
    attr_reader :gem_name, :version, :options, :gem_path, :source_path, :cache_dir

    def initialize(gem_name, version, options = {})
      @gem_name = gem_name
      @version = version
      @options = options
      @gem_path = options[:gem_path]
      @source_path = options[:source_path]
      @cache_dir = options[:cache_dir] || './cache'
      setup_cache_directories
    end

    def verify
      raise Error, "Gem name and version are required" unless gem_name && version

      gem_dir = get_or_download_gem
      source_dir = get_or_download_source
      
      compare_directories(gem_dir, source_dir)
    end

    def verify_local
      raise Error, "Both gem_path and source_path are required for local verification" unless gem_path && source_path
      raise Error, "Gem path does not exist: #{gem_path}" unless File.exist?(gem_path)
      raise Error, "Source path does not exist: #{source_path}" unless File.exist?(source_path)

      compare_directories(gem_path, source_path)
    end

    private

    def setup_cache_directories
      FileUtils.mkdir_p(File.join(cache_dir, 'gems'))
      FileUtils.mkdir_p(File.join(cache_dir, 'sources'))
    end

    def get_or_download_gem
      # First try to find locally installed gem
      local_gem_path = find_local_gem_path
      if local_gem_path
        SourcecodeVerifier.logger.info "Using locally installed gem at #{local_gem_path}"
        return local_gem_path
      end

      # Fall back to cache
      cached_gem_dir = File.join(cache_dir, 'gems', "#{gem_name}-#{version}")
      
      if Dir.exist?(cached_gem_dir) && !Dir.empty?(cached_gem_dir)
        SourcecodeVerifier.logger.debug "Using cached gem content for #{gem_name}-#{version} at #{cached_gem_dir}"
        cached_gem_dir
      else
        SourcecodeVerifier.logger.info "Downloading gem #{gem_name}-#{version}..."
        gem_downloader = GemDownloader.new(gem_name, version, cache_dir: cache_dir)
        gem_downloader.download_and_extract(cached_gem_dir)
      end
    end

    def get_or_download_source
      # Get the repo info to create a proper cache key
      adapter = source_adapter
      repo_name = adapter.github_repo.gsub('/', '_') if adapter.respond_to?(:github_repo)
      cached_source_dir = File.join(cache_dir, 'sources', "#{repo_name || gem_name}-#{version}")
      
      if Dir.exist?(cached_source_dir) && !Dir.empty?(cached_source_dir)
        SourcecodeVerifier.logger.debug "Using cached source content for #{gem_name}-#{version} at #{cached_source_dir}"
        cached_source_dir
      else
        SourcecodeVerifier.logger.info "Downloading source for #{gem_name}-#{version}..."
        adapter.download_and_extract(cached_source_dir, version)
      end
    end

    def source_adapter
      adapter_name = options[:adapter] || :github
      
      case adapter_name
      when :github
        Adapters::Github.new(gem_name, options)
      else
        raise Error, "Unknown adapter: #{adapter_name}"
      end
    end

    def find_local_gem_path
      return nil unless in_bundle_context?
      
      begin
        # Try bundle show first (more specific to current bundle)
        output = `bundle show #{gem_name} 2>/dev/null`
        if $?.success? && !output.strip.empty?
          gem_path = output.strip
          # Verify the version matches what we're looking for
          if gem_version_matches?(gem_path)
            SourcecodeVerifier.logger.debug "Found locally bundled gem: #{gem_name} #{version} at #{gem_path}"
            return gem_path
          end
        end
        
        # Fall back to gem which (system-wide gems)
        output = `gem which #{gem_name} 2>/dev/null`
        if $?.success? && !output.strip.empty?
          require_path = output.strip
          # Extract gem root from require path
          gem_path = File.dirname(File.dirname(require_path))
          if gem_version_matches?(gem_path)
            SourcecodeVerifier.logger.debug "Found system gem: #{gem_name} #{version} at #{gem_path}"
            return gem_path
          end
        end
      rescue => e
        SourcecodeVerifier.logger.warn "Failed to check for local gem: #{e.message}"
      end
      
      nil
    end

    def in_bundle_context?
      File.exist?('Gemfile') || ENV['BUNDLE_GEMFILE']
    end

    def gem_version_matches?(gem_path)
      return false unless Dir.exist?(gem_path)
      
      # Extract version from path (most reliable for bundled gems)
      # Path format: /path/to/gems/gem-name-version
      if match = File.basename(gem_path).match(/^#{Regexp.escape(gem_name)}-(.+)$/)
        path_version = match[1]
        return path_version == version
      end
      
      # Look for VERSION file or extract from gemspec
      version_file = File.join(gem_path, 'VERSION')
      if File.exist?(version_file)
        local_version = File.read(version_file).strip
        return local_version == version
      end
      
      # Check gemspec files for version
      gemspec_files = Dir.glob(File.join(gem_path, '*.gemspec'))
      gemspec_files.each do |gemspec_file|
        content = File.read(gemspec_file)
        if match = content.match(/\.version\s*=\s*['"]([^'"]+)['"]/) ||
                   content.match(/VERSION\s*=\s*['"]([^'"]+)['"]/)
          local_version = match[1]
          return local_version == version
        end
      end
      
      # If we can't determine version, assume it doesn't match to be safe
      false
    rescue => e
      SourcecodeVerifier.logger.warn "Failed to check gem version at #{gem_path}: #{e.message}"
      false
    end

    def compare_directories(gem_dir, source_dir)
      diff_engine = DiffEngine.new(gem_dir, source_dir, options)
      diff_result = diff_engine.compare

      Report.new(diff_result, gem_name, version)
    end
  end
end