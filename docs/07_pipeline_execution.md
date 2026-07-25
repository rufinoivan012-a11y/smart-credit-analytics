# Pipeline Execution

## 1. Purpose

This document defines the execution sequence, dependencies, validation gates, current bootstrap status, and operational notes for the **Smart Credit Analytics Platform**.

The current version was executed locally in PostgreSQL through pgAdmin and represents the historical analytical bootstrap.

## 2. Repository Structure

```text
sql/
├── 00_setup/
│   ├── 00_create_database.sql
│   ├── 01_create_schemas.sql
│   ├── 02_create_extensions.sql
│   └── 03_create_governance_tables.sql
│
├── 01_ddl/
│   ├── 04_create_raw_tables.sql
│   ├── 05_create_staging_functions.sql
│   ├── 06_create_staging_tables.sql
│   └── 07_create_trusted_tables.sql
│
├── 02_bootstrap/
│   ├── 08_start_initial_batch.sql
│   ├── 09_load_raw_initial.sql
│   ├── 10_load_staging_full_refresh.sql
│   ├── 12_load_dim_date.sql
│   ├── 13_load_dimensions_initial.sql
│   ├── 14_load_fact_initial.sql
│   └── 16_complete_initial_batch.sql
│
├── 03_incremental/
│   ├── 20_start_batch.sql
│   ├── 21_ingest_raw_incremental.sql
│   ├── 22_load_staging_incremental.sql
│   ├── 23_merge_dimensions.sql
│   ├── 24_merge_fact.sql
│   ├── 26_validate_batch.sql
│   └── 27_complete_batch.sql
│
├── 04_analytics/
│   └── 17_create_analytics_marts.sql
│
└── 05_validation/
    ├── 11_validate_staging.sql
    ├── 15_validate_trusted.sql
    ├── 18_validate_analytics.sql
    └── 26_validate_batch.sql
```

`25_refresh_analytics.sql` is not required while Analytics objects are standard views. It would only be required for materialized views.

## 3. Full Bootstrap Execution Order

For a clean rebuild:

```text
00_create_database.sql
01_create_schemas.sql
02_create_extensions.sql
03_create_governance_tables.sql
04_create_raw_tables.sql
05_create_staging_functions.sql
06_create_staging_tables.sql
07_create_trusted_tables.sql
08_start_initial_batch.sql
09_load_raw_initial.sql
10_load_staging_full_refresh.sql
11_validate_staging.sql
12_load_dim_date.sql
13_load_dimensions_initial.sql
14_load_fact_initial.sql
15_validate_trusted.sql
16_complete_initial_batch.sql
17_create_analytics_marts.sql
18_validate_analytics.sql
```

The numbering represents the global sequence even when validation scripts are stored in another folder.

## 4. Current Execution Status

| Area | Status |
|---|---|
| Database and schemas | Completed |
| RAW table | Completed |
| Initial CSV ingestion | Completed |
| Staging functions | Completed |
| Staging tables | Completed |
| Full-refresh staging load | Completed |
| Staging validation | Approved |
| Trusted dimensions | Completed |
| Trusted fact | Completed |
| Trusted validation | Approved |
| Analytics views | Completed |
| Analytics validation | Approved |
| Formal bootstrap batch registration | Not applied retroactively |
| Incremental pipeline | Not implemented yet |

## 5. First Bootstrap Exception

The first historical load was executed before formal batch governance was added.

Therefore, in the current database state:

```text
08_start_initial_batch.sql    → not executed retroactively
09_load_raw_initial.sql       → not rerun after the manual RAW load
16_complete_initial_batch.sql → not executed without an open batch
```

This avoids creating inaccurate governance timestamps after the real execution.

Recommended statement:

> The first historical bootstrap was completed before formal batch-control implementation. RAW, STAGING, TRUSTED, and ANALYTICS layers were validated with 8,000 records. Formal `batch_id` governance applies to future rebuilds and incremental executions.

## 6. Script Responsibilities

### 6.1 Setup and DDL

| Script | Responsibility |
|---|---|
| `00_create_database.sql` | Create `smart_credit_analytics` |
| `01_create_schemas.sql` | Create all data schemas |
| `02_create_extensions.sql` | Enable required PostgreSQL extensions |
| `03_create_governance_tables.sql` | Create or safely update governance structures |
| `04_create_raw_tables.sql` | Create the RAW landing table |
| `05_create_staging_functions.sql` | Create safe conversion functions |
| `06_create_staging_tables.sql` | Create valid and rejected staging tables |
| `07_create_trusted_tables.sql` | Create dimensions, fact, keys, and relationships |

### 6.2 Bootstrap

| Script | Responsibility |
|---|---|
| `08_start_initial_batch.sql` | Open a governed bootstrap batch |
| `09_load_raw_initial.sql` | Truncate and reload RAW during a clean rebuild |
| `10_load_staging_full_refresh.sql` | Normalize, validate, reject, and load staging |
| `12_load_dim_date.sql` | Populate the date dimension |
| `13_load_dimensions_initial.sql` | Populate all other dimensions |
| `14_load_fact_initial.sql` | Resolve surrogate keys and populate the fact |
| `16_complete_initial_batch.sql` | Close the bootstrap batch after validation |

### 6.3 Validation

| Script | Validation gate |
|---|---|
| `11_validate_staging.sql` | RAW-to-staging reconciliation and rule validation |
| `15_validate_trusted.sql` | Fact grain, foreign keys, mapping, and financial consistency |
| `18_validate_analytics.sql` | View existence, row counts, KPI reconciliation, and leakage checks |

### 6.4 Analytics

| Script | Responsibility |
|---|---|
| `17_create_analytics_marts.sql` | Create the five Analytics views |

## 7. Validated Results

### 7.1 Staging

```text
RAW rows      = 8,000
Valid rows    = 8,000
Rejected rows = 0
```

### 7.2 Trusted

| Object | Rows |
|---|---:|
| `trusted.dim_customer` | 8,000 |
| `trusted.dim_location` | 15 |
| `trusted.dim_acquisition_channel` | 5 |
| `trusted.dim_credit_profile_snapshot` | 8,000 |
| `trusted.dim_digital_risk_profile` | 7,999 |
| `trusted.fact_credit_applications` | 8,000 |

Validation results:

```text
fact duplicates = 0
orphan keys = 0
null dimension keys = 0
financial inconsistencies = 0
```

### 7.3 Analytics

Validated objects:

```text
analytics.vw_credit_application_360
analytics.vw_credit_kpis_daily
analytics.vw_credit_risk_analysis
analytics.vw_fraud_monitoring
analytics.vw_model_training_dataset
```

Validation results:

```text
views created = 5
360 rows = 8,000
distinct applications = 8,000
duplicates = 0
financial reconciliation differences = 0
valid risk bands = 5
```

## 8. Validation Gates

### Gate 1 — Staging

```text
raw_rows = valid_rows + rejected_rows
duplicate valid application_id = 0
critical invalid values = 0 in valid staging
```

### Gate 2 — Trusted

```text
staging_rows = fact_rows
fact_rows = distinct application_ids
orphan foreign keys = 0
date mismatches = 0
financial inconsistencies = 0
```

### Gate 3 — Analytics

```text
all expected views exist
fact_rows = 360_view_rows
KPI differences = 0
risk-band domain is valid
training dataset grain is preserved
forbidden post-decision feature columns = 0
```

## 9. Idempotency and Re-execution

The current bootstrap uses full refresh for staging and initial trusted loads.

Expected behavior:

```text
First execution  → 8,000 records
Second execution → 8,000 records
```

It must not produce 16,000 records.

If PostgreSQL returns `SQLSTATE 25P02`, execute:

```sql
ROLLBACK;
```

Then identify and correct the first error before re-executing the script.

During a bootstrap rebuild, the fact and referenced dimensions must be truncated in the same statement because of foreign-key dependencies.

## 10. Operational Notes

### 10.1 Script 09

`09_load_raw_initial.sql` must only be executed during a clean rebuild because it reloads RAW.

The path inside `COPY` must be changed for the local environment, and the PostgreSQL server process must have permission to read the directory.

### 10.2 Analytics refresh

The current Analytics objects are standard views and automatically reflect Trusted data. No explicit refresh is required.

### 10.3 Near-real-time scope

The analytical pipeline does not sit directly in the synchronous credit-decision response path.

Target flow:

```text
Client request
  ↓
FastAPI validation, business rules, and models
  ↓
Immediate credit decision
  ↓
Operational persistence
  ↓
Asynchronous analytical ingestion
```

## 11. Planned Incremental Execution

Expected sequence:

```text
19_create_incremental_support_objects.sql
20_start_batch.sql
21_ingest_raw_incremental.sql
22_load_staging_incremental.sql
23_merge_dimensions.sql
24_merge_fact.sql
26_validate_batch.sql
27_complete_batch.sql
```

Planned behavior:

```text
new application_id                  → INSERT
existing application_id, changed   → UPDATE
existing application_id, unchanged → DO NOTHING
```

Planned controls:

- `batch_id`;
- `record_hash`;
- append-only RAW;
- incremental staging;
- `MERGE` or `UPSERT`;
- late-arriving default and fraud outcomes;
- batch-level reconciliation;
- success or failure status in governance.

