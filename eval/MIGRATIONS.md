# RAAF Eval Database Migration Guide

> Version: 1.0.0
> Last Updated: 2025-11-07
> Database: PostgreSQL 12+

## Overview

This guide covers database setup, migrations, and maintenance for RAAF Eval. The system uses PostgreSQL with JSONB columns and GIN indexes for efficient evaluation storage and querying.

## Quick Start

```bash
# Run all migrations
cd eval
bundle exec rake db:migrate

# Check migration status
bundle exec rake db:migrate:status

# Rollback last migration
bundle exec rake db:rollback

# Rollback specific migration
bundle exec rake db:migrate:down VERSION=20251106000001
```

## Prerequisites

### PostgreSQL Version

**Minimum**: PostgreSQL 12
**Recommended**: PostgreSQL 14+

**Why**: JSONB support, GIN index improvements, better performance

```bash
# Check PostgreSQL version
psql --version

# Or in psql
SELECT version();
```

### Required Extensions

```sql
-- Enable extensions (as superuser)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- For UUID generation
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- For fuzzy text search (optional)
```

## Database Configuration

### Development Setup

```ruby
# config/database.yml (Rails)
development:
  adapter: postgresql
  database: raaf_eval_development
  username: <%= ENV['DATABASE_USERNAME'] || 'postgres' %>
  password: <%= ENV['DATABASE_PASSWORD'] || 'password' %>
  host: <%= ENV['DATABASE_HOST'] || 'localhost' %>
  port: <%= ENV['DATABASE_PORT'] || 5432 %>
  pool: <%= ENV['DATABASE_POOL'] || 5 %>
  timeout: 5000

test:
  adapter: postgresql
  database: raaf_eval_test
  username: <%= ENV['DATABASE_USERNAME'] || 'postgres' %>
  password: <%= ENV['DATABASE_PASSWORD'] || 'password' %>
  host: <%= ENV['DATABASE_HOST'] || 'localhost' %>
  port: <%= ENV['DATABASE_PORT'] || 5432 %>
  pool: 5
  timeout: 5000

production:
  adapter: postgresql
  url: <%= ENV['DATABASE_URL'] %>
  pool: <%= ENV['DATABASE_POOL'] || 10 %>
  timeout: 5000
```

### Environment Variables

```bash
export DATABASE_URL="postgresql://user:password@host:port/database"
export DATABASE_POOL=10              # Connection pool size
export DATABASE_USERNAME=postgres
export DATABASE_PASSWORD=secret
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
```

## Migration Files

### Migration 001: Create Evaluation Tables

**File**: `db/migrate/20251106000001_create_evaluation_tables.rb`

**Tables Created**:
1. evaluation_runs
2. evaluation_spans
3. evaluation_configurations
4. evaluation_results

**Indexes Created**:
- B-tree indexes: IDs, timestamps, foreign keys
- GIN indexes: JSONB columns
- Composite indexes: Common query patterns

**Run**:
```bash
bundle exec rake db:migrate VERSION=20251106000001
```

**Rollback**:
```bash
bundle exec rake db:rollback STEP=1
```

## Schema Details

### evaluation_runs

Stores top-level evaluation execution records.

```sql
CREATE TABLE evaluation_runs (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT,
  status VARCHAR NOT NULL DEFAULT 'pending',
  baseline_span_id VARCHAR NOT NULL,
  initiated_by VARCHAR,
  metadata JSONB DEFAULT '{}',
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE INDEX index_evaluation_runs_on_name ON evaluation_runs(name);
CREATE INDEX index_evaluation_runs_on_status ON evaluation_runs(status);
CREATE INDEX index_evaluation_runs_on_created_at ON evaluation_runs(created_at);
CREATE INDEX index_evaluation_runs_on_baseline_span_id ON evaluation_runs(baseline_span_id);
CREATE INDEX index_evaluation_runs_on_metadata ON evaluation_runs USING gin(metadata);
```

**Status Values**: `pending`, `running`, `completed`, `failed`, `cancelled`

### evaluation_spans

Stores complete serialized span snapshots.

```sql
CREATE TABLE evaluation_spans (
  id BIGSERIAL PRIMARY KEY,
  span_id VARCHAR NOT NULL,
  trace_id VARCHAR NOT NULL,
  parent_span_id VARCHAR,
  span_type VARCHAR NOT NULL,
  span_data JSONB NOT NULL,
  source VARCHAR NOT NULL,
  evaluation_run_id BIGINT REFERENCES evaluation_runs(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX index_evaluation_spans_on_span_id ON evaluation_spans(span_id);
CREATE INDEX index_evaluation_spans_on_trace_id ON evaluation_spans(trace_id);
CREATE INDEX index_evaluation_spans_on_parent_span_id ON evaluation_spans(parent_span_id);
CREATE INDEX index_evaluation_spans_on_span_type ON evaluation_spans(span_type);
CREATE INDEX index_evaluation_spans_on_span_data ON evaluation_spans USING gin(span_data);
CREATE INDEX index_evaluation_spans_on_trace_parent ON evaluation_spans(trace_id, parent_span_id);
```

**Span Types**: `agent`, `response`, `tool`, `handoff`
**Source Values**: `production_trace`, `evaluation_run`, `manual_upload`

### evaluation_configurations

Stores configuration variants for evaluation.

```sql
CREATE TABLE evaluation_configurations (
  id BIGSERIAL PRIMARY KEY,
  evaluation_run_id BIGINT NOT NULL REFERENCES evaluation_runs(id),
  name VARCHAR NOT NULL,
  configuration_type VARCHAR NOT NULL,
  changes JSONB NOT NULL,
  execution_order INTEGER DEFAULT 0,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE INDEX index_eval_configs_on_run_order ON evaluation_configurations(evaluation_run_id, execution_order);
CREATE INDEX index_eval_configs_on_type ON evaluation_configurations(configuration_type);
CREATE INDEX index_eval_configs_on_changes ON evaluation_configurations USING gin(changes);
```

**Configuration Types**: `model_change`, `parameter_change`, `prompt_change`, `provider_change`, `combined`

### evaluation_results

Stores evaluation results with comprehensive metrics.

```sql
CREATE TABLE evaluation_results (
  id BIGSERIAL PRIMARY KEY,
  evaluation_run_id BIGINT NOT NULL REFERENCES evaluation_runs(id),
  evaluation_configuration_id BIGINT NOT NULL REFERENCES evaluation_configurations(id),
  result_span_id VARCHAR NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'pending',

  -- Metric columns (JSONB)
  token_metrics JSONB DEFAULT '{}',
  latency_metrics JSONB DEFAULT '{}',
  accuracy_metrics JSONB DEFAULT '{}',
  structural_metrics JSONB DEFAULT '{}',
  ai_comparison JSONB DEFAULT '{}',
  ai_comparison_status VARCHAR,
  statistical_analysis JSONB DEFAULT '{}',
  custom_metrics JSONB DEFAULT '{}',
  baseline_comparison JSONB DEFAULT '{}',

  -- Error tracking
  error_message TEXT,
  error_backtrace TEXT,

  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE INDEX index_evaluation_results_on_status ON evaluation_results(status);
CREATE INDEX index_evaluation_results_on_result_span_id ON evaluation_results(result_span_id);
CREATE INDEX index_evaluation_results_on_run_status ON evaluation_results(evaluation_run_id, status);
CREATE INDEX index_evaluation_results_on_token_metrics ON evaluation_results USING gin(token_metrics);
CREATE INDEX index_evaluation_results_on_ai_comparison ON evaluation_results USING gin(ai_comparison);
CREATE INDEX index_evaluation_results_on_baseline_comparison ON evaluation_results USING gin(baseline_comparison);
```

**Status Values**: `pending`, `running`, `completed`, `failed`
**AI Comparison Status**: `pending`, `completed`, `failed`, `skipped`

## Index Maintenance

### Verify Index Usage

```sql
-- Check if GIN indexes are being used
EXPLAIN ANALYZE
SELECT * FROM evaluation_spans
WHERE span_data @> '{"metadata": {"model": "gpt-4o"}}'::jsonb;

-- Expected output should show:
-- "Bitmap Index Scan using index_evaluation_spans_on_span_data"
```

### Rebuild Indexes

```sql
-- Rebuild specific index
REINDEX INDEX index_evaluation_spans_on_span_data;

-- Rebuild all indexes for table
REINDEX TABLE evaluation_spans;

-- Rebuild all indexes in database (slow!)
REINDEX DATABASE raaf_eval_development;
```

### Monitor Index Size

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Database Maintenance

### Regular Maintenance Tasks

#### 1. VACUUM ANALYZE

**Frequency**: Daily (automated) or weekly (manual)

```sql
-- Vacuum all evaluation tables
VACUUM ANALYZE evaluation_runs;
VACUUM ANALYZE evaluation_spans;
VACUUM ANALYZE evaluation_configurations;
VACUUM ANALYZE evaluation_results;

-- Or vacuum entire database
VACUUM ANALYZE;
```

**Why**: Reclaims storage, updates statistics for query planner

#### 2. Update Statistics

**Frequency**: After large data imports

```sql
ANALYZE evaluation_spans;
ANALYZE evaluation_results;
```

#### 3. Clean Old Data

**Frequency**: Monthly

```ruby
# Archive evaluations older than 90 days
cutoff = 90.days.ago

# Move to archive table (create separately)
EvaluationRun.where("created_at < ?", cutoff).find_each do |run|
  # Export to archive
  # Then delete
  run.destroy
end
```

### Performance Tuning

#### PostgreSQL Configuration

```ini
# postgresql.conf recommendations for RAAF Eval

# Memory settings
shared_buffers = 256MB              # For JSONB performance
work_mem = 16MB                     # For complex queries
maintenance_work_mem = 128MB        # For VACUUM, index creation

# Query planner
random_page_cost = 1.1              # For SSD storage
effective_cache_size = 4GB          # Based on available RAM

# JSONB specific
gin_pending_list_limit = 4MB        # For GIN index performance

# Connections
max_connections = 100               # Based on pool size
```

#### Connection Pooling

**Use PgBouncer for large deployments**:

```ini
# pgbouncer.ini
[databases]
raaf_eval = host=localhost dbname=raaf_eval_production

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
```

## Backup and Recovery

### Backup Strategy

#### Daily Backups

```bash
# Full backup
pg_dump -h localhost -U postgres -d raaf_eval_production > backup_$(date +%Y%m%d).sql

# Compressed backup
pg_dump -h localhost -U postgres -d raaf_eval_production | gzip > backup_$(date +%Y%m%d).sql.gz

# Backup specific tables
pg_dump -h localhost -U postgres -d raaf_eval_production -t evaluation_runs -t evaluation_results > backup_partial.sql
```

#### Continuous Archiving (Production)

```bash
# Enable WAL archiving in postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'cp %p /backup/archive/%f'

# Create base backup
pg_basebackup -h localhost -U postgres -D /backup/base -Fp -Xs -P
```

### Recovery

#### Restore from Backup

```bash
# Drop existing database (careful!)
dropdb raaf_eval_production

# Create new database
createdb raaf_eval_production

# Restore from backup
psql -h localhost -U postgres -d raaf_eval_production < backup_20251107.sql
```

#### Point-in-Time Recovery

```bash
# Restore base backup
cp -r /backup/base/* /var/lib/postgresql/data/

# Configure recovery
echo "restore_command = 'cp /backup/archive/%f %p'" > /var/lib/postgresql/data/recovery.conf
echo "recovery_target_time = '2025-11-07 12:00:00'" >> /var/lib/postgresql/data/recovery.conf

# Start PostgreSQL - it will recover to target time
```

## Table Partitioning (For Large Deployments)

### When to Partition

- evaluation_results table > 1M rows
- Query performance degrading
- Backup/restore time excessive

### Partition by Month

```sql
-- Convert evaluation_results to partitioned table
-- (Requires PostgreSQL 10+)

-- 1. Rename existing table
ALTER TABLE evaluation_results RENAME TO evaluation_results_old;

-- 2. Create partitioned table
CREATE TABLE evaluation_results (
  -- Same columns as before
  id BIGSERIAL,
  evaluation_run_id BIGINT NOT NULL,
  -- ... other columns ...
  created_at TIMESTAMP NOT NULL,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- 3. Create partitions
CREATE TABLE evaluation_results_2025_01 PARTITION OF evaluation_results
FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE evaluation_results_2025_02 PARTITION OF evaluation_results
FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- 4. Copy data from old table
INSERT INTO evaluation_results SELECT * FROM evaluation_results_old;

-- 5. Drop old table
DROP TABLE evaluation_results_old;

-- 6. Automate partition creation
-- Use pg_partman extension or cron job
```

## Monitoring

### Key Metrics

```sql
-- Table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query statistics (requires pg_stat_statements)
SELECT
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
WHERE query LIKE '%evaluation_%'
ORDER BY total_time DESC
LIMIT 10;

-- Index usage
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS index_scans,
  idx_tup_read AS tuples_read,
  idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

## Troubleshooting

### Slow Queries

**Problem**: JSONB queries are slow

**Diagnosis**:
```sql
EXPLAIN ANALYZE
SELECT * FROM evaluation_spans
WHERE span_data @> '{"metadata": {"model": "gpt-4o"}}'::jsonb;
```

**Solution**: Ensure GIN index exists and is being used
```sql
-- Verify index exists
\d evaluation_spans

-- Recreate if missing
CREATE INDEX IF NOT EXISTS index_evaluation_spans_on_span_data
ON evaluation_spans USING gin(span_data);

-- Update statistics
ANALYZE evaluation_spans;
```

### Database Bloat

**Problem**: Database size growing despite deletions

**Diagnosis**:
```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
  n_dead_tup AS dead_tuples
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;
```

**Solution**: Run VACUUM
```sql
VACUUM FULL ANALYZE evaluation_results;
```

### Connection Pool Exhaustion

**Problem**: "Too many connections" error

**Diagnosis**:
```sql
SELECT COUNT(*) FROM pg_stat_activity;
SELECT max_connections FROM pg_settings WHERE name = 'max_connections';
```

**Solution**: Increase pool size or use PgBouncer
```bash
# In database.yml
pool: 20  # Increase from default 5
```

## Migration Checklist

- [ ] PostgreSQL 12+ installed
- [ ] Database created
- [ ] Extensions enabled (uuid-ossp, pg_trgm)
- [ ] Migrations run successfully
- [ ] Indexes verified with EXPLAIN ANALYZE
- [ ] Backup strategy configured
- [ ] Monitoring set up
- [ ] Maintenance tasks scheduled
- [ ] Connection pooling configured (if needed)
- [ ] Partitioning planned (for large deployments)

## References

- [PostgreSQL JSONB Documentation](https://www.postgresql.org/docs/current/datatype-json.html)
- [GIN Index Documentation](https://www.postgresql.org/docs/current/gin.html)
- [Database Schema](.agent-os/specs/2025-11-06-raaf-eval-foundation/sub-specs/database-schema.md)
- [Performance Guide](PERFORMANCE.md)
