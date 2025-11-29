require 'tmpdir'
require 'fileutils'

module SourcecodeVerifier
  class DiffEngine
    attr_reader :gem_dir, :source_dir, :diff_file

    def initialize(gem_dir, source_dir)
      @gem_dir = gem_dir
      @source_dir = source_dir
    end

    def compare
      prepare_directories_for_comparison
      generate_git_diff
      
      {
        identical: diff_file_empty?,
        diff_file: @diff_file,
        gem_only_files: files_only_in_gem,
        source_only_files: files_only_in_source,
        modified_files: get_modified_files,
        summary: generate_summary
      }
    end

    private

    def prepare_directories_for_comparison
      # Create temporary git repos for both directories to enable git diff
      prepare_git_repo(gem_dir, 'gem')
      prepare_git_repo(source_dir, 'source')
    end

    def prepare_git_repo(dir, name)
      return unless Dir.exist?(dir)
      
      Dir.chdir(dir) do
        # Initialize git repo if it doesn't exist
        unless Dir.exist?('.git')
          system('git init -q', exception: true)
          system('git config user.email "sourcecode-verifier@example.com"', exception: true)
          system('git config user.name "Sourcecode Verifier"', exception: true)
        end
        
        # Add all files and commit
        system('git add -A', exception: true)
        system("git commit -q -m 'Initial commit for #{name} comparison' --allow-empty", exception: true)
      end
    end

    def generate_git_diff
      Dir.mktmpdir('sourcecode_verifier_diff') do |temp_dir|
        @diff_file = File.join(temp_dir, 'comparison.diff')
        
        # Use git diff --no-index to compare two directories
        cmd = "git diff --no-index --no-prefix '#{gem_dir}' '#{source_dir}' > '#{@diff_file}' || true"
        system(cmd)
        
        # Copy diff file to a permanent location
        permanent_diff_file = File.join(Dir.pwd, "sourcecode_diff_#{Time.now.strftime('%Y%m%d_%H%M%S')}.diff")
        FileUtils.cp(@diff_file, permanent_diff_file)
        @diff_file = permanent_diff_file
      end
    end

    def diff_file_empty?
      File.exist?(@diff_file) && File.size(@diff_file) == 0
    end

    def files_only_in_gem
      gem_files = get_relative_file_paths(gem_dir)
      source_files = get_relative_file_paths(source_dir)
      gem_files - source_files
    end

    def files_only_in_source
      gem_files = get_relative_file_paths(gem_dir)
      source_files = get_relative_file_paths(source_dir)
      source_files - gem_files
    end

    def get_modified_files
      return [] unless File.exist?(@diff_file)
      
      modified_files = []
      File.readlines(@diff_file).each do |line|
        if line.start_with?('diff --git')
          # Extract file paths from diff header
          paths = line.scan(%r{[ab]/(.+?)(?:\s|$)}).flatten
          modified_files.concat(paths) if paths.any?
        end
      end
      
      modified_files.uniq.reject { |file| file.include?('/.git/') }
    end

    def get_relative_file_paths(dir)
      return [] unless Dir.exist?(dir)
      
      Dir.chdir(dir) do
        Dir.glob('**/*', File::FNM_DOTMATCH)
           .reject { |path| File.directory?(path) || path.include?('/.git/') || path.start_with?('.git/') }
      end
    end

    def generate_summary
      gem_only = files_only_in_gem.size
      source_only = files_only_in_source.size
      modified = get_modified_files.size
      
      if gem_only == 0 && source_only == 0 && modified == 0
        "✓ Gem and source code are identical"
      else
        summary = "⚠ Differences found:"
        summary += "\n  - #{gem_only} file(s) only in gem" if gem_only > 0
        summary += "\n  - #{source_only} file(s) only in source" if source_only > 0
        summary += "\n  - #{modified} file(s) modified" if modified > 0
        summary
      end
    end
  end
end