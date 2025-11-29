require 'tmpdir'

module SourcecodeVerifier
  class Verifier
    attr_reader :gem_name, :version, :options, :gem_path, :source_path

    def initialize(gem_name, version, options = {})
      @gem_name = gem_name
      @version = version
      @options = options
      @gem_path = options[:gem_path]
      @source_path = options[:source_path]
    end

    def verify
      raise Error, "Gem name and version are required" unless gem_name && version

      Dir.mktmpdir("sourcecode_verifier") do |temp_dir|
        gem_dir = download_gem(temp_dir)
        source_dir = download_source(temp_dir)
        
        compare_directories(gem_dir, source_dir)
      end
    end

    def verify_local
      raise Error, "Both gem_path and source_path are required for local verification" unless gem_path && source_path
      raise Error, "Gem path does not exist: #{gem_path}" unless File.exist?(gem_path)
      raise Error, "Source path does not exist: #{source_path}" unless File.exist?(source_path)

      compare_directories(gem_path, source_path)
    end

    private

    def download_gem(temp_dir)
      gem_downloader = GemDownloader.new(gem_name, version)
      gem_downloader.download_and_extract(temp_dir)
    end

    def download_source(temp_dir)
      adapter = source_adapter
      adapter.download_and_extract(temp_dir, version)
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