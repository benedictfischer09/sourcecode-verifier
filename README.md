# Sourcecode Verifier

A Ruby gem that downloads published gems from RubyGems.org and compares them with source code from repositories like GitHub to verify integrity and detect differences.

## Features

- Download gems from RubyGems.org and extract their contents
- Automatically discover GitHub repositories for gems
- Download source code from GitHub using version tags
- Compare gem files with source code files using git diff
- Generate detailed reports showing differences
- Support for local file verification (optimized flow)
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

### Basic Verification

```ruby
require 'sourcecode_verifier'

# Verify a gem against its GitHub source
report = SourcecodeVerifier.verify('rails', '7.0.0')

puts report.summary
puts "Identical: #{report.identical?}"
puts "Diff file: #{report.diff_file_path}"
```

### Advanced Options

```ruby
# Specify a custom GitHub repository
report = SourcecodeVerifier.verify('my_gem', '1.0.0', {
  github_repo: 'myusername/my_gem',
  github_token: 'your_github_token' # Optional, for private repos
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