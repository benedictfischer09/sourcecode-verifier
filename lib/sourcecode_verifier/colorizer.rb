module SourcecodeVerifier
  module Colorizer
    # ANSI color codes
    COLORS = {
      black: 30,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      white: 37,
      gray: 90,
      bright_red: 91,
      bright_green: 92,
      bright_yellow: 93,
      bright_blue: 94,
      bright_magenta: 95,
      bright_cyan: 96,
      bright_white: 97
    }.freeze

    STYLES = {
      reset: 0,
      bold: 1,
      dim: 2,
      italic: 3,
      underline: 4
    }.freeze

    class << self
      # Enable/disable color output
      attr_accessor :enabled
      
      def enabled?
        return @enabled if defined?(@enabled) && !@enabled.nil?
        @enabled = $stdout.isatty && ENV['NO_COLOR'].nil?
      end

      # Colorize text with specified color and optional style
      def colorize(text, color: nil, style: nil)
        return text.to_s unless enabled?
        
        codes = []
        codes << COLORS[color] if color && COLORS[color]
        codes << STYLES[style] if style && STYLES[style]
        
        return text.to_s if codes.empty?
        
        "\e[#{codes.join(';')}m#{text}\e[#{STYLES[:reset]}m"
      end

      # Convenience methods for common colors
      def red(text, **opts)
        colorize(text, color: :red, **opts)
      end

      def green(text, **opts)
        colorize(text, color: :green, **opts)
      end

      def yellow(text, **opts)
        colorize(text, color: :yellow, **opts)
      end

      def blue(text, **opts)
        colorize(text, color: :blue, **opts)
      end

      def gray(text, **opts)
        colorize(text, color: :gray, **opts)
      end

      def white(text, **opts)
        colorize(text, color: :white, **opts)
      end

      def bold(text, **opts)
        colorize(text, style: :bold, **opts)
      end

      # Status-specific colors
      def success(text)
        green(text, style: :bold)
      end

      def error(text)
        red(text, style: :bold)
      end

      def warning(text)
        yellow(text)
      end

      def info(text)
        gray(text)
      end

      def highlight(text)
        white(text, style: :bold)
      end

      # Status symbols with colors
      def status_symbol(status)
        case status.to_s
        when 'matching'
          success('✓')
        when 'differences'
          error('⚠')
        when 'source_not_found'
          warning('?')
        when 'errored'
          error('✗')
        else
          gray('·')
        end
      end
    end
  end
end