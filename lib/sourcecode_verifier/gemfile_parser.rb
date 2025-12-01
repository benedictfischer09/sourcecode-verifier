require 'bundler'
require 'set'

module SourcecodeVerifier
  class GemfileParser
    attr_reader :gem_groups, :dependencies

    def initialize(gemfile_path = nil)
      @gemfile_path = gemfile_path || find_gemfile
      @gem_groups = {}
      @dependencies = {}
      parse_gemfile
    end

    # Returns an array of groups for a given gem name
    def groups_for_gem(gem_name)
      @gem_groups[gem_name] || [:default]
    end

    # Returns all gems in a specific group (including subdependencies)
    def gems_in_group(group)
      result = Set.new
      
      # Add direct gems in this group
      @gem_groups.each do |gem_name, groups|
        if groups.include?(group)
          result.add(gem_name)
          # Add all subdependencies of this gem
          add_subdependencies(gem_name, result)
        end
      end
      
      result.to_a
    end

    # Returns all available groups
    def all_groups
      groups = Set.new([:default])
      @gem_groups.values.each { |gem_groups| groups.merge(gem_groups) }
      groups.to_a.sort
    end

    # Returns gem information with group data
    def gem_info_with_groups
      @gem_groups.map do |gem_name, groups|
        {
          name: gem_name,
          groups: groups,
          subdependencies: get_subdependencies(gem_name)
        }
      end
    end

    private

    def find_gemfile
      current_dir = Dir.pwd
      loop do
        gemfile_path = File.join(current_dir, 'Gemfile')
        return gemfile_path if File.exist?(gemfile_path)
        
        parent = File.dirname(current_dir)
        break if parent == current_dir # reached root
        current_dir = parent
      end
      
      raise Error, "Could not find Gemfile in current directory or any parent directories"
    end

    def parse_gemfile
      unless File.exist?(@gemfile_path)
        raise Error, "Gemfile not found at #{@gemfile_path}"
      end

      SourcecodeVerifier.logger.debug "Parsing Gemfile at #{@gemfile_path}"

      begin
        # Use Bundler to parse the Gemfile properly
        definition = Bundler::Definition.build(@gemfile_path, File.join(File.dirname(@gemfile_path), 'Gemfile.lock'), {})
        
        # Parse direct dependencies from Gemfile
        definition.dependencies.each do |dependency|
          groups = dependency.groups.empty? ? [:default] : dependency.groups
          @gem_groups[dependency.name] = groups
          SourcecodeVerifier.logger.debug "Found gem #{dependency.name} in groups: #{groups}"
        end

        # Get all specs to understand subdependencies
        specs = definition.specs
        specs.each do |spec|
          @dependencies[spec.name] = spec.dependencies.map(&:name)
        end

      rescue => e
        SourcecodeVerifier.logger.warn "Failed to parse Gemfile with Bundler: #{e.message}"
        # Fall back to simple regex parsing
        parse_gemfile_simple
      end
    end

    def parse_gemfile_simple
      SourcecodeVerifier.logger.debug "Using simple regex parsing for Gemfile"
      
      content = File.read(@gemfile_path)
      current_groups = [:default]
      
      content.lines.each do |line|
        line = line.strip
        
        # Skip comments and empty lines
        next if line.empty? || line.start_with?('#')
        
        # Handle group blocks
        if line.match(/^group\s+(.+?)\s+do/)
          groups_match = line.match(/^group\s+(.+?)\s+do/)
          if groups_match
            # Parse group names (can be symbols or strings)
            group_str = groups_match[1]
            current_groups = extract_groups_from_string(group_str)
            SourcecodeVerifier.logger.debug "Entering group block: #{current_groups}"
          end
        elsif line == 'end'
          current_groups = [:default]
          SourcecodeVerifier.logger.debug "Exiting group block, back to default"
        elsif line.match(/^gem\s+/)
          # Parse gem line
          if gem_match = line.match(/^gem\s+['"]([^'"]+)['"]/)
            gem_name = gem_match[1]
            
            # Check for inline group specification
            inline_groups = extract_inline_groups(line)
            groups = inline_groups.any? ? inline_groups : current_groups
            
            @gem_groups[gem_name] = groups
            SourcecodeVerifier.logger.debug "Found gem #{gem_name} in groups: #{groups}"
          end
        end
      end
    end

    def extract_groups_from_string(group_str)
      groups = []
      
      # Handle various formats: :test, :development, 'test', "development", [:test, :development]
      group_str.scan(/[:']?(\w+)[':]?/).each do |match|
        groups << match[0].to_sym
      end
      
      groups.any? ? groups : [:default]
    end

    def extract_inline_groups(line)
      groups = []
      
      # Look for group: or groups: specification
      if line.match(/groups?:\s*(.+?)(?:,|\s*$)/)
        group_match = line.match(/groups?:\s*(.+?)(?:,|\s*$)/)
        if group_match
          group_part = group_match[1]
          
          # Handle array format: [:test, :development]
          if group_part.include?('[')
            groups = extract_groups_from_string(group_part)
          else
            # Handle single group: :test
            groups = extract_groups_from_string(group_part)
          end
        end
      end
      
      groups
    end

    def add_subdependencies(gem_name, result_set)
      return unless @dependencies[gem_name]
      
      @dependencies[gem_name].each do |dep_name|
        next if result_set.include?(dep_name)
        result_set.add(dep_name)
        # Recursively add subdependencies
        add_subdependencies(dep_name, result_set)
      end
    end

    def get_subdependencies(gem_name)
      result = Set.new
      add_subdependencies(gem_name, result)
      result.to_a
    end
  end
end