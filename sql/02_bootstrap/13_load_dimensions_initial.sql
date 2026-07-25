BEGIN;

-- ============================================================
-- CARGA INICIAL DAS DIMENSÕES
-- Estratégia: full refresh idempotente para o bootstrap
-- ============================================================

-- A fato e as dimensões relacionadas precisam ser truncadas
-- no mesmo comando por causa das foreign keys.

TRUNCATE TABLE
    trusted.fact_credit_applications,
    trusted.dim_customer,
    trusted.dim_location,
    trusted.dim_acquisition_channel,
    trusted.dim_credit_profile_snapshot,
    trusted.dim_digital_risk_profile
RESTART IDENTITY;


-- ============================================================
-- 1. DIMENSÃO DE CLIENTES
-- Mantém o registro mais recente de cada customer_id
-- ============================================================

INSERT INTO trusted.dim_customer (
    customer_id,
    age,
    gender,
    education,
    employment_type,
    months_employed,
    monthly_income,
    marital_status,
    dependents,
    housing_status,
    bank_relationship_months,
    credit_history_months
)
SELECT DISTINCT ON (customer_id)
    customer_id,
    age,
    gender,
    education,
    employment_type,
    months_employed,
    monthly_income,
    marital_status,
    dependents,
    housing_status,
    bank_relationship_months,
    credit_history_months
FROM staging.stg_credit_applications
ORDER BY
    customer_id,
    application_date DESC,
    staging_loaded_at DESC;


-- ============================================================
-- 2. DIMENSÃO DE LOCALIZAÇÃO
-- ============================================================

INSERT INTO trusted.dim_location (
    uf,
    region,
    country
)
SELECT DISTINCT
    uf,

    CASE
        WHEN uf IN (
            'AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO'
        )
        THEN 'Norte'

        WHEN uf IN (
            'AL', 'BA', 'CE', 'MA', 'PB',
            'PE', 'PI', 'RN', 'SE'
        )
        THEN 'Nordeste'

        WHEN uf IN (
            'DF', 'GO', 'MT', 'MS'
        )
        THEN 'Centro-Oeste'

        WHEN uf IN (
            'ES', 'MG', 'RJ', 'SP'
        )
        THEN 'Sudeste'

        WHEN uf IN (
            'PR', 'RS', 'SC'
        )
        THEN 'Sul'

        ELSE 'Desconhecida'
    END AS region,

    'Brasil' AS country

FROM staging.stg_credit_applications
ORDER BY uf;


-- ============================================================
-- 3. DIMENSÃO DE CANAL DE AQUISIÇÃO
-- ============================================================

INSERT INTO trusted.dim_acquisition_channel (
    channel,
    channel_group
)
SELECT DISTINCT
    channel,

    CASE
        WHEN channel IN (
            'app_android',
            'app_ios'
        )
        THEN 'mobile_app'

        WHEN channel = 'web'
        THEN 'web'

        WHEN channel = 'parceiro'
        THEN 'partner'

        WHEN channel = 'whatsapp'
        THEN 'messaging'

        ELSE 'other'
    END AS channel_group

FROM staging.stg_credit_applications
ORDER BY channel;


-- ============================================================
-- 4. DIMENSÃO DE SNAPSHOT DO PERFIL DE CRÉDITO
-- ============================================================

INSERT INTO trusted.dim_credit_profile_snapshot (
    previous_loans,
    previous_defaults,
    bureau_inquiries_90d,
    open_credit_lines,
    credit_utilization,
    delinquency_12m,
    avg_payment_delay_days,
    monthly_existing_debt,
    debt_to_income
)
SELECT DISTINCT
    previous_loans,
    previous_defaults,
    bureau_inquiries_90d,
    open_credit_lines,
    credit_utilization,
    delinquency_12m,
    avg_payment_delay_days,
    monthly_existing_debt,
    debt_to_income
FROM staging.stg_credit_applications;


-- ============================================================
-- 5. DIMENSÃO DE PERFIL DIGITAL E RISCO
-- ============================================================

INSERT INTO trusted.dim_digital_risk_profile (
    digital_behavior_score,
    device_age_months,
    email_age_months,
    phone_verified,
    document_consistency,
    ip_risk_score
)
SELECT DISTINCT
    digital_behavior_score,
    device_age_months,
    email_age_months,
    phone_verified,
    document_consistency,
    ip_risk_score
FROM staging.stg_credit_applications;


COMMIT;