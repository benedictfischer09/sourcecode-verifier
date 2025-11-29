require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe SourcecodeVerifier::Report do
  let(:identical_diff_result) do
    {
      identical: true,
      diff_file: '/path/to/empty.diff',
      gem_only_files: [],
      source_only_files: [],
      modified_files: [],
      summary: '✓ Gem and source code are identical'
    }
  end

  let(:different_diff_result) do
    {
      identical: false,
      diff_file: '/path/to/diff.diff',
      gem_only_files: ['gem_only.rb', 'another_gem_file.txt'],
      source_only_files: ['source_only.rb'],
      modified_files: ['modified_file.rb', 'config.yml'],
      summary: '⚠ Differences found between gem and source code'
    }
  end

  let(:gem_name) { 'test_gem' }
  let(:version) { '1.0.0' }

  describe '#initialize' do
    it 'sets basic attributes' do
      report = described_class.new(identical_diff_result, gem_name, version)

      expect(report.diff_result).to eq(identical_diff_result)
      expect(report.gem_name).to eq(gem_name)
      expect(report.version).to eq(version)
      expect(report.timestamp).to be_a(Time)
    end

    it 'works without gem name and version' do
      report = described_class.new(identical_diff_result)

      expect(report.gem_name).to be_nil
      expect(report.version).to be_nil
      expect(report.timestamp).to be_a(Time)
    end
  end

  describe '#identical?' do
    it 'returns true for identical gems' do
      report = described_class.new(identical_diff_result)
      expect(report.identical?).to be true
    end

    it 'returns false for different gems' do
      report = described_class.new(different_diff_result)
      expect(report.identical?).to be false
    end
  end

  describe '#diff_file_path' do
    it 'returns the diff file path' do
      report = described_class.new(identical_diff_result)
      expect(report.diff_file_path).to eq('/path/to/empty.diff')
    end
  end

  describe '#diff_content' do
    let(:temp_diff_file) { File.join(Dir.mktmpdir, 'test.diff') }
    let(:diff_content) { "--- a/file.rb\n+++ b/file.rb\n@@ -1 +1 @@\n-old content\n+new content" }

    before do
      File.write(temp_diff_file, diff_content)
    end

    after do
      File.delete(temp_diff_file) if File.exist?(temp_diff_file)
    end

    it 'returns diff content when file exists' do
      diff_result = identical_diff_result.merge(diff_file: temp_diff_file)
      report = described_class.new(diff_result)

      expect(report.diff_content).to eq(diff_content)
    end

    it 'returns empty string when file does not exist' do
      report = described_class.new(identical_diff_result)
      expect(report.diff_content).to eq("")
    end
  end

  describe '#summary' do
    it 'returns the summary from diff result' do
      report = described_class.new(identical_diff_result)
      expect(report.summary).to eq('✓ Gem and source code are identical')
    end
  end

  describe 'file accessors' do
    let(:report) { described_class.new(different_diff_result) }

    it 'returns gem only files' do
      expect(report.gem_only_files).to eq(['gem_only.rb', 'another_gem_file.txt'])
    end

    it 'returns source only files' do
      expect(report.source_only_files).to eq(['source_only.rb'])
    end

    it 'returns modified files' do
      expect(report.modified_files).to eq(['modified_file.rb', 'config.yml'])
    end

    it 'returns empty arrays when diff result does not have file lists' do
      minimal_diff_result = { identical: true, summary: 'test' }
      minimal_report = described_class.new(minimal_diff_result)

      expect(minimal_report.gem_only_files).to eq([])
      expect(minimal_report.source_only_files).to eq([])
      expect(minimal_report.modified_files).to eq([])
    end
  end

  describe '#to_hash' do
    let(:report) { described_class.new(different_diff_result, gem_name, version) }

    it 'returns complete hash representation' do
      hash = report.to_hash

      expect(hash[:gem_name]).to eq(gem_name)
      expect(hash[:version]).to eq(version)
      expect(hash[:timestamp]).to be_a(String)
      expect(hash[:identical]).to be false
      expect(hash[:summary]).to eq('⚠ Differences found between gem and source code')
      expect(hash[:diff_file]).to eq('/path/to/diff.diff')
    end

    it 'includes correct statistics' do
      hash = report.to_hash
      stats = hash[:statistics]

      expect(stats[:gem_only_files]).to eq(2)
      expect(stats[:source_only_files]).to eq(1)
      expect(stats[:modified_files]).to eq(2)
      expect(stats[:total_differences]).to eq(5)
    end

    it 'includes file lists' do
      hash = report.to_hash
      files = hash[:files]

      expect(files[:gem_only]).to eq(['gem_only.rb', 'another_gem_file.txt'])
      expect(files[:source_only]).to eq(['source_only.rb'])
      expect(files[:modified]).to eq(['modified_file.rb', 'config.yml'])
    end
  end

  describe '#to_json' do
    let(:report) { described_class.new(identical_diff_result, gem_name, version) }

    it 'returns valid JSON string' do
      json_string = report.to_json
      expect { JSON.parse(json_string) }.not_to raise_error
    end

    it 'includes all expected fields in JSON' do
      parsed = JSON.parse(report.to_json)

      expect(parsed['gem_name']).to eq(gem_name)
      expect(parsed['version']).to eq(version)
      expect(parsed['identical']).to be true
      expect(parsed).to have_key('timestamp')
      expect(parsed).to have_key('statistics')
      expect(parsed).to have_key('files')
    end
  end

  describe '#to_s' do
    context 'with gem name and version' do
      let(:report) { described_class.new(identical_diff_result, gem_name, version) }

      it 'includes header information' do
        output = report.to_s

        expect(output).to include('=== Sourcecode Verification Report ===')
        expect(output).to include(gem_name)
        expect(output).to include(version)
        expect(output).to include('Timestamp:')
      end

      it 'includes summary' do
        output = report.to_s
        expect(output).to include('✓ Gem and source code are identical')
      end
    end

    context 'without gem name and version' do
      let(:report) { described_class.new(identical_diff_result) }

      it 'does not include header' do
        output = report.to_s
        expect(output).not_to include('=== Sourcecode Verification Report ===')
      end

      it 'still includes summary' do
        output = report.to_s
        expect(output).to include('✓ Gem and source code are identical')
      end
    end

    context 'with differences' do
      let(:report) { described_class.new(different_diff_result, gem_name, version) }

      it 'includes file difference details' do
        output = report.to_s

        expect(output).to include('Files only in gem')
        expect(output).to include('another_gem_file.txt')

        expect(output).to include('Files only in source')
        expect(output).to include('source_only.rb')

        expect(output).to include('Modified files')
        expect(output).to include('modified_file.rb')
        expect(output).to include('config.yml')
      end

      it 'includes diff file path when file exists' do
        temp_file = File.join(Dir.mktmpdir, 'test.diff')
        File.write(temp_file, 'test diff')

        diff_result_with_real_file = different_diff_result.merge(diff_file: temp_file)
        report_with_real_file = described_class.new(diff_result_with_real_file, gem_name, version)

        output = report_with_real_file.to_s
        expect(output).to include("Detailed diff saved to: #{temp_file}")

        File.delete(temp_file)
      end
    end
  end

  describe '#save_report' do
    let(:temp_dir) { Dir.mktmpdir }
    let(:report) { described_class.new(identical_diff_result, gem_name, version) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'saves report to default filename' do
      Dir.chdir(temp_dir) do
        filename = report.save_report

        expect(filename).to match(/sourcecode_verification_test_gem_1\.0\.0\.json/)
        expect(File.exist?(filename)).to be true

        content = JSON.parse(File.read(filename))
        expect(content['gem_name']).to eq(gem_name)
      end
    end

    it 'saves report to custom filename' do
      Dir.chdir(temp_dir) do
        custom_filename = 'my_custom_report.json'
        filename = report.save_report(custom_filename)

        expect(filename).to eq(custom_filename)
        expect(File.exist?(custom_filename)).to be true
      end
    end

    it 'generates filename with timestamp when gem info missing' do
      report_without_gem = described_class.new(identical_diff_result)

      Dir.chdir(temp_dir) do
        filename = report_without_gem.save_report

        expect(filename).to match(/sourcecode_verification_local_\d{8}_\d{6}\.json/)
        expect(File.exist?(filename)).to be true
      end
    end
  end
end
