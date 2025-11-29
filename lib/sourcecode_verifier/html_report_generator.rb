require 'erb'
require 'cgi'
require 'fileutils'

# Simple humanize method for status strings
class String
  def humanize
    self.gsub('_', ' ').split.map(&:capitalize).join(' ')
  end
end

module SourcecodeVerifier
  class HtmlReportGenerator
    attr_reader :results, :options

    def initialize(results, options = {})
      @results = results
      @options = options
    end

    def generate
      # Create reports/html directory
      reports_dir = File.join(Dir.pwd, 'reports', 'html')
      FileUtils.mkdir_p(reports_dir)

      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      filename = File.join(reports_dir, "sourcecode_verification_report_#{timestamp}.html")

      File.write(filename, generate_html)
      open_in_browser(filename) if $stdout.isatty
      filename
    end

    private

    def open_in_browser(path)
        begin
            case RbConfig::CONFIG['host_os']
            when /darwin/  then system('open', path)   # macOS
            when /linux/   then system('xdg-open', path)
            when /mingw|mswin/ then system('start', path) # Windows
            end
        rescue StandardError
            # Do nothing if it fails
        end
    end

    def generate_html
      erb_template = ERB.new(html_template, trim_mode: '-')
      erb_template.result(binding)
    end

    def html_template
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Sourcecode Verification Report</title>
            <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.0/css/bootstrap.min.css" rel="stylesheet">
            <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css" rel="stylesheet">
            <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
            <style>
                .status-matching { color: #28a745; }
                .status-differences { color: #dc3545; }
                .status-source_not_found { color: #ffc107; }
                .status-errored { color: #6c757d; }
                .gem-card { margin-bottom: 1rem; border-left: 4px solid #dee2e6; }
                .gem-card.matching { border-left-color: #28a745; }
                .gem-card.differences { border-left-color: #dc3545; }
                .gem-card.source_not_found { border-left-color: #ffc107; }
                .gem-card.errored { border-left-color: #6c757d; }
                .diff-content {
                    max-height: 500px;
                    overflow-y: auto;
                    font-family: 'Courier New', monospace;
                    font-size: 12px;
                    background-color: #f8f9fa;
                }
                .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
                .filter-buttons .btn { margin: 0.25rem; }
                pre { margin: 0; }
                .collapse-toggle { cursor: pointer; }
                .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; }
            </style>
        </head>
        <body>
            <div class="container-fluid py-4">
                <div class="row">
                    <div class="col-12">
                        <div class="summary-card card text-white mb-4">
                            <div class="card-body">
                                <h1 class="card-title"><i class="fas fa-shield-alt"></i> Sourcecode Verification Report</h1>
                                <p class="card-text">Generated on <%= Time.now.strftime('%B %d, %Y at %I:%M %p') %></p>
                                <div class="stats-grid mt-3">
                                    <div class="text-center">
                                        <h3><%= total_gems %></h3>
                                        <small>Total Gems</small>
                                    </div>
                                    <div class="text-center">
                                        <h3 class="text-success"><%= matching_count %></h3>
                                        <small>Matching</small>
                                    </div>
                                    <div class="text-center">
                                        <h3 class="text-danger"><%= differences_count %></h3>
                                        <small>Differences</small>
                                    </div>
                                    <div class="text-center">
                                        <h3 class="text-warning"><%= source_not_found_count %></h3>
                                        <small>Source Not Found</small>
                                    </div>
                                    <div class="text-center">
                                        <h3 class="text-muted"><%= errored_count %></h3>
                                        <small>Errored</small>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="row">
                    <div class="col-12">
                        <div class="card">
                            <div class="card-body">
                                <div class="d-flex justify-content-between align-items-center mb-3">
                                    <h5 class="card-title mb-0">Gem Analysis Results</h5>
                                    <div class="filter-buttons">
                                        <button class="btn btn-sm btn-outline-secondary active" onclick="filterGems('all')">All</button>
                                        <button class="btn btn-sm btn-outline-success" onclick="filterGems('matching')">Matching</button>
                                        <button class="btn btn-sm btn-outline-danger" onclick="filterGems('differences')">Differences</button>
                                        <button class="btn btn-sm btn-outline-warning" onclick="filterGems('source_not_found')">No Source</button>
                                        <button class="btn btn-sm btn-outline-muted" onclick="filterGems('errored')">Errored</button>
                                    </div>
                                </div>

                                <div id="gem-results">
                                    <% results.sort_by { |r| r[:gem_name] }.each_with_index do |result, index| %>
                                        <div class="card gem-card <%= result[:status] %>" data-status="<%= result[:status] %>">
                                            <div class="card-body">
                                                <div class="row align-items-center">
                                                    <div class="col-md-6">
                                                        <h6 class="card-title mb-1">
                                                            <i class="<%= status_icon(result[:status]) %> status-<%= result[:status] %>"></i>
                                                            <%= result[:gem_name] %>
                                                            <span class="badge bg-secondary"><%= result[:version] %></span>
                                                        </h6>
                                                        <small class="text-muted">
                                                            Status: <span class="status-<%= result[:status] %>"><%= result[:status].humanize %></span>
                                                            • Duration: <%= sprintf('%.2f', result[:duration]) %>s
                                                        </small>
                                                    </div>
                                                    <div class="col-md-6 text-md-end">
                                                        <% if result[:status] == 'differences' && result[:diff_content] %>
                                                            <button class="btn btn-sm btn-outline-primary collapse-toggle"
                                                                    onclick="toggleDiff('diff-<%= index %>')">
                                                                <i class="fas fa-code"></i> View Diff
                                                            </button>
                                                        <% end %>
                                                        <% if result[:error] %>
                                                            <button class="btn btn-sm btn-outline-secondary collapse-toggle"
                                                                    onclick="toggleError('error-<%= index %>')">
                                                                <i class="fas fa-exclamation-triangle"></i> Error Details
                                                            </button>
                                                        <% end %>
                                                    </div>
                                                </div>

                                                <% if result[:summary] && result[:status] == 'differences' %>
                                                    <div class="mt-2">
                                                        <small class="text-muted"><%= result[:summary] %></small>
                                                    </div>
                                                <% end %>

                                                <% if result[:error] %>
                                                    <div id="error-<%= index %>" class="collapse mt-3">
                                                        <div class="alert alert-danger">
                                                            <strong>Error:</strong> <%= CGI.escapeHTML(result[:error]) %>
                                                        </div>
                                                    </div>
                                                <% end %>

                                                <% if result[:diff_content] %>
                                                    <div id="diff-<%= index %>" class="collapse mt-3">
                                                        <div class="diff-content border rounded p-2">
                                                            <pre><code class="language-diff"><%= CGI.escapeHTML(result[:diff_content]) %></code></pre>
                                                        </div>
                                                    </div>
                                                <% end %>
                                            </div>
                                        </div>
                                    <% end %>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.0/js/bootstrap.bundle.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>
            <script>
                function toggleDiff(id) {
                    const element = document.getElementById(id);
                    const button = event.target.closest('button');

                    if (element.classList.contains('show')) {
                        element.classList.remove('show');
                        button.innerHTML = '<i class="fas fa-code"></i> View Diff';
                    } else {
                        element.classList.add('show');
                        button.innerHTML = '<i class="fas fa-code"></i> Hide Diff';
                        Prism.highlightAllUnder(element);
                    }
                }

                function toggleError(id) {
                    const element = document.getElementById(id);
                    const button = event.target.closest('button');

                    if (element.classList.contains('show')) {
                        element.classList.remove('show');
                        button.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Error Details';
                    } else {
                        element.classList.add('show');
                        button.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Hide Error';
                    }
                }

                function filterGems(status) {
                    const cards = document.querySelectorAll('.gem-card');
                    const buttons = document.querySelectorAll('.filter-buttons .btn');

                    // Update button states
                    buttons.forEach(btn => btn.classList.remove('active'));
                    event.target.classList.add('active');

                    // Show/hide cards
                    cards.forEach(card => {
                        if (status === 'all' || card.dataset.status === status) {
                            card.style.display = 'block';
                        } else {
                            card.style.display = 'none';
                        }
                    });
                }

                // Initialize Prism for syntax highlighting
                Prism.highlightAll();
            </script>
        </body>
        </html>
      HTML
    end

    def total_gems
      results.size
    end

    def matching_count
      results.count { |r| r[:status] == 'matching' }
    end

    def differences_count
      results.count { |r| r[:status] == 'differences' }
    end

    def source_not_found_count
      results.count { |r| r[:status] == 'source_not_found' }
    end

    def errored_count
      results.count { |r| r[:status] == 'errored' }
    end

    def status_icon(status)
      case status
      when 'matching' then 'fas fa-check-circle'
      when 'differences' then 'fas fa-exclamation-triangle'
      when 'source_not_found' then 'fas fa-question-circle'
      when 'errored' then 'fas fa-times-circle'
      else 'fas fa-circle'
      end
    end
  end
end
