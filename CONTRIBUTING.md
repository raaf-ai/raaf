# Contributing to RAAF (Ruby AI Agents Factory)

Thank you for your interest in contributing to RAAF (Ruby AI Agents Factory)! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Documentation](#documentation)
- [Community](#community)

## Code of Conduct

This project adheres to a code of conduct that we expect all contributors to follow. Please be respectful and constructive in all interactions.

### Our Standards

- **Be respectful**: Treat everyone with respect and kindness
- **Be constructive**: Focus on helping and improving the project
- **Be inclusive**: Welcome newcomers and diverse perspectives
- **Be professional**: Maintain professionalism in all communications

## Getting Started

### Prerequisites

- Ruby 3.0 or higher
- Bundler gem manager
- Git version control
- OpenAI API key (for testing)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/raaf.git
   cd raaf
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/enterprisemodules/raaf.git
   ```

## Development Setup

### Install Dependencies

```bash
# Install Ruby dependencies
bundle install

# Set up environment variables
cp .env.example .env
# Edit .env with your API keys
```

### Environment Variables

Create a `.env` file with:
```bash
OPENAI_API_KEY=your_openai_api_key_here
ANTHROPIC_API_KEY=your_anthropic_api_key_here
GEMINI_API_KEY=your_gemini_api_key_here
```

### Run Tests

```bash
# Run the test suite
bundle exec rspec

# Run with coverage
bundle exec rspec --format documentation

# Run specific tests
bundle exec rspec spec/agent_spec.rb
```

### Run Examples

```bash
# Run the complete feature showcase
ruby examples/complete_features_showcase.rb

# Run specific examples
ruby examples/basic_agent_example.rb
```

## Contributing Guidelines

### Types of Contributions

We welcome various types of contributions:

- **Bug fixes**: Fix issues and improve reliability
- **Features**: Add new functionality and capabilities
- **Documentation**: Improve guides, examples, and API docs
- **Tests**: Add test coverage and improve test quality
- **Performance**: Optimize code and improve efficiency
- **Examples**: Create helpful examples and tutorials

### Development Principles

- **Simplicity**: Keep the API simple and intuitive
- **Reliability**: Ensure robust error handling and validation
- **Performance**: Optimize for speed and memory usage
- **Compatibility**: Maintain backward compatibility when possible
- **Documentation**: Document all public APIs and features

### Code Style

- Follow Ruby community conventions
- Use meaningful variable and method names
- Write clear, concise comments
- Keep methods focused and single-purpose
- Use consistent indentation (2 spaces)

### Commit Messages

Follow conventional commit format:
```
type(scope): description

- feat: new feature
- fix: bug fix
- docs: documentation changes
- style: code style changes
- refactor: code refactoring
- test: test additions/changes
- chore: maintenance tasks
```

Examples:
```
feat(agent): add voice workflow support
fix(runner): handle timeout errors gracefully
docs(examples): add multi-agent workflow example
```

## Pull Request Process

### Before Submitting

1. **Create an issue**: Discuss major changes first
2. **Fork and branch**: Create a feature branch
3. **Develop**: Implement your changes
4. **Test**: Ensure all tests pass
5. **Document**: Update documentation as needed

### Submitting a Pull Request

1. **Update your fork**:
   ```bash
   git fetch upstream
   git checkout main
   git rebase upstream/main
   ```

2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**:
   - Implement your feature or fix
   - Add tests for new functionality
   - Update documentation
   - Ensure code style compliance

4. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat(scope): description of changes"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create pull request**:
   - Go to GitHub and create a pull request
   - Fill out the PR template
   - Link any related issues

### Pull Request Guidelines

- **Clear description**: Explain what changes you made and why
- **Small, focused**: Keep PRs focused on a single feature or fix
- **Tests included**: Add tests for new functionality
- **Documentation**: Update relevant documentation
- **No breaking changes**: Avoid breaking existing APIs

### Review Process

1. **Automated checks**: Ensure CI passes
2. **Code review**: Maintainers will review your code
3. **Feedback**: Address any requested changes
4. **Approval**: PR will be approved and merged

## Issue Reporting

### Bug Reports

When reporting bugs, include:

- **Ruby version**: Which version you're using
- **Gem version**: Which version of the gem
- **Error messages**: Full error messages and stack traces
- **Reproduction steps**: How to reproduce the issue
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened

### Feature Requests

For feature requests, include:

- **Use case**: Why is this feature needed?
- **Proposed solution**: How should it work?
- **Alternatives**: What alternatives have you considered?
- **Examples**: Provide usage examples if possible

### Issue Templates

Use the provided issue templates when available:
- Bug report template
- Feature request template
- Documentation improvement template

## Development Workflow

### Branching Strategy

- `main`: Stable release branch
- `develop`: Integration branch for features
- `feature/*`: Feature development branches
- `hotfix/*`: Critical bug fixes

### Release Process

1. **Feature development**: Develop on feature branches
2. **Integration**: Merge to develop branch
3. **Testing**: Comprehensive testing on develop
4. **Release**: Merge to main and tag version
5. **Deployment**: Publish gem to RubyGems

### Version Management

We follow [Semantic Versioning](https://semver.org/):
- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes (backward compatible)

## Testing

### Test Structure

```
spec/
├── spec_helper.rb          # Test configuration
├── support/                # Test utilities
├── unit/                   # Unit tests
├── integration/            # Integration tests
└── examples/               # Example tests
```

### Writing Tests

- Use RSpec for testing
- Write descriptive test names
- Test both success and failure cases
- Mock external API calls
- Aim for high test coverage

### Test Categories

- **Unit tests**: Test individual classes and methods
- **Integration tests**: Test component interactions
- **Example tests**: Verify examples work correctly
- **Performance tests**: Test performance characteristics

### Running Tests

```bash
# All tests
bundle exec rspec

# Specific test file
bundle exec rspec spec/agent_spec.rb

# Specific test
bundle exec rspec spec/agent_spec.rb:25

# With coverage
bundle exec rspec --format documentation
```

## Documentation

### Types of Documentation

- **API documentation**: RDoc comments in code
- **Guides**: Comprehensive how-to guides
- **Examples**: Working code examples
- **README**: Project overview and quick start

### Documentation Standards

- **Clear and concise**: Easy to understand
- **Complete**: Cover all parameters and options
- **Examples**: Include usage examples
- **Up-to-date**: Keep documentation current

### Generating Documentation

```bash
# Generate RDoc documentation
bundle exec yard doc

# Serve documentation locally
bundle exec yard server
```

## Community

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and community discussions
- **Pull Requests**: Code contributions and reviews

### Getting Help

- Check existing issues and discussions
- Read the documentation and examples
- Ask questions in GitHub Discussions
- Join community discussions

### Recognition

Contributors are recognized in:
- CHANGELOG.md for significant contributions
- README.md acknowledgments
- GitHub contributor graphs
- Release notes

## Development Tips

### Debugging

- Use the built-in REPL for interactive testing
- Enable tracing for debugging complex workflows
- Use the debugging module for step-by-step execution
- Add logging for production debugging

### Performance

- Profile code for performance bottlenecks
- Use efficient data structures
- Minimize API calls
- Cache expensive operations

### Best Practices

- Follow Ruby idioms and conventions
- Use dependency injection for testability
- Handle errors gracefully
- Validate inputs and outputs
- Write self-documenting code

## Thank You

Thank you for contributing to RAAF (Ruby AI Agents Factory)! Your contributions help make this project better for everyone.

For questions or help with contributing, please open an issue or start a discussion on GitHub.

---

**Happy coding!** 🚀