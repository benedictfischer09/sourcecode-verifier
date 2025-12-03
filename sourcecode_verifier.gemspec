require_relative "lib/sourcecode_verifier/version"

Gem::Specification.new do |spec|
  spec.name = "sourcecode_verifier"
  spec.version = SourcecodeVerifier::VERSION
  spec.authors = ["Ben Fischer"]
  spec.email = ["ben.fischer.810@gmail.com"]

  spec.summary = "Verify source code integrity by comparing published gems with their source repositories"
  spec.description = "A Ruby gem that downloads published gems from RubyGems.org and compares them with source code from repositories like GitHub to verify integrity and detect differences."
  spec.homepage = "https://github.com/yourusername/sourcecode-verifier"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = ["sourcecode-verifier"]
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "octokit", "~> 5.0"
  spec.add_dependency "rubyzip", "~> 2.3"
  spec.add_dependency "tmpdir"
  spec.add_dependency "base64"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vernier", "~> 1.0"
end
