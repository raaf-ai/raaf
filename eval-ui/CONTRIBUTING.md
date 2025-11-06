# Contributing to RAAF Eval UI

Thank you for your interest in contributing to RAAF Eval UI! This document provides guidelines for contributing to the project.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/ruby-ai-agents-factory.git
   cd ruby-ai-agents-factory/eval-ui
   ```
3. **Install dependencies**:
   ```bash
   bundle install
   ```
4. **Set up the test database**:
   ```bash
   cd spec/dummy
   rails db:migrate RAILS_ENV=test
   cd ../..
   ```

## Development Workflow

### Running Tests

```bash
# Run all specs
bundle exec rspec

# Run specific spec file
bundle exec rspec spec/models/raaf/eval/ui/session_spec.rb

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a
```

### Testing Your Changes

1. Create a test Rails application:
   ```bash
   cd spec/dummy
   rails server
   ```
2. Navigate to `http://localhost:3000/eval` to test the engine

## Contribution Guidelines

### Code Style

- Follow the Ruby Style Guide
- Use meaningful variable and method names
- Write descriptive commit messages
- Keep methods small and focused
- Add comments for complex logic

### Testing

- Write tests for all new features
- Ensure existing tests pass before submitting PR
- Aim for 95%+ code coverage
- Include both unit and integration tests

### Documentation

- Update README.md for user-facing changes
- Add YARD documentation for public APIs
- Include code examples where appropriate
- Update CHANGELOG.md with your changes

### Pull Request Process

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Write clean, tested code
   - Follow existing patterns
   - Update documentation

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

   Use conventional commits:
   - `feat:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation changes
   - `test:` for test additions/changes
   - `refactor:` for code refactoring
   - `chore:` for maintenance tasks

4. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create a Pull Request**:
   - Provide a clear description of changes
   - Reference any related issues
   - Ensure CI checks pass
   - Request review from maintainers

### What to Contribute

We welcome contributions in these areas:

- **Bug fixes**: Fix reported issues
- **New features**: Add functionality aligned with project goals
- **Documentation**: Improve guides and examples
- **Tests**: Increase test coverage
- **Performance**: Optimize existing code
- **Accessibility**: Improve UI accessibility
- **Internationalization**: Add translations

### Questions or Need Help?

- Open an issue for discussion
- Join our community chat
- Email: team@raaf.dev

## Code of Conduct

Please note that this project is released with a Contributor Code of Conduct. By participating in this project you agree to abide by its terms.

## License

By contributing to RAAF Eval UI, you agree that your contributions will be licensed under the MIT License.
