# Integration Tests

This project includes integration tests that verify the bundled analysis functionality by actually downloading gems and analyzing them. These tests are excluded from the default test run because they:

- Make real network requests to RubyGems.org and GitHub
- Download and cache actual gem files
- Take significantly longer to run than unit tests
- May be affected by external service availability

## Running Integration Tests

### Run all tests including integration tests:
```bash
INTEGRATION_TESTS=true rspec
```

### Run only integration tests:
```bash
INTEGRATION_TESTS=true rspec --tag integration
```

### Run normal tests (excluding integration tests - default):
```bash
rspec
```

## What the Integration Tests Cover

### Bundled Analyzer Integration Test (`spec/bundled_analyzer_spec.rb`)

- **Full workflow testing**: Tests the complete bundled analysis workflow with real gems
- **HTML report generation**: Verifies that HTML reports are created correctly
- **ZIP file creation**: Tests CI-friendly ZIP archive generation
- **Error handling**: Tests various failure scenarios (missing repos, network errors)
- **Bundle list parsing**: Verifies correct parsing of `bundle list` output
- **Status classification**: Tests gem status detection (matching/differences/source_not_found/errored)

### Test Gems Used

The integration tests use a small subset of well-known, stable gems:
- `base64` - Ruby standard library gem
- `json` - Core JSON handling gem  
- `rake` - Ruby build tool

These gems are chosen because they:
- Have stable GitHub repositories
- Are unlikely to change frequently
- Represent different types of gems (stdlib, core functionality, tools)
- Should consistently return "matching" status

## Notes

- Integration tests may take 30-60 seconds to complete due to network operations
- Tests will create cache directories and temporary files
- Network connectivity to RubyGems.org and GitHub is required
- Some tests may fail if external services are unavailable

## CI Considerations

In CI environments, you can run integration tests as a separate job:

```yaml
# Example GitHub Actions
- name: Run integration tests
  run: INTEGRATION_TESTS=true bundle exec rspec --tag integration
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```