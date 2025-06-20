# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the OpenAI Agents Ruby project. All workflows are designed to work with free GitHub accounts, with optional paid features clearly marked and commented out.

## Workflows Overview

### 🔄 CI Workflow (`ci.yml`)
**Purpose**: Continuous Integration testing and validation
- ✅ **Free Features**:
  - Multi-Ruby version testing (3.0, 3.1, 3.2, 3.3)
  - RuboCop linting
  - Bundle audit security checks
  - Gem building and validation
  - Example syntax validation
- 💰 **Optional Paid Features** (commented out):
  - Codecov coverage reporting (requires free Codecov account)

### 🚀 Release Workflow (`release.yml`)
**Purpose**: Automated releases when tags are pushed
- ✅ **Free Features**:
  - Full test suite execution
  - GitHub Release creation with release notes
  - Gem building and validation
- 💰 **Optional Paid Features** (commented out):
  - RubyGems publishing (requires free RubyGems.org account)

### 🛡️ Security Workflow (`security.yml`)
**Purpose**: Security scanning and vulnerability detection
- ✅ **Free Features**:
  - Bundle audit dependency scanning
  - Brakeman security analysis
  - CodeQL security analysis
  - Dependency review for PRs
  - License compliance checking
  - Security policy validation
- 💰 **Optional Paid Features** (commented out):
  - TruffleHog secret scanning (free but may have rate limits)

### 📚 Documentation Workflow (`docs.yml`)
**Purpose**: Documentation generation and validation
- ✅ **Free Features**:
  - YARD documentation generation
  - Documentation coverage analysis
  - README/EXAMPLES.md validation
  - Markdown link checking
  - Spell checking with custom dictionary
  - Documentation quality metrics
- 💰 **Optional Paid Features** (commented out):
  - GitHub Pages deployment (requires Pages enabled in settings)

### 🔍 CodeQL Workflow (`codeql.yml`)
**Purpose**: Advanced security analysis
- ✅ **Free Features**:
  - GitHub's CodeQL security analysis
  - Scheduled weekly scans
  - Ruby-specific security patterns

### ⚡ Performance Workflow (`performance.yml`)
**Purpose**: Performance testing and benchmarking
- ✅ **Free Features**:
  - Benchmark-ips performance testing
  - Memory profiling and leak detection
  - Load testing with concurrent operations
  - CPU profiling for bottleneck identification
  - Gem size and complexity analysis

## Setup Instructions

### Required Secrets (Optional)
To enable commented-out features, add these secrets in your GitHub repository settings:

1. **For RubyGems Publishing**:
   - `RUBYGEMS_API_KEY`: Your RubyGems.org API key

2. **For Test API Keys** (if needed):
   - `OPENAI_API_KEY_TEST`: Test API key for OpenAI
   - `ANTHROPIC_API_KEY_TEST`: Test API key for Anthropic
   - `GEMINI_API_KEY_TEST`: Test API key for Google Gemini

### Optional Integrations

1. **Codecov** (Free):
   - Sign up at [codecov.io](https://codecov.io)
   - Enable your repository
   - Uncomment the codecov section in `ci.yml`

2. **GitHub Pages** (Free):
   - Enable Pages in repository Settings → Pages
   - Uncomment the GitHub Pages deployment in `docs.yml`

3. **RubyGems Publishing** (Free):
   - Create account at [rubygems.org](https://rubygems.org)
   - Generate API key in your profile
   - Add `RUBYGEMS_API_KEY` secret
   - Uncomment the publishing section in `release.yml`

## Workflow Features

### 🎯 Production Ready
- Comprehensive error handling
- Proper caching for faster builds
- Security best practices
- Artifact uploads for debugging

### 🔒 Security Focused
- Multiple security scanning tools
- Dependency vulnerability checking
- Secret detection capabilities
- License compliance validation

### 📊 Quality Assurance
- Multi-version Ruby testing
- Code style enforcement
- Documentation coverage
- Performance monitoring

### 🚀 Automated Releases
- Tag-based release triggering
- Automatic release note generation
- Gem validation before publishing
- Success/failure notifications

## Customization

### Adding New Ruby Versions
Edit the matrix in workflows:
```yaml
strategy:
  matrix:
    ruby-version: ['3.0', '3.1', '3.2', '3.3', '3.4']  # Add new versions
```

### Enabling Optional Features
1. Uncomment the desired sections
2. Add required secrets if needed
3. Test with a pull request

### Custom Domains
For GitHub Pages with custom domain:
```yaml
cname: docs.your-domain.com  # Uncomment and modify
```

## Troubleshooting

### Common Issues

1. **Workflow Permissions**:
   - Ensure Actions have write permissions in Settings → Actions → General

2. **Secret Access**:
   - Check that secrets are properly set in repository settings
   - Verify secret names match exactly

3. **Rate Limits**:
   - Some tools may have rate limits on public repositories
   - Consider scheduling workflows during off-peak hours

### Support

For issues with specific workflows:
1. Check the Actions tab for detailed logs
2. Review the workflow file for configuration
3. Verify all required dependencies are available

## License

These workflows are part of the OpenAI Agents Ruby project and are licensed under the MIT License.

---

🤖 **Generated with AI assistance**