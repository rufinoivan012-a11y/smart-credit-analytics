BEGIN;

-- Full refresh idempotente da staging.
-- A camada RAW não é alterada.
TRUNCATE TABLE staging.stg_credit_applications RESTART IDENTITY;
TRUNCATE TABLE staging.rejected_credit_applications RESTART IDENTITY;

DROP TABLE IF EXISTS tmp_credit_stage;

CREATE TEMP TABLE tmp_credit_stage
ON COMMIT DROP
AS
WITH normalized AS (
    SELECT
        TO_JSONB(r) AS raw_record,
        NULLIF(BTRIM(r.application_id), '') AS application_id,
        NULLIF(BTRIM(r.customer_id), '') AS customer_id,
        staging.try_date(r.application_date) AS application_date,
        UPPER(NULLIF(BTRIM(r.uf), '')) AS uf,
        LOWER(NULLIF(BTRIM(r.channel), '')) AS channel,
        staging.try_integer(r.age) AS age,
        UPPER(NULLIF(BTRIM(r.gender), '')) AS gender,
        LOWER(NULLIF(BTRIM(r.education), '')) AS education,
        LOWER(NULLIF(BTRIM(r.employment_type), '')) AS employment_type,
        staging.try_integer(r.months_employed) AS months_employed,
        staging.try_numeric(r.monthly_income) AS monthly_income,
        staging.try_integer(r.bank_relationship_months) AS bank_relationship_months,
        LOWER(NULLIF(BTRIM(r.marital_status), '')) AS marital_status,
        staging.try_integer(r.dependents) AS dependents,
        LOWER(NULLIF(BTRIM(r.housing_status), '')) AS housing_status,
        staging.try_integer(r.credit_history_months) AS credit_history_months,
        staging.try_integer(r.previous_loans) AS previous_loans,
        staging.try_integer(r.previous_defaults) AS previous_defaults,
        staging.try_integer(r.bureau_inquiries_90d) AS bureau_inquiries_90d,
        staging.try_integer(r.open_credit_lines) AS open_credit_lines,
        staging.try_numeric(r.credit_utilization) AS credit_utilization,
        staging.try_integer(r.delinquency_12m) AS delinquency_12m,
        staging.try_numeric(r.avg_payment_delay_days) AS avg_payment_delay_days,
        staging.try_numeric(r.monthly_existing_debt) AS monthly_existing_debt,
        staging.try_numeric(r.requested_amount) AS requested_amount,
        LOWER(NULLIF(BTRIM(r.loan_purpose), '')) AS loan_purpose,
        staging.try_integer(r.term_months) AS term_months,
        staging.try_numeric(r.estimated_installment) AS estimated_installment,
        staging.try_numeric(r.debt_to_income) AS debt_to_income,
        staging.try_numeric(r.digital_behavior_score) AS digital_behavior_score,
        staging.try_integer(r.device_age_months) AS device_age_months,
        staging.try_integer(r.email_age_months) AS email_age_months,
        staging.try_boolean(r.phone_verified) AS phone_verified,
        staging.try_boolean(r.document_consistency) AS document_consistency,
        staging.try_numeric(r.ip_risk_score) AS ip_risk_score,
        staging.try_integer(r.credit_score_internal) AS credit_score_internal,
        UPPER(NULLIF(BTRIM(r.risk_band), '')) AS risk_band,
        staging.try_boolean(r.approved) AS approved,
        staging.try_numeric(r.approved_amount) AS approved_amount,
        staging.try_numeric(r.interest_rate_monthly) AS interest_rate_monthly,
        staging.try_boolean(r.default_90d) AS default_90d,
        staging.try_boolean(r.fraud_confirmed) AS fraud_confirmed,
        r.source_file,
        r.ingested_at AS raw_ingested_at,
        COUNT(*) OVER (
            PARTITION BY NULLIF(BTRIM(r.application_id), '')
        ) AS application_id_count
    FROM raw.credit_applications r
),
validated AS (
    SELECT
        n.*,
        ARRAY_REMOVE(
            ARRAY[
                CASE WHEN application_id IS NULL THEN 'missing_application_id' END,
                CASE WHEN application_id IS NOT NULL AND application_id_count > 1
                     THEN 'duplicate_application_id' END,
                CASE WHEN customer_id IS NULL THEN 'missing_customer_id' END,
                CASE WHEN source_file IS NULL THEN 'missing_source_file' END,
                CASE WHEN raw_ingested_at IS NULL THEN 'missing_raw_ingested_at' END,
                CASE WHEN application_date IS NULL THEN 'invalid_application_date' END,
                CASE WHEN uf IS NULL OR uf !~ '^[A-Z]{2}$' THEN 'invalid_uf' END,
                CASE WHEN channel IS NULL OR channel NOT IN
                    ('app_android', 'app_ios', 'web', 'parceiro', 'whatsapp')
                    THEN 'invalid_channel' END,
                CASE WHEN age IS NULL OR age NOT BETWEEN 18 AND 80 THEN 'invalid_age' END,
                CASE WHEN gender IS NULL OR gender NOT IN ('F', 'M', 'NA')
                    THEN 'invalid_gender' END,
                CASE WHEN education IS NULL OR education NOT IN
                    ('fundamental', 'medio', 'superior_incompleto', 'superior', 'pos_graduacao')
                    THEN 'invalid_education' END,
                CASE WHEN employment_type IS NULL OR employment_type NOT IN
                    ('clt', 'autonomo', 'mei', 'servidor_publico', 'desempregado', 'aposentado')
                    THEN 'invalid_employment_type' END,
                CASE WHEN months_employed IS NULL OR months_employed < 0
                    THEN 'invalid_months_employed' END,
                CASE WHEN monthly_income IS NULL OR monthly_income <= 0
                    THEN 'invalid_monthly_income' END,
                CASE WHEN bank_relationship_months IS NULL OR bank_relationship_months < 0
                    THEN 'invalid_bank_relationship_months' END,
                CASE WHEN marital_status IS NULL OR marital_status NOT IN
                    ('solteiro', 'casado', 'divorciado', 'uniao_estavel', 'viuvo')
                    THEN 'invalid_marital_status' END,
                CASE WHEN dependents IS NULL OR dependents < 0
                    THEN 'invalid_dependents' END,
                CASE WHEN housing_status IS NULL OR housing_status NOT IN
                    ('alugado', 'proprio_quitado', 'proprio_financiado', 'familia', 'outro')
                    THEN 'invalid_housing_status' END,
                CASE WHEN credit_history_months IS NULL OR credit_history_months < 0
                    THEN 'invalid_credit_history_months' END,
                CASE WHEN previous_loans IS NULL OR previous_loans < 0
                    THEN 'invalid_previous_loans' END,
                CASE WHEN previous_defaults IS NULL OR previous_defaults < 0
                    THEN 'invalid_previous_defaults' END,
                CASE WHEN previous_defaults > previous_loans
                    THEN 'defaults_greater_than_previous_loans' END,
                CASE WHEN bureau_inquiries_90d IS NULL OR bureau_inquiries_90d < 0
                    THEN 'invalid_bureau_inquiries_90d' END,
                CASE WHEN open_credit_lines IS NULL OR open_credit_lines < 0
                    THEN 'invalid_open_credit_lines' END,
                CASE WHEN credit_utilization IS NULL OR credit_utilization NOT BETWEEN 0 AND 1
                    THEN 'invalid_credit_utilization' END,
                CASE WHEN delinquency_12m IS NULL OR delinquency_12m < 0
                    THEN 'invalid_delinquency_12m' END,
                CASE WHEN avg_payment_delay_days IS NULL OR avg_payment_delay_days < 0
                    THEN 'invalid_avg_payment_delay_days' END,
                CASE WHEN monthly_existing_debt IS NULL OR monthly_existing_debt < 0
                    THEN 'invalid_monthly_existing_debt' END,
                CASE WHEN requested_amount IS NULL OR requested_amount <= 0
                    THEN 'invalid_requested_amount' END,
                CASE WHEN loan_purpose IS NULL OR loan_purpose NOT IN
                    ('capital_giro', 'consumo', 'renegociacao', 'educacao', 'saude', 'reforma', 'veiculo', 'emergencia')
                    THEN 'invalid_loan_purpose' END,
                CASE WHEN term_months IS NULL OR term_months <= 0
                    THEN 'invalid_term_months' END,
                CASE WHEN estimated_installment IS NULL OR estimated_installment <= 0
                    THEN 'invalid_estimated_installment' END,
                CASE WHEN debt_to_income IS NULL OR debt_to_income NOT BETWEEN 0 AND 2.5
                    THEN 'invalid_debt_to_income' END,
                CASE WHEN digital_behavior_score IS NULL OR digital_behavior_score NOT BETWEEN 0 AND 100
                    THEN 'invalid_digital_behavior_score' END,
                CASE WHEN device_age_months IS NULL OR device_age_months < 0
                    THEN 'invalid_device_age_months' END,
                CASE WHEN email_age_months IS NULL OR email_age_months < 0
                    THEN 'invalid_email_age_months' END,
                CASE WHEN phone_verified IS NULL THEN 'invalid_phone_verified' END,
                CASE WHEN document_consistency IS NULL THEN 'invalid_document_consistency' END,
                CASE WHEN ip_risk_score IS NULL OR ip_risk_score NOT BETWEEN 0 AND 100
                    THEN 'invalid_ip_risk_score' END,
                CASE WHEN credit_score_internal IS NULL OR credit_score_internal NOT BETWEEN 250 AND 950
                    THEN 'invalid_credit_score_internal' END,
                CASE WHEN risk_band IS NULL OR risk_band NOT IN ('A', 'B', 'C', 'D', 'E')
                    THEN 'invalid_risk_band' END,
                CASE WHEN approved IS NULL THEN 'invalid_approved' END,
                CASE WHEN approved_amount IS NULL OR approved_amount < 0
                    THEN 'invalid_approved_amount' END,
                CASE WHEN approved_amount > requested_amount
                    THEN 'approved_amount_greater_than_requested' END,
                CASE WHEN approved = TRUE AND approved_amount <= 0
                    THEN 'approved_application_without_amount' END,
                CASE WHEN approved = FALSE AND approved_amount <> 0
                    THEN 'rejected_application_with_approved_amount' END,
                CASE WHEN interest_rate_monthly IS NULL OR interest_rate_monthly NOT BETWEEN 0 AND 1
                    THEN 'invalid_interest_rate_monthly' END,
                CASE WHEN default_90d IS NULL THEN 'invalid_default_90d' END,
                CASE WHEN fraud_confirmed IS NULL THEN 'invalid_fraud_confirmed' END
            ]::TEXT[],
            NULL
        ) AS validation_errors
    FROM normalized n
)
SELECT *
FROM validated;

INSERT INTO staging.rejected_credit_applications (
    application_id,
    customer_id,
    raw_record,
    rejection_reason,
    source_file,
    raw_ingested_at
)
SELECT
    application_id,
    customer_id,
    raw_record,
    ARRAY_TO_STRING(validation_errors, '; '),
    source_file,
    raw_ingested_at
FROM tmp_credit_stage
WHERE CARDINALITY(validation_errors) > 0;

INSERT INTO staging.stg_credit_applications (
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
    fraud_confirmed,
    source_file,
    raw_ingested_at
)
SELECT
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
    fraud_confirmed,
    source_file,
    raw_ingested_at
FROM tmp_credit_stage
WHERE CARDINALITY(validation_errors) = 0;

COMMIT;
