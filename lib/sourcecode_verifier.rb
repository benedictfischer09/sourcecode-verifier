require 'logger'
require_relative "sourcecode_verifier/version"
require_relative "sourcecode_verifier/file_filter"
require_relative "sourcecode_verifier/verifier"
require_relative "sourcecode_verifier/gem_downloader"
require_relative "sourcecode_verifier/adapters/github"
require_relative "sourcecode_verifier/diff_engine"
require_relative "sourcecode_verifier/report"
require_relative "sourcecode_verifier/bundled_analyzer"
require_relative "sourcecode_verifier/html_report_generator"

module SourcecodeVerifier
  class Error < StandardError; end

  # Global logger configuration
  def self.logger
    @logger ||= begin
      logger = Logger.new(STDERR)
      logger.level = Logger::INFO
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      logger
    end
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.set_log_level(level)
    case level.to_s.downcase
    when 'debug' then logger.level = Logger::DEBUG
    when 'info' then logger.level = Logger::INFO
    when 'warn' then logger.level = Logger::WARN
    when 'error' then logger.level = Logger::ERROR
    else
      logger.warn "Unknown log level '#{level}', using INFO"
      logger.level = Logger::INFO
    end
  end

  def self.verify(gem_name, version, options = {})
    verifier = Verifier.new(gem_name, version, options)
    verifier.verify
  end

  def self.verify_local(gem_path, source_path, options = {})
    verifier = Verifier.new(nil, nil, options.merge(gem_path: gem_path, source_path: source_path))
    verifier.verify_local
  end
end