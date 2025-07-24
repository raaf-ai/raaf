# RAAF Core GitHub Actions Workflows

This directory contains a comprehensive CI/CD setup for the RAAF core gem with multiple workflow types optimized for different use cases and fail-fast feedback.

## 🏗️ Workflow Architecture

### 1. **core-ci.yml** - Main CI Pipeline
**Triggers**: Push/PR to `main`/`develop` with core changes  
**Purpose**: Comprehensive testing with fail-fast strategy  
**Duration**: ~8-12 minutes

**Staged Execution Order:**
1. **🔍 Lint & Style** - Fast syntax and style checks (RuboCop, bundle audit)
2. **🧪 Unit Tests** - Core functionality (Ruby 3.2, 3.3, 3.4 matrix)
3. **🤖 Models & Providers** - Critical integration points
4. **⚠️ Edge Cases** - Boundary condition testing
5. **🔗 Integration Tests** - External dependency testing
6. **📋 Compliance Tests** - Standards validation (runs parallel)
7. **✅ Acceptance Tests** - End-to-end scenarios
8. **⚡ Performance Tests** - Resource intensive (continue-on-error)
9. **💰 Cost Analysis** - Expensive operations (continue-on-error)
10. **📦 Build Gem** - Final validation (runs parallel after core tests)
11. **📊 Test Summary** - Results aggregation and status

### 2. **core-quick-check.yml** - Development Feedback
**Triggers**: Feature/fix branches, PRs marked ready for review  
**Purpose**: Fast feedback for developers  
**Duration**: ~2-3 minutes

**Quick Execution:**
- **⚡ Quick Lint** - Parallel RuboCop execution
- **🧪 Essential Tests** - Only critical unit tests (agent, runner, models)
- **💨 Smoke Test** - Basic gem loading and functionality verification
- **✓ Status Check** - Summary report for PR reviews

### 3. **core-nightly.yml** - Comprehensive Analysis
**Triggers**: Nightly schedule (2 AM UTC), manual dispatch  
**Purpose**: Deep analysis and cross-platform testing  
**Duration**: ~25-35 minutes

**Comprehensive Testing:**
- **🌙 Full Matrix** - Ubuntu/macOS/Windows × Ruby 3.2/3.3/3.4/head
- **🧠 Memory Analysis** - Memory profiling, leak detection, GC stress testing
- **🔒 Security Scan** - Bundle audit, Brakeman security analysis
- **📊 Coverage Analysis** - Complete test coverage reporting
- **📈 Nightly Summary** - Comprehensive health report generation

## 🚀 Fail-Fast Strategy

Tests are strategically ordered by:
1. **Speed** - Fastest feedback first (lint → unit → integration)
2. **Criticality** - Most essential functionality first
3. **Dependencies** - External dependencies tested later
4. **Resource Usage** - Intensive tests last

**Special Handling:**
- Performance and Cost tests use `continue-on-error` to prevent flaky failures from blocking deployments
- Matrix builds use `fail-fast: true` for immediate failure detection
- Critical path jobs block subsequent stages until they pass
- Each stage depends on previous stage success (except parallel branches)

## 📋 Test Categories

| Category | Count | Description | Examples |
|----------|-------|-------------|----------|
| **Unit Tests** | 57 files | Core functionality without external deps | Agent behavior, Runner execution, Context management |
| **Integration Tests** | 9 files | External system integration | Provider communication, API interactions |
| **Compliance Tests** | 4 files | Standards and compatibility | Python SDK parity, OpenAI compatibility |
| **Edge Cases** | 3 files | Boundary and regression testing | Corner cases, bug regressions |
| **Performance Tests** | 5 files | Resource usage and scalability | Load testing, memory profiling |
| **Cost Tests** | 2 files | Financial optimization | Model efficiency, token budgets |
| **Acceptance Tests** | 2 files | End-to-end scenarios | Multi-agent workflows |

## 🎯 Workflow Selection Guide

| Situation | Workflow | Why |
|-----------|----------|-----|
| Feature development | `core-quick-check.yml` | Fast feedback loop |
| PR to main/develop | `core-ci.yml` | Full quality gate |
| Production readiness | `core-nightly.yml` | Comprehensive validation |
| Security audit | `core-nightly.yml` | Complete security scan |
| Performance regression | `core-nightly.yml` | Memory and performance analysis |

## 🔧 Usage Examples

### Running Tests Locally
```bash
# Quick check equivalent (unit tests only)
bundle exec rspec --exclude-pattern "spec/{acceptance,compliance,cost,edge_cases,integration,performance}/**/*_spec.rb"

# Models and providers only
bundle exec rspec spec/models/

# With integration tests
RUN_INTEGRATION_TESTS=true bundle exec rspec spec/integration/

# Full test suite (nightly equivalent)
RUN_INTEGRATION_TESTS=true RUN_PERFORMANCE_TESTS=true RUN_COST_TESTS=true RUN_ACCEPTANCE_TESTS=true bundle exec rspec

# Specific test categories
bundle exec rspec spec/compliance/      # Compliance tests
bundle exec rspec spec/edge_cases/      # Edge cases
bundle exec rspec spec/performance/     # Performance tests (requires RUN_PERFORMANCE_TESTS=true)
```

### Triggering Workflows
```bash
# Quick check - push to feature branch
git push origin feature/my-feature

# Full CI - push to main branch  
git push origin main

# Force full CI on any branch
git commit --allow-empty -m "trigger CI"
git push

# Manual nightly run
# Use GitHub UI "Run workflow" button on core-nightly.yml
```

## 📊 Artifacts and Reporting

Each workflow generates comprehensive artifacts:

### Test Results
- **JUnit XML** files for GitHub integration and test result visualization
- **Test timing data** for performance optimization
- **Failure details** with full stack traces

### Coverage Reports (Nightly Only)
- **Line coverage** with SimpleCov integration
- **Branch coverage** analysis
- **Coverage trends** over time

### Security Reports (Nightly Only)
- **Dependency vulnerabilities** (bundle audit)
- **Security issues** (Brakeman analysis)
- **License compliance** reports

### Performance Data (Nightly Only)
- **Memory profiling** with allocation tracking
- **Garbage collection** stress test results
- **CPU profiling** for bottleneck identification
- **Object space analysis** for leak detection

## 🎛️ Configuration

### Environment Variables
```bash
# Test execution control
RUN_INTEGRATION_TESTS=true    # Enable integration tests
RUN_PERFORMANCE_TESTS=true    # Enable performance tests  
RUN_COST_TESTS=true          # Enable cost analysis tests
RUN_ACCEPTANCE_TESTS=true    # Enable acceptance tests

# Coverage reporting
COVERAGE=true                # Enable coverage collection

# Debugging
RAAF_LOG_LEVEL=debug        # Detailed logging
RAAF_DEBUG_CATEGORIES=api   # Category-specific debug
```

### Required Secrets
```bash
# API keys for testing (recommended but optional)
OPENAI_API_KEY_TEST      # OpenAI API for integration tests
ANTHROPIC_API_KEY_TEST   # Anthropic API for multi-provider tests  
GEMINI_API_KEY_TEST      # Google Gemini API for provider tests
```

## 📈 Performance Characteristics

| Workflow | Jobs | Duration | Parallelism | Failure Impact |
|----------|------|----------|-------------|----------------|
| **Quick Check** | 3 | 2-3 min | Limited | Blocks PR merge |
| **Main CI** | 11 | 8-12 min | High | Blocks deployment |
| **Nightly** | 4 | 25-35 min | Cross-platform | Notification only |

### Resource Usage
- **CPU**: Optimized with parallel execution and strategic job dependencies
- **Memory**: Memory-intensive tests isolated to nightly workflow
- **Network**: VCR cassettes minimize external API calls
- **Storage**: Artifacts retained for 7-30 days based on importance

## 🛠️ Maintenance and Customization

### Adding New Test Categories
1. Create new directory under `spec/` (e.g., `spec/my_category/`)
2. Add category detection in `spec/spec_helper.rb`:
   ```ruby
   config.define_derived_metadata(file_path: %r{/spec/my_category/}) do |metadata|
     metadata[:type] = :my_category
     metadata[:my_category] = true
   end
   ```
3. Add new job in `core-ci.yml` following the existing pattern:
   ```yaml
   my-category-tests:
     name: "🔧 My Category Tests"
     runs-on: ubuntu-latest
     needs: previous-stage
   ```
4. Update this README documentation

### Extending to Other Gems
1. Copy `core-ci.yml` as `{gem-name}-ci.yml`
2. Update all path references from `core/` to `{gem-name}/`
3. Update gem name in build commands
4. Adjust test categories based on gem's specific needs
5. Update trigger paths to match gem directory

### Performance Optimization
- **Caching**: Uses `bundler-cache: true` for dependency caching
- **Parallelism**: Strategic use of `needs:` for job dependencies
- **Early termination**: `fail-fast: true` in matrices
- **Resource allocation**: Memory-intensive tasks in nightly only

## 🚨 Troubleshooting

### Common Issues

1. **Test Timeouts**:
   ```bash
   # Increase timeout for slow tests
   bundle exec rspec --default-timeout 60
   ```

2. **Memory Issues**:
   ```bash
   # Skip memory-intensive tests locally
   bundle exec rspec --exclude-pattern "spec/performance/**/*_spec.rb"
   ```

3. **API Rate Limits**:
   - VCR cassettes prevent most external calls
   - Use test API keys with higher limits if needed

4. **Flaky Tests**:
   - Performance and cost tests use `continue-on-error`
   - Check nightly runs for persistent issues

### Debugging Workflows
1. Check **Actions tab** for detailed execution logs
2. Download **artifacts** for test results and reports  
3. Use **GitHub Step Summary** for high-level status
4. Enable **debug logging** with `RAAF_LOG_LEVEL=debug`

### Getting Help
- **Workflow issues**: Check Actions tab logs and workflow YAML syntax
- **Test failures**: Review test output and run locally with same environment
- **Performance issues**: Check nightly memory analysis reports
- **Security alerts**: Review security scan artifacts and bundle audit output

---

## 📊 Status Summary

| Component | Status | Coverage | Last Updated |
|-----------|--------|----------|--------------|
| Core CI Pipeline | ✅ Active | 95%+ | Current |
| Quick Check | ✅ Active | Essential tests | Current |
| Nightly Analysis | ✅ Active | 100% comprehensive | Current |
| Legacy Workflows | 🚫 Disabled | N/A | Replaced |

*Generated for RAAF Core v1.0 - Enterprise-grade AI agent framework with comprehensive CI/CD*