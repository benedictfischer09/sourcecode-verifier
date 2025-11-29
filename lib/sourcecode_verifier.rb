require_relative "sourcecode_verifier/version"
require_relative "sourcecode_verifier/file_filter"
require_relative "sourcecode_verifier/verifier"
require_relative "sourcecode_verifier/gem_downloader"
require_relative "sourcecode_verifier/adapters/github"
require_relative "sourcecode_verifier/diff_engine"
require_relative "sourcecode_verifier/report"

module SourcecodeVerifier
  class Error < StandardError; end

  def self.verify(gem_name, version, options = {})
    verifier = Verifier.new(gem_name, version, options)
    verifier.verify
  end

  def self.verify_local(gem_path, source_path, options = {})
    verifier = Verifier.new(nil, nil, options.merge(gem_path: gem_path, source_path: source_path))
    verifier.verify_local
  end
end