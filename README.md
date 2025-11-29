# Sourcecode Verifier
A Ruby gem that downloads published gems from RubyGems.org and compares them with source code from repositories like GitHub to verify integrity and detect differences.

## Features

- Download gems from RubyGems.org and extract their contents
- Automatically discover GitHub repositories for gems
- Download source code from GitHub using version tags
- Compare gem files with source code files using git diff
- Generate detailed reports showing differences
- Support for local file verification (optimized flow)
- **CLI tool with smart caching** - Downloads stored locally for repeated analysis
- **Intelligent cache management** - Warns when using cached content, organized by gem/version
- Extensible adapter system for different source code platforms

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sourcecode_verifier'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sourcecode_verifier

## Usage

### Command Line Interface (CLI)

The gem includes a CLI tool for easy verification from the command line:

#### Basic Usage

```bash
# Verify any gem against its GitHub source
./exe/sourcecode-verifier <gem_name> <version>

# Example: verify the base64 gem
./exe/sourcecode-verifier base64 0.2.0
```

#### CLI Options

```bash
Usage: sourcecode-verifier [options] <gem_name> <version>

Options:
  -r, --repo REPO          GitHub repository (owner/repo)
  -t, --token TOKEN        GitHub token for private repos
  -c, --cache-dir DIR      Cache directory (default: ./cache)
  -v, --verbose            Verbose output
  -h, --help               Show this help

Examples:
  sourcecode-verifier rails 7.0.0
  sourcecode-verifier --repo myorg/mygem mygem 1.0.0
  sourcecode-verifier --token $GITHUB_TOKEN private_gem 0.1.0
  sourcecode-verifier --verbose --cache-dir /tmp/cache rails 6.1.0
```

#### CLI Output

```bash
$ ./exe/sourcecode-verifier --verbose base64 0.2.0
Verifying base64 version 0.2.0...
Downloading gem base64-0.2.0...
Downloading source for base64-0.2.0...

=== Sourcecode Verification Report ===
Gem: base64 (0.2.0)
Timestamp: 2025-11-29 11:23:10 -0500

⚠ Differences found:
  - 9 file(s) only in source
  - 6 file(s) modified

Files only in source (9):
  - .github/dependabot.yml
  - .github/workflows/test.yml
  - .gitignore
  - Gemfile
  - Rakefile
  - base64.gemspec
  - bin/console
  - bin/setup
  - test/base64/test_base64.rb

Modified files (6):
  ~ lib/base64.rb
  ~ README.md
  [...]

Detailed diff saved to: sourcecode_diff_20251129_112310.diff
```

#### Caching

The CLI tool automatically caches downloads in the `./cache` directory:

```
./cache/
├── gems/           # Extracted gem files
│   └── base64-0.2.0/
└── sources/        # GitHub source files
    └── ruby_base64-0.2.0/
```

When content is already cached:

```bash
$ ./exe/sourcecode-verifier --verbose base64 0.2.0
Verifying base64 version 0.2.0...
⚠ Using cached gem content for base64-0.2.0
⚠ Using cached source content for base64-0.2.0
[... continues with verification ...]
```

#### Exit Codes

- `0`: Files are identical
- `1`: Differences found
- `2`: Error (missing arguments, gem not found, etc.)
- `3`: Interrupted by user (Ctrl+C)
- `4`: Unexpected error

### Ruby API

#### Basic Verification

```ruby
require 'sourcecode_verifier'

# Verify a gem against its GitHub source
report = SourcecodeVerifier.verify('rails', '7.0.0')

puts report.summary
puts "Identical: #{report.identical?}"
puts "Diff file: #{report.diff_file_path}"
```

#### Advanced Options

```ruby
# Specify a custom GitHub repository
report = SourcecodeVerifier.verify('my_gem', '1.0.0', {
  github_repo: 'myusername/my_gem',
  github_token: 'your_github_token', # Optional, for private repos
  cache_dir: './my_cache',           # Custom cache directory
  verbose: true                      # Enable verbose output
})

# Use local files (optimized flow)
report = SourcecodeVerifier.verify_local('/path/to/gem/files', '/path/to/source/code')
```

### Working with Reports

```ruby
report = SourcecodeVerifier.verify('rails', '7.0.0')

# Check if files are identical
if report.identical?
  puts "✓ Gem and source code match perfectly!"
else
  puts "⚠ Differences found:"

  # Show files only in gem
  puts "Files only in gem: #{report.gem_only_files}"

  # Show files only in source
  puts "Files only in source: #{report.source_only_files}"

  # Show modified files
  puts "Modified files: #{report.modified_files}"

  # Get the detailed diff
  puts File.read(report.diff_file_path)
end

# Save report as JSON
report.save_report('verification_report.json')

# Print formatted summary
report.print_summary
```

## Configuration

### GitHub Token

For private repositories or to avoid rate limiting, set your GitHub token:

```ruby
report = SourcecodeVerifier.verify('private_gem', '1.0.0', {
  github_token: ENV['GITHUB_TOKEN']
})
```

### Custom Repository

If the gem's GitHub repository can't be automatically discovered:

```ruby
report = SourcecodeVerifier.verify('gem_name', '1.0.0', {
  github_repo: 'owner/repository'
})
```

## Adapters

Currently supported source code platforms:

- **GitHub**: Automatically discovers repositories and downloads source code by version tags

Future adapters planned:
- GitLab
- Bitbucket
- Generic Git repositories

## How It Works

1. **Download Gem**: Downloads the specified gem version from RubyGems.org and extracts its files
2. **Discover Source**: Automatically finds the GitHub repository from gem metadata
3. **Download Source**: Downloads the source code archive for the matching version tag
4. **Compare**: Uses git diff to compare the extracted gem files with the source code
5. **Report**: Generates a detailed report showing all differences

## Development

After checking out the repo, run:

```bash
bundle install
```

To run tests:

```bash
rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/sourcecode-verifier.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
