# Contributing to Ruby AI Agents Factory - voice

Thank you for your interest in contributing to the Ruby AI Agents Factory voice gem\! This document provides guidelines for contributing to this specific gem.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Style Guide](#style-guide)
- [Questions](#questions)

## Code of Conduct

This project adheres to the Ruby AI Agents Factory Code of Conduct. By participating, you are expected to uphold this code.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally
3. Create a new branch for your feature or bugfix
4. Make your changes
5. Test your changes
6. Submit a pull request

## Development Setup

```bash
# Clone the repository
git clone https://github.com/your-username/ruby-ai-agents-factory.git
cd ruby-ai-agents-factory

# Navigate to the voice gem
cd voice

# Install dependencies
bundle install

# Run tests
bundle exec rspec
```

## Making Changes

### Branch Naming

- Feature branches: `feature/description`
- Bug fix branches: `fix/description`
- Documentation: `docs/description`

### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line

### Code Changes

1. **Follow Ruby conventions**: Use 2-space indentation, snake_case for variables and methods
2. **Write tests**: All new features should have corresponding tests
3. **Update documentation**: Update README.md and inline documentation as needed
4. **Follow existing patterns**: Look at existing code for patterns and conventions

## Testing

```bash
# Run all tests
bundle exec rspec

# Run tests with coverage
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/specific_test_spec.rb
```

## Submitting Changes

1. **Create a pull request** against the main branch
2. **Provide a clear description** of what your changes do
3. **Include tests** for any new functionality
4. **Update documentation** as needed
5. **Ensure all tests pass**
6. **Follow the pull request template**

### Pull Request Guidelines

- Keep pull requests focused on a single change
- Write clear, descriptive commit messages
- Include tests for new functionality
- Update documentation as needed
- Ensure all CI checks pass

## Style Guide

### Ruby Style

We follow the [Ruby Style Guide](https://rubystyle.guide/) with these specific conventions:

- **Line length**: 120 characters maximum
- **Indentation**: 2 spaces, no tabs
- **Method names**: snake_case
- **Class names**: PascalCase
- **Constants**: SCREAMING_SNAKE_CASE

### Documentation

- **YARD comments**: Use YARD format for method documentation
- **README updates**: Update README.md for user-facing changes
- **Examples**: Include usage examples for new features

### Testing

- **RSpec**: Use RSpec for testing
- **Test coverage**: Aim for high test coverage
- **Test naming**: Use descriptive test names
- **Mock external services**: Don't make real API calls in tests

## Questions

If you have questions about contributing:

1. **Check existing issues** on GitHub
2. **Create a new issue** with the "question" label
3. **Join our community** discussions
4. **Review the main project** documentation

## Recognition

Contributors will be recognized in:
- The project README
- Release notes
- The contributors list

Thank you for contributing to Ruby AI Agents Factory\!
