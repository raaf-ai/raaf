# RAAF GitHub Actions Workflows Guide

This file documents the GitHub Actions setup for the RAAF monorepo, currently focused on the core gem with comprehensive testing strategy.

## ACTIVE WORKFLOWS

### 1. 🚀 core-ci.yml - Complete Test Suite (main/develop branches + PRs)
#    Triggers: Push to main/develop, PRs to main/develop on core/** changes
#    - 🔍 Lint & Style (Stage 1 - fastest feedback, skips drafts)
#    - 🧪 Unit Tests (Stage 2 - Ruby 3.2/3.3/3.4.5 matrix)
#    - 📝 Example Validation (Stage 3 - parallel)
#    - 🔗 Integration Tests (Stage 3 - parallel)
#    - 📋 Compliance Tests (Stage 3 - parallel)
#    - ⚡ Performance Tests (Stage 3 - parallel, continue-on-error)
#    - 💰 Cost Analysis Tests (Stage 3 - parallel, continue-on-error)
#    - ✅ Acceptance Tests (Stage 4 - validates all previous tests)
#    - 📦 Build Gem (Stage 5 - after acceptance tests)
#    - 📊 Test Summary & Coverage Check (Final reporting + PR comments)
# 
**Triggers:** Push to main/develop, PRs to main/develop on core/** changes

**Stages:**
- 🔍 Lint & Style (Stage 1 - fastest feedback, skips drafts)
- 🧪 Unit Tests (Stage 2 - Ruby 3.2/3.3/3.4.5 matrix)
- 📝 Example Validation (Stage 3 - parallel)
- 🔗 Integration Tests (Stage 3 - parallel)
- 📋 Compliance Tests (Stage 3 - parallel)
- ⚡ Performance Tests (Stage 3 - parallel, continue-on-error)
- 💰 Cost Analysis Tests (Stage 3 - parallel, continue-on-error)
- ✅ Acceptance Tests (Stage 4 - validates all previous tests)
- 📦 Build Gem (Stage 5 - after acceptance tests)
- 📊 Test Summary & Coverage Check (Final reporting + PR comments)

### 2. ⚡ core-quick-check.yml - Fast Development Feedback (feature branches)

**Triggers:** Push to feature/*, fix/*, hotfix/* branches on core/** changes

**Stages:**
- ⚡ Quick Lint (parallel RuboCop, skips drafts)
- 🧪 Essential Tests (core specs only: agent, runner, models)
- 💨 Smoke Test (gem build + basic loading test)
- ✓ Quick Check Status (summary for developers)

### 3. 🌙 core-nightly.yml - Comprehensive Health Check (scheduled)

**Triggers:** Daily at 2 AM UTC + manual dispatch

**Stages:**
- 🌙 Comprehensive Matrix (Ubuntu/macOS/Windows × Ruby 3.2/3.3/3.4.5/head)
- 🧠 Memory Analysis (profiling, leak detection, GC stress testing)
- 🔒 Security Scan (bundle audit, Brakeman)
- 📊 Coverage Analysis (full test coverage reporting)
- 📈 Nightly Summary (comprehensive health report)

### 4. 📚 guides-build-deploy.yml - Documentation Build & Deploy

**Triggers:** Push/PR to main/develop with guides/** changes + manual dispatch

**Stages:**
- 🔍 Validate Guides (markdown linting, code validation)
- 🏗️ Build Guides (generate HTML, check links, validate HTML)
- ⚙️ Setup Pages (GitHub Pages configuration)
- 🚀 Deploy to Pages (deploy to https://raaf-ai.github.io/raaf/)
- 📊 Build Summary (comprehensive build reporting)

## FAIL-FAST STRATEGY

Tests are ordered by:
1. **Speed** (fastest first for immediate feedback)
2. **Criticality** (most essential functionality first)
3. **Dependencies** (external dependencies later)
4. **Resource usage** (intensive tests last)

Performance and Cost tests use `continue-on-error` to prevent flaky failures from blocking deployments while still providing feedback.

## DISABLED LEGACY WORKFLOWS

The following workflows were removed (focusing on core gem only):
- `ci.yml` (replaced by core-ci.yml)
- `docs.yml` (replaced by guides-build-deploy.yml)
- `performance.yml` (integrated into core-ci.yml)  
- `security.yml` (integrated into core-nightly.yml)
- `release.yml` (legacy gem structure)

## WORKFLOW STRATEGY & BEST PRACTICES

### Trigger Strategy
- **core-ci.yml**: Full CI for main branches and PRs (comprehensive testing)
- **core-quick-check.yml**: Fast feedback for feature branches (development speed)
- **core-nightly.yml**: Deep health checks for maintenance (comprehensive monitoring)
- **guides-build-deploy.yml**: Documentation builds and GitHub Pages deployment

### Performance Optimizations
- Parallel execution where possible (lint + tests, parallel test categories)
- Caching with `ruby/setup-ruby@v1` bundler-cache
- Artifact retention: 7-30 days based on importance
- `continue-on-error` for flaky but informative tests (performance, cost)

### Environment Standards
- `RUBY_VERSION: '3.4.5'` (primary development version)
- `DEFAULT_RUBY_VERSION: '3.4.5'` (fallback for consistency)
- Test secrets: `*_API_KEY_TEST` (separate from production)

## FUTURE GEM WORKFLOWS

When other gems need CI/CD, create workflows based on `core-ci.yml` template:
- `tracing-ci.yml`, `memory-ci.yml`, `tools-ci.yml`, `guardrails-ci.yml`
- `providers-ci.yml`, `dsl-ci.yml`, `rails-ci.yml`, `streaming-ci.yml`

### Template Creation Steps
1. Copy `core-ci.yml` structure and rename appropriately
2. Update trigger paths: `'core/**'` → `'TARGET_GEM/**'`
3. Update working directory: `'cd core'` → `'cd TARGET_GEM'`
4. Update gem name in build commands: `'raaf-core'` → `'raaf-TARGET_GEM'`
5. Adjust test categories and stages based on gem's specific needs
6. Update artifact names to avoid conflicts: `'core-*'` → `'TARGET_GEM-*'`