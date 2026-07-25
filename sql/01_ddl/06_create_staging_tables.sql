CREATE TABLE IF NOT EXISTS staging.stg_credit_applications (
    staging_record_id BIGSERIAL PRIMARY KEY,
    application_id VARCHAR(30) NOT NULL,
    customer_id VARCHAR(30) NOT NULL,
    application_date DATE NOT NULL,
    uf CHAR(2),
    channel VARCHAR(50),
    age INT,
    gender VARCHAR(20),
    education VARCHAR(50),
    employment_type VARCHAR(50),
    months_employed INT,
    monthly_income DECIMAL(12,2),
    bank_relationship_months INT,
    marital_status VARCHAR(30),
    dependents INT,
    housing_status VARCHAR(50),
    credit_history_months INT,
    previous_loans INT,
    previous_defaults INT,
    bureau_inquiries_90d INT,
    open_credit_lines INT,
    credit_utilization DECIMAL(6,3),
    delinquency_12m INT,
    avg_payment_delay_days DECIMAL(12,2),
    monthly_existing_debt DECIMAL(12,2),
    requested_amount DECIMAL(12,2),
    loan_purpose VARCHAR(50),
    term_months INT,
    estimated_installment DECIMAL(12,2),
    debt_to_income DECIMAL(6,3),
    digital_behavior_score DECIMAL(5,2),
    device_age_months INT,
    email_age_months INT,
    phone_verified BOOLEAN,
    document_consistency BOOLEAN,
    ip_risk_score DECIMAL(5,2),
    credit_score_internal INT,
    risk_band CHAR(1),
    approved BOOLEAN,
    approved_amount DECIMAL(12,2),
    interest_rate_monthly DECIMAL(6,4),
    default_90d BOOLEAN,
    fraud_confirmed BOOLEAN,
    source_file TEXT NOT NULL,
    raw_ingested_at TIMESTAMP NOT NULL,
    staging_loaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_stg_credit_applications_application_id
    ON staging.stg_credit_applications (application_id);

CREATE INDEX IF NOT EXISTS ix_stg_credit_applications_source_file
    ON staging.stg_credit_applications (source_file);

CREATE TABLE IF NOT EXISTS staging.rejected_credit_applications (
    rejection_id BIGSERIAL PRIMARY KEY,
    application_id TEXT,
    customer_id TEXT,
    raw_record JSONB NOT NULL,
    rejection_reason TEXT NOT NULL,
    source_file TEXT,
    raw_ingested_at TIMESTAMP,
    rejected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_rejected_credit_applications_application_id
    ON staging.rejected_credit_applications (application_id);

CREATE INDEX IF NOT EXISTS ix_rejected_credit_applications_source_file
    ON staging.rejected_credit_applications (source_file);
