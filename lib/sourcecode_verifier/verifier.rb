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
      cached_gem_dir = File.join(cache_dir, 'gems', "#{gem_name}-#{version}")
      
      if Dir.exist?(cached_gem_dir) && !Dir.empty?(cached_gem_dir)
        puts "⚠ Using cached gem content for #{gem_name}-#{version}" if options[:verbose]
        cached_gem_dir
      else
        puts "Downloading gem #{gem_name}-#{version}..." if options[:verbose]
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
        puts "⚠ Using cached source content for #{gem_name}-#{version}" if options[:verbose]
        cached_source_dir
      else
        puts "Downloading source for #{gem_name}-#{version}..." if options[:verbose]
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

    def compare_directories(gem_dir, source_dir)
      diff_engine = DiffEngine.new(gem_dir, source_dir)
      diff_result = diff_engine.compare

      Report.new(diff_result, gem_name, version)
    end
  end
end