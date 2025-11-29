# Contributing to Sourcecode Verifier

Thanks for your interest in contributing! This guide will help you get started.

## Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/sourcecode-verifier.git
   cd sourcecode-verifier
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Run the tests**
   ```bash
   # Unit tests only (fast)
   bundle exec rspec
   
   # All tests including integration tests (slower)
   INTEGRATION_TESTS=true bundle exec rspec
   ```

## Testing

### Unit Tests
Fast tests that mock external dependencies:
```bash
bundle exec rspec
```

### Integration Tests
Tests that make real network requests and verify end-to-end functionality:
```bash
INTEGRATION_TESTS=true bundle exec rspec --tag integration
```

**Note:** Integration tests require internet connectivity and may take several minutes.

## Code Style

- Follow Ruby best practices
- Use clear, descriptive variable names
- Add comments for complex logic
- Keep methods focused and small

## Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write tests for new functionality
   - Ensure existing tests pass
   - Update documentation as needed

3. **Run the full test suite**
   ```bash
   # Run unit tests
   bundle exec rspec
   
   # Run integration tests (optional locally, but CI will run them)
   INTEGRATION_TESTS=true bundle exec rspec
   ```

4. **Commit your changes**
   ```bash
   git commit -am "Add your descriptive commit message"
   ```

5. **Push and create a PR**
   ```bash
   git push origin feature/your-feature-name
   ```

## CI/CD Pipeline

The GitHub Actions workflow will automatically:

- ✅ **Test** on Ruby 3.4 with all specs including integration tests

## Adding New Adapters

To add support for new source code platforms (GitLab, Bitbucket, etc.):

1. Create a new adapter in `lib/sourcecode_verifier/adapters/`
2. Follow the interface defined by the GitHub adapter
3. Add tests for the new adapter
4. Update the verifier to recognize the new adapter

## Release Process

1. Update version in `lib/sourcecode_verifier/version.rb`
2. Update CHANGELOG.md
3. Commit changes
4. Create and push a git tag: `git tag v0.x.x && git push origin v0.x.x`
5. GitHub Actions will automatically publish to RubyGems

## Getting Help

- 💬 **Questions or issues**: Open an issue

Thank you for contributing! 🎉