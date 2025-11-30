module SourcecodeVerifier
  class FileFilter
    # Common files/directories that are typically NOT included in published gems
    DEFAULT_SOURCE_IGNORE_PATTERNS = [
      # Version control
      '.git/',
      '.gitignore',
      '.gitattributes',
      '.gitmodules',
      
      # CI/CD and GitHub
      '.github/',
      '.circleci/',
      
      # Development tools
      'Gemfile',
      'Gemfile.lock', 
      'Rakefile',
      'Guardfile',
      '.rspec',
      
      # Documentation and project files  
      'CHANGELOG.rst',
      
      # Gem specification (but be careful - some gems include their main gemspec)
      # Only exclude clearly development-specific gemspec files
      '*-java.gemspec',
      '*_pure.gemspec', 
      '*-dev.gemspec',
      'dev-*.gemspec',
      
      # Development directories
      'bin/',
      'script/',
      'scripts/',
      'exe/',  # Sometimes exe/ is included in gems, but often not
      'test/',
      'tests/',
      'spec/',
      'specs/',
      'features/',
      'benchmark/',
      'benchmarks/',
      'example/',
      'examples/',
      'sample/',
      'samples/',
      'demo/',
      'demos/',
      'doc/',
      'docs/',
      
      # Build artifacts
      'pkg/',
      'vendor/',
      'coverage/',
      'tmp/',
      'log/',
      'logs/',
      
      # IDE files
      '.vscode/',
      '.idea/',
      '*.swp',
      '*.swo',
      '.DS_Store',
      'Thumbs.db',
      
      # Language specific
      'node_modules/',
      '.bundle/',
      '.yardoc/',
      
      # Configuration files
      '.env',
      '.env.*', 
      'Dockerfile',
      '.dockerignore',
      'Vagrantfile',
      
      # Additional development files often not included in gems
      '.simplecov',
      '.yardopts',
      '.yard/**/*',
      
      # Bundler gemfiles for testing different dependency versions
      'gemfiles/',
      'gemfiles/**/*',
      
      # Common file extensions that are typically documentation/config (case insensitive)
      '*.md',
      '*.txt', 
      '*.yml',
      '*.yaml',
      
      # License files  
      '*license*',
      '*licence*'
    ].freeze
    
    attr_reader :source_ignore_patterns, :gem_ignore_patterns, :display_ignore_patterns

    def initialize(options = {})
      @source_ignore_patterns = build_patterns(DEFAULT_SOURCE_IGNORE_PATTERNS, options[:ignore_source])
      @gem_ignore_patterns = build_patterns(['.git/'], options[:ignore_gem])
      @display_ignore_patterns = build_patterns(DEFAULT_SOURCE_IGNORE_PATTERNS, options[:ignore_display])
    end

    def should_ignore_source_file?(file_path)
      matches_any_pattern?(file_path, source_ignore_patterns)
    end

    def should_ignore_gem_file?(file_path)
      matches_any_pattern?(file_path, gem_ignore_patterns)
    end

    def filter_source_files(file_list)
      file_list.reject { |file| should_ignore_source_file?(file) }
    end

    def filter_gem_files(file_list)
      file_list.reject { |file| should_ignore_gem_file?(file) }
    end

    def filter_files_for_display(file_list)
      file_list.reject { |file| should_ignore_for_display?(file) }
    end

    def should_ignore_for_display?(file_path)
      # Apply same filtering as source files, plus some gem-specific patterns
      # This creates consistent filtering for display purposes
      matches_any_pattern?(file_path, display_ignore_patterns)
    end

    private

    def build_patterns(default_patterns, custom_patterns)
      patterns = default_patterns.dup
      patterns.concat(Array(custom_patterns)) if custom_patterns
      
      # Convert glob patterns to regex patterns
      patterns.map do |pattern|
        if pattern.end_with?('/')
          # Directory pattern - match anything starting with this path (case insensitive)
          /^#{Regexp.escape(pattern.chomp('/'))}(\/|$)/i
        elsif pattern.include?('*')
          # Glob pattern - convert to regex (all patterns are case insensitive)
          regex_pattern = pattern.gsub(/\*+/, '.*')
          /^#{regex_pattern}$/i
        else
          # Exact match pattern (case insensitive)
          /^#{Regexp.escape(pattern)}$/i
        end
      end
    end

    def matches_any_pattern?(file_path, patterns)
      # Normalize path separators
      normalized_path = file_path.gsub('\\', '/')
      
      patterns.any? do |pattern|
        case pattern
        when Regexp
          normalized_path.match?(pattern)
        else
          normalized_path == pattern
        end
      end
    end
  end
end