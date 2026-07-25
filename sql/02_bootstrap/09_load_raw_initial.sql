-- ============================================================
-- Carga inicial e reproduzível do CSV para a camada RAW.
-- ============================================================

BEGIN;

TRUNCATE TABLE raw.credit_applications;

COPY raw.credit_applications (
    application_id,
    customer_id,
    application_date,
    uf,
    channel,
    age,
    gender,
    education,
    employment_type,
    months_employed,
    monthly_income,
    bank_relationship_months,
    marital_status,
    dependents,
    housing_status,
    credit_history_months,
    previous_loans,
    previous_defaults,
    bureau_inquiries_90d,
    open_credit_lines,
    credit_utilization,
    delinquency_12m,
    avg_payment_delay_days,
    monthly_existing_debt,
    requested_amount,
    loan_purpose,
    term_months,
    estimated_installment,
    debt_to_income,
    digital_behavior_score,
    device_age_months,
    email_age_months,
    phone_verified,
    document_consistency,
    ip_risk_score,
    credit_score_internal,
    risk_band,
    approved,
    approved_amount,
    interest_rate_monthly,
    default_90d,
    fraud_confirmed
)
FROM 'C:\Users\rufin\OneDrive\projetos_portifolio\smart_credit_analytics\data\raw\fintech_credit_risk_dataset.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    DELIMITER ',',
    ENCODING 'UTF8'
);

-- Como source_file e ingested_at não fazem parte do CSV, os valores
-- são preenchidos pelos DEFAULTS definidos na tabela RAW.

UPDATE governance.etl_batch_control
SET raw_rows = (SELECT COUNT(*) FROM raw.credit_applications)
WHERE batch_id = (
    SELECT batch_id
    FROM governance.etl_batch_control
    WHERE pipeline_name = 'credit_bootstrap_initial_load'
      AND status = 'running'
    ORDER BY started_at DESC
    LIMIT 1
);

-- Controle mínimo antes do COMMIT.
DO $$
DECLARE
    v_total BIGINT;
    v_distinct BIGINT;
BEGIN
    SELECT COUNT(*), COUNT(DISTINCT application_id)
      INTO v_total, v_distinct
    FROM raw.credit_applications;

    IF v_total = 0 THEN
        RAISE EXCEPTION 'A carga RAW terminou sem registros.';
    END IF;

    IF v_total <> v_distinct THEN
        RAISE EXCEPTION
            'A RAW possui application_id duplicado: total=%, distintos=%',
            v_total,
            v_distinct;
    END IF;
END;
$$;

COMMIT;

SELECT
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT application_id) AS distinct_applications,
    MIN(application_date) AS min_application_date,
    MAX(application_date) AS max_application_date,
    MIN(ingested_at) AS first_ingested_at,
    MAX(ingested_at) AS last_ingested_at
FROM raw.credit_applications;