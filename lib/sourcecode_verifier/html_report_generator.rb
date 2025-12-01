require 'erb'
require 'cgi'
require 'fileutils'
require 'set'

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
      base_reports_dir = SourcecodeVerifier::PathUtils.determine_reports_directory
      reports_dir = File.join(base_reports_dir, 'html')
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
                                        <div class="mb-2">
                                            <strong>Status Filter:</strong>
                                            <button class="btn btn-sm btn-outline-secondary active" onclick="filterByStatus('all')">All</button>
                                            <button class="btn btn-sm btn-outline-success" onclick="filterByStatus('matching')">Matching</button>
                                            <button class="btn btn-sm btn-outline-danger" onclick="filterByStatus('differences')">Differences</button>
                                            <button class="btn btn-sm btn-outline-warning" onclick="filterByStatus('source_not_found')">No Source</button>
                                            <button class="btn btn-sm btn-outline-muted" onclick="filterByStatus('errored')">Errored</button>
                                        </div>
                                        <div>
                                            <strong>Group Filter:</strong>
                                            <button class="btn btn-sm btn-outline-primary active" onclick="filterByGroup('all')">All Groups</button>
                                            <% all_groups.each do |group| %>
                                                <button class="btn btn-sm btn-outline-info" onclick="filterByGroup('<%= group %>')">
                                                    <%= group.to_s.capitalize %> (<%= gems_in_group(group).size %>)
                                                </button>
                                            <% end %>
                                        </div>
                                    </div>
                                </div>

                                <div id="gem-results">
                                    <% results.sort_by { |r| r[:gem_name] }.each_with_index do |result, index| %>
                                        <div class="card gem-card <%= result[:status] %>" data-status="<%= result[:status] %>" data-groups="<%= (result[:groups] || [:default]).join(',') %>">
                                            <div class="card-body">
                                                <div class="row align-items-center">
                                                    <div class="col-md-6">
                                                        <h6 class="card-title mb-1">
                                                            <i class="<%= status_icon(result[:status]) %> status-<%= result[:status] %>"></i>
                                                            <%= result[:gem_name] %>
                                                            <span class="badge bg-secondary"><%= result[:version] %></span>
                                                            <% (result[:groups] || [:default]).each do |group| %>
                                                                <span class="badge <%= group_badge_class(group) %>"><%= group %></span>
                                                            <% end %>
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
                                                        <% if result[:status] == 'differences' && has_file_differences?(result) %>
                                                            <button class="btn btn-sm btn-outline-info collapse-toggle"
                                                                    onclick="toggleFileDetails('files-<%= index %>')">
                                                                <i class="fas fa-list"></i> File Details
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

                                                <% if result[:status] == 'differences' && has_file_differences?(result) %>
                                                    <div id="files-<%= index %>" class="collapse mt-3">
                                                        <div class="card">
                                                            <div class="card-body">
                                                                <h6 class="card-title">File Analysis Details</h6>
                                                                
                                                                <% if result[:gem_only_files] && !result[:gem_only_files].empty? %>
                                                                    <div class="mb-3">
                                                                        <h6 class="text-warning">
                                                                            <i class="fas fa-exclamation-triangle"></i> Files only in gem (<%= result[:gem_only_files].size %>)
                                                                        </h6>
                                                                        <small class="text-muted mb-2 d-block">
                                                                            These files are packaged in the published gem but not present in the source repository.
                                                                            <strong>Security concern:</strong> Unknown origin of these files - could be build artifacts, generated files, or potentially malicious additions.
                                                                            Investigate each file to ensure it's legitimate.
                                                                        </small>
                                                                        <div class="bg-light rounded p-2">
                                                                            <ul class="list-unstyled mb-0 small">
                                                                                <% result[:gem_only_files].each do |file| %>
                                                                                    <li class="text-warning">
                                                                                        <i class="fas fa-exclamation-triangle"></i> <%= CGI.escapeHTML(file) %>
                                                                                    </li>
                                                                                <% end %>
                                                                            </ul>
                                                                        </div>
                                                                    </div>
                                                                <% end %>

                                                                <% if result[:source_only_files] && !result[:source_only_files].empty? %>
                                                                    <div class="mb-3">
                                                                        <h6 class="text-muted">
                                                                            <i class="fas fa-info-circle"></i> Files only in source (<%= result[:source_only_files].size %>)
                                                                        </h6>
                                                                        <small class="text-muted mb-2 d-block">
                                                                            These files are present in the source repository but not packaged in the published gem.
                                                                            This is normal and expected - these are typically development files, tests, documentation, or build configurations.
                                                                            <strong>No security concern.</strong>
                                                                        </small>
                                                                        <div class="bg-light rounded p-2">
                                                                            <ul class="list-unstyled mb-0 small">
                                                                                <% result[:source_only_files].each do |file| %>
                                                                                    <li class="text-muted">
                                                                                        <i class="fas fa-info"></i> <%= CGI.escapeHTML(file) %>
                                                                                    </li>
                                                                                <% end %>
                                                                            </ul>
                                                                        </div>
                                                                    </div>
                                                                <% end %>

                                                                <% if result[:modified_files] && !result[:modified_files].empty? %>
                                                                    <div class="mb-3">
                                                                        <h6 class="text-danger">
                                                                            <i class="fas fa-times-circle"></i> Modified files (<%= result[:modified_files].size %>)
                                                                        </h6>
                                                                        <small class="text-muted mb-2 d-block">
                                                                            These files exist in both gem and source but have content differences.
                                                                            <strong>Security risk:</strong> The gem contains different code than the source repository.
                                                                            This could indicate unauthorized modifications, build issues, or version mismatches.
                                                                        </small>
                                                                        <div class="bg-light rounded p-2">
                                                                            <ul class="list-unstyled mb-0 small">
                                                                                <% result[:modified_files].each do |file| %>
                                                                                    <li class="text-danger">
                                                                                        <i class="fas fa-times-circle"></i> <%= CGI.escapeHTML(file) %>
                                                                                    </li>
                                                                                <% end %>
                                                                            </ul>
                                                                        </div>
                                                                    </div>
                                                                <% end %>
                                                            </div>
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

                function toggleFileDetails(id) {
                    const element = document.getElementById(id);
                    const button = event.target.closest('button');

                    if (element.classList.contains('show')) {
                        element.classList.remove('show');
                        button.innerHTML = '<i class="fas fa-list"></i> File Details';
                    } else {
                        element.classList.add('show');
                        button.innerHTML = '<i class="fas fa-list"></i> Hide Details';
                    }
                }

                let currentStatusFilter = 'all';
                let currentGroupFilter = 'all';

                function filterByStatus(status) {
                    currentStatusFilter = status;
                    
                    // Update button states - only for status buttons
                    const statusButtons = document.querySelectorAll('[onclick^="filterByStatus"]');
                    statusButtons.forEach(btn => btn.classList.remove('active'));
                    event.target.classList.add('active');

                    applyFilters();
                }

                function filterByGroup(group) {
                    currentGroupFilter = group;
                    
                    // Update button states - only for group buttons
                    const groupButtons = document.querySelectorAll('[onclick^="filterByGroup"]');
                    groupButtons.forEach(btn => btn.classList.remove('active'));
                    event.target.classList.add('active');

                    applyFilters();
                }

                function applyFilters() {
                    const cards = document.querySelectorAll('.gem-card');

                    cards.forEach(card => {
                        let statusMatch = currentStatusFilter === 'all' || card.dataset.status === currentStatusFilter;
                        let groupMatch = currentGroupFilter === 'all' || 
                                        card.dataset.groups.split(',').includes(currentGroupFilter);

                        if (statusMatch && groupMatch) {
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

    def has_file_differences?(result)
      (result[:gem_only_files] && !result[:gem_only_files].empty?) ||
      (result[:source_only_files] && !result[:source_only_files].empty?) ||
      (result[:modified_files] && !result[:modified_files].empty?)
    end

    def all_groups
      groups = Set.new
      results.each do |result|
        groups.merge(result[:groups] || [:default])
      end
      groups.to_a.sort
    end

    def gems_in_group(group)
      results.select { |result| (result[:groups] || [:default]).include?(group) }
    end

    def group_badge_class(group)
      case group.to_s
      when 'default'
        'bg-primary'
      when 'development'
        'bg-info'
      when 'test'
        'bg-success'
      when 'production'
        'bg-warning text-dark'
      else
        'bg-secondary'
      end
    end
  end
end
