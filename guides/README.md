# RAAF Documentation

This directory contains the documentation for Ruby AI Agents Factory (RAAF), built using a Rails Guides-inspired system.

## 🚀 Live Documentation

The documentation is automatically deployed to GitHub Pages at: **https://guides.raaf-ai.dev/**

[![📚 Guides Build & Deploy](https://github.com/raaf-ai/raaf/actions/workflows/guides-build-deploy.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/guides-build-deploy.yml)

## 📁 Structure

```
guides/
├── source/              # Markdown source files
├── output/              # Generated HTML files (auto-deployed)
├── assets/              # CSS, JavaScript, images
├── raaf_guides/         # Build system
└── .github/workflows/   # GitHub Actions for deployment
```

## 🏗️ Local Development

### Prerequisites
- Ruby 3.1+
- Bundler

### Setup
```bash
bundle install
```

### Build Documentation
```bash
# Generate HTML guides
bundle exec rake guides:generate:html

# Generate specific guide only
ONLY=getting_started bundle exec rake guides:generate:html

# Generate all guides
ALL=1 bundle exec rake guides:generate:html
```

### Preview Locally
```bash
# Serve the output directory
cd output
python -m http.server 8000
# Visit http://localhost.com:8000
```

## 🔧 Adding New Guides

1. Create a new `.md` file in the `source/` directory
2. Add it to `source/documents.yaml`
3. Run the build command
4. Commit and push to trigger deployment

## 📝 Writing Guidelines

- Follow the style guide in `source/CLAUDE.md`
- Use pragmatic, story-driven examples
- Include real-world code samples
- Test all code examples

## 🚀 Deployment

Documentation is automatically deployed via GitHub Actions when:
- Changes are pushed to the `main` branch in the `guides/` directory
- The [`guides-build-deploy.yml`](../.github/workflows/guides-build-deploy.yml) workflow runs
- Validation steps: markdown linting, code validation, link checking
- Build step: `bundle exec rake guides:generate:html`
- Generated files in `output/` are deployed to GitHub Pages

**Workflow triggers:**
- 📝 Push to `main`/`develop` with `guides/**` changes
- 🔄 Pull requests to `main`/`develop` with `guides/**` changes  
- 🚀 Manual dispatch for on-demand builds

## 🔍 Validation

```bash
# Lint markdown files
bundle exec rake guides:lint:mdl

# Check for broken links
bundle exec rake guides:lint:check_links

# Validate HTML output
bundle exec rake guides:validate

# Validate code examples  
ruby code_validator.rb            # Mark failing examples (default)
ruby code_validator.rb validate   # Check all code examples only
ruby code_validator.rb unmark     # Remove failure markers
```

### Code Example Validation

All Ruby code examples in the documentation are automatically validated for syntax and execution errors. When examples fail validation, they are marked with clear warnings in the documentation:

```
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! 
Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
[technical error details]
```
```

**How it works:**
- The `code_validator.rb` script extracts all Ruby code blocks from markdown files
- Each code block is executed in isolation to check for errors
- Failed examples are tagged with helpful error messages and contribution invitations
- This helps maintain documentation quality while encouraging community contributions

**Commands:**
- `ruby code_validator.rb` - Mark failing examples (default behavior)
- `ruby code_validator.rb validate` - Run validation and show summary only
- `ruby code_validator.rb mark` - Add warning markers to failing examples  
- `ruby code_validator.rb unmark` - Remove all validation markers

## 📚 Available Guides

- **Getting Started**: Introduction to RAAF
- **Core Guide**: Core concepts and architecture
- **Tools Guide**: Built-in and custom tools
- **Memory Guide**: Memory management and strategies
- **Providers Guide**: Multi-provider support
- **Testing Guide**: Testing patterns and best practices
- **Deployment Guide**: Production deployment
- **API Reference**: Complete API documentation

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Add or update documentation
4. Test locally with `bundle exec rake guides:generate:html`
5. Submit a pull request

## Technical Details

### Styling System
The visual styling uses SCSS in `stylesrc/` directory with:
- `include_media` for responsive design
- `normalize.css` for browser compatibility
- Dark mode support in separate files

### Build Process
Run `rake guides:generate` to build static files. Remove the `output/` directory before rebuilding if you change HTML/ERB templates.

## 📄 License

This documentation is licensed under the same terms as the RAAF project.