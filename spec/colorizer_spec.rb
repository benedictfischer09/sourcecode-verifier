require 'spec_helper'

RSpec.describe SourcecodeVerifier::Colorizer do
  before do
    # Enable colors for testing
    described_class.enabled = true
  end

  after do
    # Reset to default
    described_class.enabled = nil
  end

  describe '.enabled?' do
    it 'defaults to true when stdout is a tty and NO_COLOR is not set' do
      allow($stdout).to receive(:isatty).and_return(true)
      allow(ENV).to receive(:[]).with('NO_COLOR').and_return(nil)
      described_class.enabled = nil # Reset
      
      expect(described_class.enabled?).to be true
    end

    it 'returns false when NO_COLOR environment variable is set' do
      allow($stdout).to receive(:isatty).and_return(true)
      allow(ENV).to receive(:[]).with('NO_COLOR').and_return('1')
      described_class.enabled = nil # Reset
      
      expect(described_class.enabled?).to be false
    end
  end

  describe '.colorize' do
    context 'when colors are enabled' do
      it 'colorizes text with specified color' do
        result = described_class.colorize('test', color: :red)
        expect(result).to include("\e[31m")
        expect(result).to include("test")
        expect(result).to include("\e[0m")
      end

      it 'applies styles' do
        result = described_class.colorize('test', style: :bold)
        expect(result).to include("\e[1m")
        expect(result).to include("test")
        expect(result).to include("\e[0m")
      end

      it 'combines color and style' do
        result = described_class.colorize('test', color: :green, style: :bold)
        expect(result).to include("\e[32;1m")
        expect(result).to include("test")
        expect(result).to include("\e[0m")
      end
    end

    context 'when colors are disabled' do
      before { described_class.enabled = false }

      it 'returns plain text' do
        result = described_class.colorize('test', color: :red, style: :bold)
        expect(result).to eq('test')
      end
    end
  end

  describe '.status_symbol' do
    it 'returns colored symbols for different statuses' do
      expect(described_class.status_symbol('matching')).to include('✓')
      expect(described_class.status_symbol('differences')).to include('⚠')
      expect(described_class.status_symbol('source_not_found')).to include('?')
      expect(described_class.status_symbol('errored')).to include('✗')
    end
  end

  describe 'convenience methods' do
    it 'provides color shortcuts' do
      expect(described_class.red('test')).to include("\e[31m")
      expect(described_class.green('test')).to include("\e[32m")
      expect(described_class.yellow('test')).to include("\e[33m")
      expect(described_class.blue('test')).to include("\e[34m")
    end

    it 'provides semantic methods' do
      expect(described_class.success('test')).to include("\e[32")
      expect(described_class.error('test')).to include("\e[31")
      expect(described_class.warning('test')).to include("\e[33")
    end
  end
end