module SourcecodeVerifier
  class Report
    attr_reader :diff_result, :gem_name, :version, :timestamp

    def initialize(diff_result, gem_name = nil, version = nil)
      @diff_result = diff_result
      @gem_name = gem_name
      @version = version
      @timestamp = Time.now
    end

    def identical?
      diff_result[:identical]
    end

    def diff_file_path
      diff_result[:diff_file]
    end

    def diff_content
      return "" unless File.exist?(diff_file_path)
      File.read(diff_file_path)
    end

    def summary
      diff_result[:summary]
    end

    def gem_only_files
      diff_result[:gem_only_files] || []
    end

    def source_only_files
      diff_result[:source_only_files] || []
    end

    def modified_files
      diff_result[:modified_files] || []
    end

    def to_hash
      {
        gem_name: gem_name,
        version: version,
        timestamp: timestamp.iso8601,
        identical: identical?,
        summary: summary,
        diff_file: diff_file_path,
        statistics: {
          gem_only_files: gem_only_files.size,
          source_only_files: source_only_files.size,
          modified_files: modified_files.size,
          total_differences: gem_only_files.size + source_only_files.size + modified_files.size
        },
        files: {
          gem_only: gem_only_files,
          source_only: source_only_files,
          modified: modified_files
        }
      }
    end

    def to_json
      require 'json'
      JSON.pretty_generate(to_hash)
    end

    def to_s
      output = []
      
      if gem_name && version
        output << "=== Sourcecode Verification Report ==="
        output << "Gem: #{gem_name} (#{version})"
        output << "Timestamp: #{timestamp}"
        output << ""
      end
      
      output << summary
      output << ""
      
      unless identical?
        if gem_only_files.any?
          output << "Files only in gem (#{gem_only_files.size}):"
          gem_only_files.each { |file| output << "  + #{file}" }
          output << ""
        end
        
        if source_only_files.any?
          output << "Files only in source (#{source_only_files.size}):"
          source_only_files.each { |file| output << "  - #{file}" }
          output << ""
        end
        
        if modified_files.any?
          output << "Modified files (#{modified_files.size}):"
          modified_files.each { |file| output << "  ~ #{file}" }
          output << ""
        end
        
        if diff_file_path && File.exist?(diff_file_path)
          output << "Detailed diff saved to: #{diff_file_path}"
        end
      end
      
      output.join("\n")
    end

    def print_summary
      puts to_s
    end

    def save_report(filename = nil)
      filename ||= "sourcecode_verification_#{gem_name || 'local'}_#{version || timestamp.strftime('%Y%m%d_%H%M%S')}.json"
      
      File.write(filename, to_json)
      filename
    end
  end
end