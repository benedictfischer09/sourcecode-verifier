module SourcecodeVerifier
  module PathUtils
    def self.determine_reports_directory
      # Prefer /tmp if it exists and is writable, fallback to ./tmp
      if Dir.exist?('/tmp') && File.writable?('/tmp')
        File.join('/tmp', 'sourcecode-verifier-reports')
      else
        './tmp/reports'
      end
    end

    def self.determine_cache_directory
      # Prefer /tmp if it exists and is writable, fallback to ./tmp/cache
      if Dir.exist?('/tmp') && File.writable?('/tmp')
        File.join('/tmp', 'sourcecode-verifier')
      else
        './tmp/cache'
      end
    end
  end
end