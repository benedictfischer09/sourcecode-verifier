require 'tmpdir'
require 'fileutils'

module SourcecodeVerifier
  class DiffEngine
    attr_reader :gem_dir, :source_dir, :diff_file, :file_filter, :options

    def initialize(gem_dir, source_dir, options = {})
      @gem_dir = gem_dir
      @source_dir = source_dir
      @options = options
      @file_filter = FileFilter.new(options)
    end

    def compare
      # Create clean temporary directories with only the files we want to compare
      Dir.mktmpdir("sourcecode_verifier_clean_compare") do |temp_dir|
        clean_gem_dir = File.join(temp_dir, 'gem')
        clean_source_dir = File.join(temp_dir, 'source')
        
        copy_filtered_files(gem_dir, clean_gem_dir, :gem)
        copy_filtered_files(source_dir, clean_source_dir, :source)
        
        prepare_directories_for_comparison(clean_gem_dir, clean_source_dir)
        generate_git_diff(clean_gem_dir, clean_source_dir)
        
        {
          identical: diff_file_empty?,
          diff_file: @diff_file,
          gem_only_files: files_only_in_gem,
          source_only_files: files_only_in_source,
          modified_files: get_modified_files,
          summary: generate_summary
        }
      end
    end

    private

    def copy_filtered_files(source_dir, target_dir, type)
      FileUtils.mkdir_p(target_dir)
      
      filtered_files = get_filtered_file_paths(source_dir, type)
      
      filtered_files.each do |relative_path|
        # Skip any .git files that might have slipped through
        next if relative_path.include?('.git')
        
        source_file = File.join(source_dir, relative_path)
        target_file = File.join(target_dir, relative_path)
        
        if File.exist?(source_file)
          FileUtils.mkdir_p(File.dirname(target_file))
          FileUtils.cp(source_file, target_file)
        end
      end
      
      # Optional: print what files we copied for debugging
      if options && options[:verbose] && options[:debug]
        files = Dir.glob(File.join(target_dir, '**/*')).select { |f| File.file?(f) }.map { |f| f.sub(target_dir + '/', '') }
        puts "Copied #{type} files: #{files}"
      end
    end

    def prepare_directories_for_comparison(clean_gem_dir, clean_source_dir)
      # Create temporary git repos for both directories to enable git diff
      prepare_git_repo(clean_gem_dir, 'gem')
      prepare_git_repo(clean_source_dir, 'source')
    end

    def prepare_git_repo(dir, name)
      return unless Dir.exist?(dir)
      
      Dir.chdir(dir) do
        # Initialize git repo if it doesn't exist
        system('git init -q', exception: true)
        system('git config user.email "sourcecode-verifier@example.com"', exception: true)
        system('git config user.name "Sourcecode Verifier"', exception: true)
        
        # Add all files and commit
        system('git add -A', exception: true)
        system("git commit -q -m 'Initial commit for #{name} comparison' --allow-empty", exception: true)
      end
    end

    def generate_git_diff(clean_gem_dir, clean_source_dir)
      Dir.mktmpdir('sourcecode_verifier_diff') do |temp_dir|
        @diff_file = File.join(temp_dir, 'comparison.diff')
        
        # Create a custom comparison that only looks at non-.git files
        gem_files = Dir.glob(File.join(clean_gem_dir, '**/*')).reject { |f| f.include?('.git') || File.directory?(f) }
        source_files = Dir.glob(File.join(clean_source_dir, '**/*')).reject { |f| f.include?('.git') || File.directory?(f) }
        
        # Use git diff --no-index on specific files instead of directories
        File.open(@diff_file, 'w') do |diff_output|
          all_relative_files = (gem_files.map { |f| f.sub(clean_gem_dir + '/', '') } + 
                               source_files.map { |f| f.sub(clean_source_dir + '/', '') }).uniq.sort
          
          all_relative_files.each do |relative_file|
            gem_file = File.join(clean_gem_dir, relative_file)
            source_file = File.join(clean_source_dir, relative_file)
            
            # Skip if both files don't exist (shouldn't happen with our logic)
            next unless File.exist?(gem_file) || File.exist?(source_file)
            
            # Use git diff --no-index to compare individual files
            temp_diff = `git diff --no-index --no-prefix '#{gem_file}' '#{source_file}' 2>/dev/null || true`
            diff_output.write(temp_diff) unless temp_diff.empty?
          end
        end
        
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
      gem_files = get_filtered_file_paths(gem_dir, :gem)
      source_files = get_filtered_file_paths(source_dir, :source)
      gem_files - source_files
    end

    def files_only_in_source
      gem_files = get_filtered_file_paths(gem_dir, :gem)
      source_files = get_filtered_file_paths(source_dir, :source)
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
      
      # Filter out ignored files and git files
      modified_files.uniq.reject do |file|
        file.include?('/.git/') || 
        file_filter.should_ignore_source_file?(file) ||
        file_filter.should_ignore_gem_file?(file)
      end
    end

    def get_relative_file_paths(dir)
      return [] unless Dir.exist?(dir)
      
      Dir.chdir(dir) do
        Dir.glob('**/*', File::FNM_DOTMATCH)
           .reject { |path| File.directory?(path) || path.include?('/.git/') || path.start_with?('.git/') }
           .sort
      end
    end

    def get_filtered_file_paths(dir, type)
      all_files = get_relative_file_paths(dir)
      
      case type
      when :gem
        file_filter.filter_gem_files(all_files)
      when :source
        file_filter.filter_source_files(all_files)
      else
        all_files
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