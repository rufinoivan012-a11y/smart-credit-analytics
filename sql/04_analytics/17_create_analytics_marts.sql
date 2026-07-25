-- ============================================================================
-- SMART CREDIT ANALYTICS
-- Script 17: criação da camada Analytics (views semânticas e marts)
--
-- Pré-requisitos:
--   - trusted.dim_date carregada
--   - trusted.dim_customer carregada
--   - trusted.dim_location carregada
--   - trusted.dim_acquisition_channel carregada
--   - trusted.dim_credit_profile_snapshot carregada
--   - trusted.dim_digital_risk_profile carregada
--   - trusted.fact_credit_applications carregada e validada
--
-- Estratégia da versão 1:
--   - Views lógicas, adequadas ao volume inicial e ao consumo pelo Power BI.
--   - Nenhuma regra altera os dados da camada Trusted.
--   - Métricas de inadimplência usam apenas operações aprovadas no denominador.
-- ============================================================================


BEGIN;

CREATE SCHEMA IF NOT EXISTS analytics;

-- ============================================================================
-- 1. VISÃO ANALÍTICA 360 DA SOLICITAÇÃO
-- Granularidade: uma linha por application_id.
-- Objetivo: camada semântica principal para exploração, BI e auditoria.
-- ============================================================================

CREATE OR REPLACE VIEW analytics.vw_credit_application_360 AS
SELECT
    -- Identificadores e chaves
    f.application_key,
    f.application_id,
    f.date_key,
    c.customer_key,
    c.customer_id,
    l.location_key,
    ch.channel_key,
    cp.credit_profile_key,
    dr.digital_risk_key,

    -- Calendário
    d.full_date AS application_date,
    d.day,
    d.month,
    d.month_name,
    d.quarter,
    d.year,
    d.week_of_year,
    d.day_of_week,
    d.day_name,
    d.is_weekend,

    -- Localização e aquisição
    l.uf,
    l.region,
    l.country,
    ch.channel,
    ch.channel_group,

    -- Cadastro do cliente
    c.age,
    c.gender,
    c.education,
    c.employment_type,
    c.months_employed,
    c.monthly_income,
    c.marital_status,
    c.dependents,
    c.housing_status,
    c.bank_relationship_months,
    c.credit_history_months,

    -- Snapshot do perfil de crédito
    cp.previous_loans,
    cp.previous_defaults,
    cp.bureau_inquiries_90d,
    cp.open_credit_lines,
    cp.credit_utilization,
    cp.delinquency_12m,
    cp.avg_payment_delay_days,
    cp.monthly_existing_debt,
    cp.debt_to_income,

    -- Snapshot do perfil digital/antifraude
    dr.digital_behavior_score,
    dr.device_age_months,
    dr.email_age_months,
    dr.phone_verified,
    dr.document_consistency,
    dr.ip_risk_score,

    -- Solicitação, decisão e desfechos
    f.requested_amount,
    f.loan_purpose,
    f.term_months,
    f.estimated_installment,
    f.credit_score_internal,
    f.risk_band,
    f.approved,
    f.approved_amount,
    f.interest_rate_monthly,
    f.default_90d,
    f.fraud_confirmed,

    -- Campos derivados para consumo analítico
    CASE
        WHEN f.approved IS TRUE THEN 'approved'
        WHEN f.approved IS FALSE THEN 'rejected'
        ELSE 'unknown'
    END AS decision_status,

    CASE WHEN f.approved IS TRUE THEN 1 ELSE 0 END AS approved_flag,
    CASE WHEN f.default_90d IS TRUE THEN 1 ELSE 0 END AS default_90d_flag,
    CASE WHEN f.fraud_confirmed IS TRUE THEN 1 ELSE 0 END AS fraud_confirmed_flag,

    ROUND(
        f.requested_amount / NULLIF(c.monthly_income, 0),
        4
    ) AS requested_amount_to_income,

    ROUND(
        f.estimated_installment / NULLIF(c.monthly_income, 0),
        4
    ) AS installment_to_income

FROM trusted.fact_credit_applications f
JOIN trusted.dim_date d
    ON d.date_key = f.date_key
JOIN trusted.dim_customer c
    ON c.customer_key = f.customer_key
JOIN trusted.dim_location l
    ON l.location_key = f.location_key
JOIN trusted.dim_acquisition_channel ch
    ON ch.channel_key = f.channel_key
JOIN trusted.dim_credit_profile_snapshot cp
    ON cp.credit_profile_key = f.credit_profile_key
JOIN trusted.dim_digital_risk_profile dr
    ON dr.digital_risk_key = f.digital_risk_key;

COMMENT ON VIEW analytics.vw_credit_application_360 IS
'Visão analítica consolidada com granularidade de uma linha por solicitação de crédito.';


-- ============================================================================
-- 2. KPIs DIÁRIOS DE CRÉDITO
-- Granularidade: uma linha por data.
-- Observação: default_rate_90d_pct usa somente operações aprovadas.
-- ============================================================================

CREATE OR REPLACE VIEW analytics.vw_credit_kpis_daily AS
SELECT
    application_date,
    year,
    quarter,
    month,
    month_name,
    week_of_year,

    COUNT(*) AS total_applications,
    COUNT(*) FILTER (WHERE approved IS TRUE) AS approved_applications,
    COUNT(*) FILTER (WHERE approved IS FALSE) AS rejected_applications,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE approved IS TRUE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE approved IS FALSE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS rejection_rate_pct,

    SUM(requested_amount) AS total_requested_amount,
    COALESCE(
        SUM(approved_amount) FILTER (WHERE approved IS TRUE),
        0
    ) AS total_approved_amount,

    ROUND(AVG(requested_amount), 2) AS avg_requested_amount,
    ROUND(
        AVG(approved_amount) FILTER (WHERE approved IS TRUE),
        2
    ) AS avg_approved_amount,

    COUNT(*) FILTER (
        WHERE approved IS TRUE
          AND default_90d IS TRUE
    ) AS defaulted_approved_applications,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE approved IS TRUE
              AND default_90d IS TRUE
        )
        / NULLIF(
            COUNT(*) FILTER (WHERE approved IS TRUE),
            0
        ),
        2
    ) AS default_rate_90d_pct,

    COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE) AS confirmed_fraud_cases,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS fraud_rate_pct,

    COALESCE(
        SUM(approved_amount) FILTER (
            WHERE approved IS TRUE
              AND default_90d IS TRUE
        ),
        0
    ) AS exposure_default_90d

FROM analytics.vw_credit_application_360
GROUP BY
    application_date,
    year,
    quarter,
    month,
    month_name,
    week_of_year;

COMMENT ON VIEW analytics.vw_credit_kpis_daily IS
'KPIs diários de volume, aprovação, exposição, inadimplência em 90 dias e fraude confirmada.';


-- ============================================================================
-- 3. ANÁLISE DE PERFORMANCE POR FAIXA DE RISCO
-- Granularidade: uma linha por risk_band.
-- exposure_default_90d é exposição aprovada em default, não perda financeira.
-- ============================================================================

CREATE OR REPLACE VIEW analytics.vw_credit_risk_analysis AS
SELECT
    risk_band,

    COUNT(*) AS total_applications,
    COUNT(*) FILTER (WHERE approved IS TRUE) AS approved_applications,
    COUNT(*) FILTER (WHERE approved IS FALSE) AS rejected_applications,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE approved IS TRUE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,

    ROUND(AVG(credit_score_internal), 2) AS avg_credit_score,
    ROUND(AVG(debt_to_income), 4) AS avg_debt_to_income,
    ROUND(AVG(credit_utilization), 4) AS avg_credit_utilization,

    SUM(requested_amount) AS total_requested_amount,
    COALESCE(
        SUM(approved_amount) FILTER (WHERE approved IS TRUE),
        0
    ) AS total_approved_amount,

    COUNT(*) FILTER (
        WHERE approved IS TRUE
          AND default_90d IS TRUE
    ) AS defaulted_approved_applications,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE approved IS TRUE
              AND default_90d IS TRUE
        )
        / NULLIF(
            COUNT(*) FILTER (WHERE approved IS TRUE),
            0
        ),
        2
    ) AS default_rate_90d_pct,

    COALESCE(
        SUM(approved_amount) FILTER (
            WHERE approved IS TRUE
              AND default_90d IS TRUE
        ),
        0
    ) AS exposure_default_90d,

    COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE) AS confirmed_fraud_cases,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS fraud_rate_pct

FROM analytics.vw_credit_application_360
GROUP BY risk_band;

COMMENT ON VIEW analytics.vw_credit_risk_analysis IS
'Performance agregada das solicitações por faixa interna de risco.';


-- ============================================================================
-- 4. MONITORAMENTO DE FRAUDE
-- Granularidade: data + UF + canal.
-- Não cria score ou regra heurística nova; expõe sinais observados.
-- ============================================================================

CREATE OR REPLACE VIEW analytics.vw_fraud_monitoring AS
SELECT
    application_date,
    uf,
    region,
    channel,
    channel_group,

    COUNT(*) AS total_applications,
    COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE) AS confirmed_fraud_cases,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE fraud_confirmed IS TRUE)
        / NULLIF(COUNT(*), 0),
        2
    ) AS fraud_rate_pct,

    COUNT(*) FILTER (WHERE phone_verified IS FALSE) AS unverified_phone_cases,
    COUNT(*) FILTER (WHERE document_consistency IS FALSE) AS inconsistent_document_cases,

    ROUND(AVG(ip_risk_score), 2) AS avg_ip_risk_score,
    MAX(ip_risk_score) AS max_ip_risk_score,
    ROUND(AVG(digital_behavior_score), 2) AS avg_digital_behavior_score,

    COALESCE(
        SUM(requested_amount) FILTER (WHERE fraud_confirmed IS TRUE),
        0
    ) AS requested_amount_confirmed_fraud,

    COALESCE(
        SUM(approved_amount) FILTER (
            WHERE approved IS TRUE
              AND fraud_confirmed IS TRUE
        ),
        0
    ) AS approved_exposure_confirmed_fraud

FROM analytics.vw_credit_application_360
GROUP BY
    application_date,
    uf,
    region,
    channel,
    channel_group;

COMMENT ON VIEW analytics.vw_fraud_monitoring IS
'Monitoramento agregado de fraude confirmada e sinais digitais por data, UF e canal.';


-- ============================================================================
-- 5. BASE ANALÍTICA PARA MODELAGEM
-- Granularidade: uma linha por application_id.
--
-- Contém somente atributos disponíveis na solicitação e os targets separados.
-- Campos de decisão posterior (approved_amount e interest_rate_monthly) não são
-- incluídos como features, reduzindo risco de data leakage.
--
-- Para o modelo de default:
--   WHERE eligible_default_model = TRUE
--   target = target_default_90d
--
-- Para o modelo de fraude:
--   WHERE eligible_fraud_model = TRUE
--   target = target_fraud_confirmed
--
-- approved é mantido somente como indicador de seleção da amostra de default;
-- não deve ser usado como feature preditiva.
-- ============================================================================

CREATE OR REPLACE VIEW analytics.vw_model_training_dataset AS
SELECT
    application_id,
    application_date,

    -- Contexto cadastral e de aquisição
    uf,
    region,
    channel,
    channel_group,
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

    -- Perfil de crédito
    previous_loans,
    previous_defaults,
    bureau_inquiries_90d,
    open_credit_lines,
    credit_utilization,
    delinquency_12m,
    avg_payment_delay_days,
    monthly_existing_debt,
    debt_to_income,

    -- Solicitação
    requested_amount,
    loan_purpose,
    term_months,
    estimated_installment,
    requested_amount_to_income,
    installment_to_income,

    -- Perfil digital e antifraude
    digital_behavior_score,
    device_age_months,
    email_age_months,
    phone_verified,
    document_consistency,
    ip_risk_score,

    -- Indicador de seleção e targets
    approved AS selection_approved,
    default_90d AS target_default_90d,
    fraud_confirmed AS target_fraud_confirmed,

    (
        approved IS TRUE
        AND default_90d IS NOT NULL
        AND fraud_confirmed IS FALSE
    ) AS eligible_default_model,

    (fraud_confirmed IS NOT NULL) AS eligible_fraud_model

FROM analytics.vw_credit_application_360;

COMMENT ON VIEW analytics.vw_model_training_dataset IS
'Base preditiva com features pré-decisão, targets separados e indicadores de elegibilidade para default e fraude.';

COMMIT;