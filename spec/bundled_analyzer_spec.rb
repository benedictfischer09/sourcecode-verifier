RSpec.describe SourcecodeVerifier::BundledAnalyzer do
  let(:options) do
    {
      cache_dir: './cache',
      verbose: false,
      bundled: true,
      html: true
    }
  end

  describe "#analyze_all", :integration do
    context "when analyzing a subset of bundled gems" do
      let(:test_analyzer) do
        Class.new(SourcecodeVerifier::BundledAnalyzer) do
          private
          
          def get_bundled_gems
            # Use a small subset of known good gems for testing
            [
              ['base64', '0.3.0'],
              ['json', '2.16.0'],
              ['rake', '13.3.1']
            ]
          end
        end
      end

      it "successfully analyzes multiple gems and generates reports", :integration do
        analyzer = test_analyzer.new(options)
        
        # Capture output to verify progress reporting
        result = capture_output do
          analyzer.analyze_all
        end

        expect(result).to exit_with_code(0)

        # Verify progress output
        expect(result[:output]).to include("Found 3 gems to analyze...")
        expect(result[:output]).to include("base64 0.3.0")
        expect(result[:output]).to include("json 2.16.0") 
        expect(result[:output]).to include("rake 13.3.1")
        expect(result[:output]).to include("=== Summary ===")
        expect(result[:output]).to include("Total gems: 3")

        # Verify results structure
        results = analyzer.results
        expect(results).to be_an(Array)
        expect(results.size).to eq(3)

        # Check that each result has the expected structure
        results.each do |result|
          expect(result).to include(:gem_name, :version, :status, :identical, :duration)
          expect(result[:gem_name]).to be_a(String)
          expect(result[:version]).to be_a(String)
          expect(result[:status]).to be_in(['matching', 'differences', 'source_not_found', 'errored'])
          expect(result[:duration]).to be_a(Float)
          expect(result[:duration]).to be > 0
        end
      end

      it "generates HTML reports when html option is enabled", :integration do
        analyzer = test_analyzer.new(options)
        
        expect_any_instance_of(SourcecodeVerifier::HtmlReportGenerator)
          .to receive(:generate)
          .and_return("test_report.html")

        result = capture_output do
          analyzer.analyze_all
        end
        
        expect(result).to exit_with_code(0)
      end
    end

    context "when analyzing with ZIP output" do
      let(:zip_options) { options.merge(zip: true) }
      
      let(:test_analyzer) do
        Class.new(SourcecodeVerifier::BundledAnalyzer) do
          private
          
          def get_bundled_gems
            [['base64', '0.3.0']] # Single gem for faster test
          end
        end
      end

      it "creates ZIP file when zip option is enabled", :integration do
        analyzer = test_analyzer.new(zip_options)
        
        # Mock the ZIP creation to avoid actual file system operations
        allow(analyzer).to receive(:create_zip_file).and_call_original
        
        result = capture_output do
          analyzer.analyze_all
        end
        
        expect(result).to exit_with_code(0)
        expect(analyzer).to have_received(:create_zip_file)
      end
    end

    context "when bundle list fails" do
      let(:failing_analyzer) do
        Class.new(SourcecodeVerifier::BundledAnalyzer) do
          private
          
          def get_bundled_gems
            raise SourcecodeVerifier::Error, "Failed to run 'bundle list'"
          end
        end
      end

      it "handles bundle list failures gracefully" do
        analyzer = failing_analyzer.new(options)
        
        result = capture_output do
          analyzer.analyze_all
        end
        
        expect(result).to exit_with_code(2)
        expect(result[:output]).to include("Error: Failed to run 'bundle list'")
      end
    end
  end

  describe "#get_bundled_gems" do
    let(:analyzer) { SourcecodeVerifier::BundledAnalyzer.new(options) }

    it "parses bundle list output correctly", :integration do
      # This test uses the real bundle list from the current project
      # Skip if no Gemfile present
      skip "No Gemfile found" unless File.exist?('Gemfile')
      
      gems = analyzer.send(:get_bundled_gems)
      
      expect(gems).to be_an(Array)
      expect(gems.size).to be > 0
      
      # Each gem should be an array with [name, version]
      gems.each do |gem_info|
        expect(gem_info).to be_an(Array)
        expect(gem_info.size).to eq(2)
        expect(gem_info[0]).to be_a(String)  # name
        expect(gem_info[1]).to be_a(String)  # version
      end
      
      # Should be sorted alphabetically by name
      gem_names = gems.map(&:first)
      expect(gem_names).to eq(gem_names.sort)
      
      # Should include some expected gems from our Gemfile
      gem_names = gems.map(&:first)
      expect(gem_names).to include('rspec')  # We know rspec is in our dependencies
    end
  end

  describe "#analyze_gem" do
    let(:analyzer) { SourcecodeVerifier::BundledAnalyzer.new(options) }

    it "returns proper structure for successful analysis" do
      # Mock a successful verification
      mock_report = double('Report',
        identical?: true,
        diff_file_path: nil,
        gem_only_files: [],
        source_only_files: [],
        modified_files: [],
        summary: "✓ Gem and source code are identical"
      )
      
      allow(SourcecodeVerifier).to receive(:verify).and_return(mock_report)
      
      result = analyzer.send(:analyze_gem, 'test_gem', '1.0.0')
      
      expect(result).to include(
        gem_name: 'test_gem',
        version: '1.0.0',
        status: 'matching',
        identical: true,
        error: nil
      )
      expect(result[:duration]).to be > 0
    end

    it "handles source not found errors" do
      allow(SourcecodeVerifier).to receive(:verify)
        .and_raise(SourcecodeVerifier::Error, "Could not discover GitHub repository")
      
      result = analyzer.send(:analyze_gem, 'unknown_gem', '1.0.0')
      
      expect(result).to include(
        gem_name: 'unknown_gem',
        version: '1.0.0',
        status: 'source_not_found',
        identical: false,
        error: "Could not discover GitHub repository"
      )
    end

    it "handles general errors" do
      allow(SourcecodeVerifier).to receive(:verify)
        .and_raise(StandardError, "Network error")
      
      result = analyzer.send(:analyze_gem, 'error_gem', '1.0.0')
      
      expect(result).to include(
        gem_name: 'error_gem',
        version: '1.0.0',
        status: 'errored',
        identical: false,
        error: "Network error"
      )
    end
  end

  # Helper method to capture output and exit codes
  def capture_output(&block)
    original_stdout = $stdout
    exit_code = nil
    
    $stdout = StringIO.new
    
    # Mock exit to capture exit code
    allow(Kernel).to receive(:exit) do |code|
      exit_code = code || 0
      throw :exit_called
    end
    
    begin
      catch(:exit_called) do
        yield
        exit_code = 0 # If no exit was called, assume success
      end
    ensure
      output = $stdout.string
      $stdout = original_stdout
      allow(Kernel).to receive(:exit).and_call_original
    end
    
    # Return both output and exit code
    { output: output, exit_code: exit_code }
  end

  # Custom matcher for exit codes
  RSpec::Matchers.define :exit_with_code do |expected_code|
    match do |actual|
      actual[:exit_code] == expected_code
    end
    
    failure_message do |actual|
      "expected exit code #{expected_code}, got #{actual[:exit_code]}"
    end
  end
end