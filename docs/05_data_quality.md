# Data Quality Rules

## 1. Purpose

This document defines the data quality controls applied to the **Smart Credit Analytics Platform** from source ingestion through the `staging`, `trusted`, and `analytics` layers.

Current scope:

- 8,000 synthetic personal-loan applications
- 42 business columns
- application period from 2024-01-01 to 2026-04-30
- business key: `application_id`
- customer key: `customer_id`

## 2. Validated Flow

```text
CSV
  ↓
raw.credit_applications
  ↓
staging.stg_credit_applications
  ├── valid records
  └── staging.rejected_credit_applications
  ↓
trusted.dim_* + trusted.fact_credit_applications
  ↓
analytics.vw_*
```

The current implementation is a full-refresh bootstrap. Incremental processing will be introduced in a later version.

## 3. Quality Principles

### 3.1 Source preservation

The `raw` layer stores the 42 business fields as `TEXT` and adds:

- `source_file`
- `ingested_at`

No correction, deletion, standardization, or business filtering is applied in RAW.

### 3.2 Safe conversion

The pipeline uses:

```text
staging.try_integer(TEXT)
staging.try_numeric(TEXT)
staging.try_date(TEXT)
staging.try_boolean(TEXT)
```

Malformed values return `NULL` instead of aborting the entire load. Validation rules then determine whether the record is accepted or rejected.

### 3.3 Quarantine

Invalid records are written to `staging.rejected_credit_applications`.

The table preserves:

- `application_id`
- `customer_id`
- original row in `raw_record JSONB`
- `rejection_reason`
- `source_file`
- `raw_ingested_at`
- `rejected_at`

### 3.4 Reconciliation

Mandatory rule:

```text
raw_rows = valid_staging_rows + rejected_rows
```

Validated bootstrap result:

```text
8,000 = 8,000 + 0
```

## 4. Data Quality Dimensions

| Dimension | Objective |
|---|---|
| Completeness | Required fields must be populated |
| Validity | Values must comply with types, ranges, and domains |
| Uniqueness | Business identifiers must not be duplicated |
| Consistency | Related fields must follow logical and financial rules |
| Referential integrity | Fact foreign keys must map to dimensions |
| Traceability | Source and processing metadata must be preserved |
| Reconciliation | No record may be lost or multiplied between layers |

## 5. Staging Rules

### 5.1 Identification and lineage

| Rule ID | Field | Rule | Action |
|---|---|---|---|
| DQ-ID-001 | `application_id` | Required after trimming | Reject |
| DQ-ID-002 | `application_id` | Must be unique in the processed dataset | Reject duplicates |
| DQ-ID-003 | `customer_id` | Required after trimming | Reject |
| DQ-LIN-001 | `source_file` | Required | Reject |
| DQ-LIN-002 | `raw_ingested_at` | Required | Reject |

Rejection codes:

```text
missing_application_id
duplicate_application_id
missing_customer_id
missing_source_file
missing_raw_ingested_at
```

### 5.2 Date and customer attributes

| Field | Current rule |
|---|---|
| `application_date` | Must be convertible to `DATE` |
| `uf` | Two uppercase letters |
| `age` | Between 18 and 80 |
| `months_employed` | Greater than or equal to zero |
| `monthly_income` | Greater than zero |
| `bank_relationship_months` | Greater than or equal to zero |
| `dependents` | Greater than or equal to zero |
| `credit_history_months` | Greater than or equal to zero |

Standardization:

```text
uf               → UPPER(TRIM(value))
channel          → LOWER(TRIM(value))
education        → LOWER(TRIM(value))
employment_type  → LOWER(TRIM(value))
marital_status   → LOWER(TRIM(value))
housing_status   → LOWER(TRIM(value))
```

### 5.3 Credit profile

| Field | Current rule |
|---|---|
| `previous_loans` | Greater than or equal to zero |
| `previous_defaults` | Greater than or equal to zero and not greater than `previous_loans` |
| `bureau_inquiries_90d` | Greater than or equal to zero |
| `open_credit_lines` | Greater than or equal to zero |
| `credit_utilization` | Between 0 and 1 |
| `delinquency_12m` | Greater than or equal to zero |
| `avg_payment_delay_days` | Greater than or equal to zero |
| `monthly_existing_debt` | Greater than or equal to zero |
| `debt_to_income` | Between 0 and 2.5 |

### 5.4 Application and digital-risk fields

| Field | Current rule |
|---|---|
| `requested_amount` | Greater than zero |
| `term_months` | Greater than zero |
| `estimated_installment` | Greater than zero |
| `digital_behavior_score` | Between 0 and 100 |
| `device_age_months` | Greater than or equal to zero |
| `email_age_months` | Greater than or equal to zero |
| `phone_verified` | Must be convertible to Boolean |
| `document_consistency` | Must be convertible to Boolean |
| `ip_risk_score` | Between 0 and 100 |

### 5.5 Decision and outcomes

| Field | Current rule |
|---|---|
| `credit_score_internal` | Between 250 and 950 |
| `risk_band` | `A`, `B`, `C`, `D`, or `E` |
| `approved` | Must be convertible to Boolean |
| `approved_amount` | Greater than or equal to zero and not greater than `requested_amount` |
| Approved application | Must have `approved_amount > 0` |
| Rejected application | Must have `approved_amount = 0` |
| `interest_rate_monthly` | Between 0 and 1 |
| `default_90d` | Required in the historical dataset |
| `fraud_confirmed` | Required in the historical dataset |

> In the future near-real-time flow, `default_90d` and `fraud_confirmed` may initially be `NULL` because they are post-decision outcomes.

## 6. Trusted Layer Controls

Fact grain:

```text
One row = one credit application
```

Validated results:

```text
fact_rows = 8,000
distinct_application_ids = 8,000
duplicates = 0
orphan foreign keys = 0
null foreign keys = 0
financial inconsistencies = 0
```

Bootstrap cardinality:

| Object | Rows |
|---|---:|
| `trusted.dim_customer` | 8,000 |
| `trusted.dim_location` | 15 |
| `trusted.dim_acquisition_channel` | 5 |
| `trusted.dim_credit_profile_snapshot` | 8,000 |
| `trusted.dim_digital_risk_profile` | 7,999 |
| `trusted.fact_credit_applications` | 8,000 |

The credit and digital profile dimensions are high-cardinality snapshot dimensions. This design is accepted in the current version and should be reviewed before production adoption.

## 7. Analytics Layer Controls

Approved controls:

- five Analytics views exist;
- the 360 view contains 8,000 rows and 8,000 distinct applications;
- no duplicated `application_id`;
- no null values in critical fields;
- derived fields are consistent;
- KPI and financial reconciliations return zero difference;
- exactly five valid risk bands are present;
- fraud-monitoring aggregates reconcile;
- the model-training dataset preserves one row per application;
- post-decision leakage fields are excluded from model features.

## 8. Bootstrap Result

| Control | Result |
|---|---:|
| RAW rows | 8,000 |
| Valid staging rows | 8,000 |
| Rejected rows | 0 |
| Fact rows | 8,000 |
| Fact duplicates | 0 |
| Orphan foreign keys | 0 |
| Financial inconsistencies | 0 |
| Analytics views | 5 |
| Overall status | Approved |
