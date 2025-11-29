require 'fileutils'

module SourcecodeVerifier
  class BundledAnalyzer
    attr_reader :options, :results

    def initialize(options = {})
      @options = options
      @results = []
    end

    def analyze_all
      gems = get_bundled_gems
      puts "Found #{Colorizer.highlight(gems.size)} gems to analyze..."
      SourcecodeVerifier.logger.info "Starting bundled analysis of #{gems.size} gems"

      gems.each_with_index do |(gem_name, version), index|
        progress_indicator = Colorizer.highlight("(#{index + 1}/#{gems.size})")
        puts "#{Colorizer.info('Analyzing')} #{gem_name} #{version} #{progress_indicator}..."
        SourcecodeVerifier.logger.debug "Processing gem #{index + 1}/#{gems.size}: #{gem_name} #{version}"
        
        result = analyze_gem(gem_name, version)
        @results << result
        
        # Print colorized progress
        status_symbol = Colorizer.status_symbol(result[:status])
        status_text = colorize_status_text(result[:status])
        
        puts "#{status_symbol} #{gem_name} #{version} - #{status_text}"
      end

      generate_reports if options[:html]
      
      # Summary
      puts "\n#{Colorizer.bold('=== Summary ===')}"
      puts "Total gems: #{Colorizer.highlight(@results.size)}"
      
      matching_count = @results.count { |r| r[:status] == 'matching' }
      differences_count = @results.count { |r| r[:status] == 'differences' }
      source_not_found_count = @results.count { |r| r[:status] == 'source_not_found' }
      errored_count = @results.count { |r| r[:status] == 'errored' }
      
      puts "#{Colorizer.success('✓')} Matching: #{Colorizer.success(matching_count)}" if matching_count > 0
      puts "#{Colorizer.error('⚠')} Differences detected: #{Colorizer.error(differences_count)}" if differences_count > 0
      puts "#{Colorizer.warning('?')} Source not found: #{Colorizer.warning(source_not_found_count)}" if source_not_found_count > 0
      puts "#{Colorizer.error('✗')} Errored: #{Colorizer.error(errored_count)}" if errored_count > 0
      
      # Exit with error if any critical issues found
      exit_code = @results.any? { |r| r[:status] == 'differences' } ? 1 : 0
      exit(exit_code)
    end

    private

    def get_bundled_gems
      # Get list of gems from bundle
      begin
        output = `bundle list 2>/dev/null`
        unless $?.success?
          raise Error, "Failed to run 'bundle list'. Make sure you're in a directory with a Gemfile and bundle is installed."
        end
        
        gems = []
        output.lines.each do |line|
          # Parse lines like "  * rails (7.0.0)"
          if match = line.match(/^\s*\*\s+(\S+)\s+\(([^)]+)\)/)
            gem_name = match[1]
            version = match[2]
            
            # Skip bundler itself and other system gems
            next if %w[bundler].include?(gem_name)
            
            gems << [gem_name, version]
          end
        end
        
        gems.sort_by(&:first)  # Sort alphabetically by gem name
      rescue => e
        raise Error, "Error getting bundled gems: #{e.message}"
      end
    end

    def analyze_gem(gem_name, version)
      start_time = Time.now
      
      begin
        SourcecodeVerifier.logger.debug "Verifying gem #{gem_name} #{version}"
        report = SourcecodeVerifier.verify(gem_name, version, options)
        
        status = if report.identical?
          'matching'
        else
          'differences'
        end
        
        {
          gem_name: gem_name,
          version: version,
          status: status,
          identical: report.identical?,
          diff_file: report.diff_file_path,
          diff_content: get_diff_content(report.diff_file_path),
          gem_only_files: report.gem_only_files,
          source_only_files: report.source_only_files,
          modified_files: report.modified_files,
          summary: report.summary,
          duration: Time.now - start_time,
          error: nil
        }
      rescue => e
        error_message = e.message
        status = if error_message.include?("Could not discover GitHub repository") ||
                   error_message.include?("Could not find matching tag")
          'source_not_found'
        else
          'errored'
        end
        
        {
          gem_name: gem_name,
          version: version,
          status: status,
          identical: false,
          diff_file: nil,
          diff_content: nil,
          gem_only_files: [],
          source_only_files: [],
          modified_files: [],
          summary: nil,
          duration: Time.now - start_time,
          error: error_message
        }
      end
    end

    def get_diff_content(diff_file_path)
      return nil unless diff_file_path && File.exist?(diff_file_path)
      return nil if File.size(diff_file_path) == 0
      
      content = File.read(diff_file_path)
      # Limit diff content size for HTML embedding
      content.length > 50000 ? content[0...50000] + "\n... (truncated)" : content
    end

    def generate_reports
      puts "\n#{Colorizer.info('Generating HTML report...')}"
      SourcecodeVerifier.logger.info "Generating HTML report for #{@results.size} gems"
      
      html_generator = HtmlReportGenerator.new(@results, options)
      output_file = html_generator.generate
      
      if options[:zip]
        create_zip_file(output_file)
      else
        puts "HTML report generated: #{output_file}"
      end
    end

    def create_zip_file(html_file)
      begin
        require 'zip'
      rescue LoadError
        puts "Warning: rubyzip gem not available, cannot create ZIP file"
        puts "HTML report available at: #{html_file}"
        return
      end
      
      # Create reports/zips directory
      reports_dir = File.join(Dir.pwd, 'reports', 'zips')
      FileUtils.mkdir_p(reports_dir)
      
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      zip_filename = File.join(reports_dir, "sourcecode_verification_report_#{timestamp}.zip")
      
      Zip::File.open(zip_filename, create: true) do |zip|
        zip.add("index.html", html_file)
        
        # Add any diff files that exist
        @results.each do |result|
          if result[:diff_file] && File.exist?(result[:diff_file]) && File.size(result[:diff_file]) > 0
            diff_filename = "diffs/#{result[:gem_name]}-#{result[:version]}.diff"
            zip.add(diff_filename, result[:diff_file])
          end
        end
      end
      
      # Clean up the standalone HTML file
      File.delete(html_file) if File.exist?(html_file)
      
      puts "ZIP report generated: #{zip_filename}"
      puts "Extract and open index.html in a browser to view the report."
    end

    def colorize_status_text(status)
      case status
      when 'matching'
        Colorizer.success('matching')
      when 'differences'
        Colorizer.error('differences')
      when 'source_not_found'
        Colorizer.warning('source_not_found')
      when 'errored'
        Colorizer.error('errored')
      else
        Colorizer.gray(status)
      end
    end
  end
end