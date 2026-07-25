-- ============================================================================
-- SMART CREDIT ANALYTICS
-- Script 18: validação da camada Analytics
--
-- Pré-requisito:
--   - 17_create_analytics_marts.sql executado com sucesso
--
-- Objetivo:
--   - Validar existência das views
--   - Validar granularidade e reconciliação com a camada Trusted
--   - Validar consistência dos KPIs
--   - Validar marts de risco, fraude e modelagem
--
-- Este script é somente leitura: não altera dados.
-- ============================================================================

-- ============================================================================
-- 1. EXISTÊNCIA DAS VIEWS
-- ============================================================================

SELECT 
	table_schema,
	table_name
FROM information_schema.views
WHERE table_schema = 'analytics'
ORDER BY table_name;

-- ============================================================================
-- 2. GRANULARIDADE DA VIEW 360
-- Esperado:
--   fact_rows = analytics_rows = distinct_applications = 8000
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM trusted.fact_credit_applications) AS fact_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360) AS analytics_rows,

    (SELECT COUNT(DISTINCT application_id)
     FROM analytics.vw_credit_application_360) AS distinct_applications;


-- Duplicidades na granularidade da visão 360.
-- Esperado: 0 linhas.

SELECT
    application_id,
    COUNT(*) AS occurrences
FROM analytics.vw_credit_application_360
GROUP BY application_id
HAVING COUNT(*) > 1;


-- ============================================================================
-- 3. CAMPOS CRÍTICOS DA VIEW 360
-- Esperado: todos os contadores iguais a 0.
-- ============================================================================

SELECT
    COUNT(*) FILTER (WHERE application_id IS NULL) AS null_application_id,
    COUNT(*) FILTER (WHERE application_date IS NULL) AS null_application_date,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE uf IS NULL) AS null_uf,
    COUNT(*) FILTER (WHERE channel IS NULL) AS null_channel,
    COUNT(*) FILTER (WHERE requested_amount IS NULL) AS null_requested_amount,
    COUNT(*) FILTER (WHERE approved IS NULL) AS null_approved,
    COUNT(*) FILTER (WHERE risk_band IS NULL) AS null_risk_band
FROM analytics.vw_credit_application_360;


-- ============================================================================
-- 4. CONSISTÊNCIA DOS CAMPOS DERIVADOS
-- Esperado: todos os contadores iguais a 0.
-- ============================================================================

SELECT
    COUNT(*) FILTER (
        WHERE approved IS TRUE
          AND decision_status <> 'approved'
    ) AS invalid_approved_status,

    COUNT(*) FILTER (
        WHERE approved IS FALSE
          AND decision_status <> 'rejected'
    ) AS invalid_rejected_status,

    COUNT(*) FILTER (
        WHERE approved_flag <> CASE WHEN approved IS TRUE THEN 1 ELSE 0 END
    ) AS invalid_approved_flag,

    COUNT(*) FILTER (
        WHERE default_90d_flag <> CASE WHEN default_90d IS TRUE THEN 1 ELSE 0 END
    ) AS invalid_default_flag,

    COUNT(*) FILTER (
        WHERE fraud_confirmed_flag <>
              CASE WHEN fraud_confirmed IS TRUE THEN 1 ELSE 0 END
    ) AS invalid_fraud_flag
FROM analytics.vw_credit_application_360;


-- Razões derivadas: comparação com recálculo direto.
-- Esperado: todos os contadores iguais a 0.

SELECT
    COUNT(*) FILTER (
        WHERE monthly_income <> 0
          AND requested_amount_to_income <>
              ROUND(requested_amount / NULLIF(monthly_income, 0), 4)
    ) AS invalid_requested_income_ratio,

    COUNT(*) FILTER (
        WHERE monthly_income <> 0
          AND installment_to_income <>
              ROUND(estimated_installment / NULLIF(monthly_income, 0), 4)
    ) AS invalid_installment_income_ratio
FROM analytics.vw_credit_application_360;


-- ============================================================================
-- 5. RECONCILIAÇÃO DOS KPIs DIÁRIOS
-- Esperado: os valores analytics e direct devem ser iguais.
-- ============================================================================

SELECT
    SUM(k.total_applications) AS analytics_total_applications,
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360) AS direct_total_applications,

    SUM(k.approved_applications) AS analytics_approved_applications,
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360
     WHERE approved IS TRUE) AS direct_approved_applications,

    SUM(k.rejected_applications) AS analytics_rejected_applications,
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360
     WHERE approved IS FALSE) AS direct_rejected_applications,

    SUM(k.defaulted_approved_applications) AS analytics_defaulted_approved,
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360
     WHERE approved IS TRUE
       AND default_90d IS TRUE) AS direct_defaulted_approved,

    SUM(k.confirmed_fraud_cases) AS analytics_confirmed_fraud,
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360
     WHERE fraud_confirmed IS TRUE) AS direct_confirmed_fraud
FROM analytics.vw_credit_kpis_daily k;


-- Reconciliação financeira dos KPIs diários.
-- Esperado: diferenças iguais a 0.00.

SELECT
    ROUND(
        SUM(k.total_requested_amount)
        - (SELECT SUM(requested_amount)
           FROM analytics.vw_credit_application_360),
        2
    ) AS requested_amount_difference,

    ROUND(
        SUM(k.total_approved_amount)
        - (SELECT COALESCE(SUM(approved_amount), 0)
           FROM analytics.vw_credit_application_360
           WHERE approved IS TRUE),
        2
    ) AS approved_amount_difference,

    ROUND(
        SUM(k.exposure_default_90d)
        - (SELECT COALESCE(SUM(approved_amount), 0)
           FROM analytics.vw_credit_application_360
           WHERE approved IS TRUE
             AND default_90d IS TRUE),
        2
    ) AS default_exposure_difference
FROM analytics.vw_credit_kpis_daily k;


-- Uma linha por data e nenhuma taxa fora de 0 a 100.
-- Esperado: todos os contadores iguais a 0.

SELECT
    COUNT(*) FILTER (
        WHERE application_date IS NULL
    ) AS null_dates,

    COUNT(*) - COUNT(DISTINCT application_date) AS duplicate_dates,

    COUNT(*) FILTER (
        WHERE approval_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_approval_rates,

    COUNT(*) FILTER (
        WHERE rejection_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_rejection_rates,

    COUNT(*) FILTER (
        WHERE default_rate_90d_pct NOT BETWEEN 0 AND 100
    ) AS invalid_default_rates,

    COUNT(*) FILTER (
        WHERE fraud_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_fraud_rates,

    COUNT(*) FILTER (
        WHERE ABS((approval_rate_pct + rejection_rate_pct) - 100.00) > 0.01
    ) AS invalid_decision_rate_sum
FROM analytics.vw_credit_kpis_daily;


-- Recalcular as taxas diárias e procurar divergências.
-- Esperado: 0 linhas.

SELECT
    application_date,
    approval_rate_pct,
    ROUND(
        100.0 * approved_applications / NULLIF(total_applications, 0),
        2
    ) AS recalculated_approval_rate,
    rejection_rate_pct,
    ROUND(
        100.0 * rejected_applications / NULLIF(total_applications, 0),
        2
    ) AS recalculated_rejection_rate,
    default_rate_90d_pct,
    ROUND(
        100.0 * defaulted_approved_applications
        / NULLIF(approved_applications, 0),
        2
    ) AS recalculated_default_rate,
    fraud_rate_pct,
    ROUND(
        100.0 * confirmed_fraud_cases
        / NULLIF(total_applications, 0),
        2
    ) AS recalculated_fraud_rate
FROM analytics.vw_credit_kpis_daily
WHERE approval_rate_pct <>
          ROUND(100.0 * approved_applications / NULLIF(total_applications, 0), 2)
   OR rejection_rate_pct <>
          ROUND(100.0 * rejected_applications / NULLIF(total_applications, 0), 2)
   OR default_rate_90d_pct IS DISTINCT FROM
          ROUND(
              100.0 * defaulted_approved_applications
              / NULLIF(approved_applications, 0),
              2
          )
   OR fraud_rate_pct <>
          ROUND(100.0 * confirmed_fraud_cases / NULLIF(total_applications, 0), 2);


-- ============================================================================
-- 6. VALIDAÇÃO DO MART DE RISCO
-- Esperado:
--   - 5 faixas, A a E
--   - totais reconciliados com a visão 360
-- ============================================================================

SELECT
    COUNT(*) AS risk_band_rows,
    COUNT(DISTINCT risk_band) AS distinct_risk_bands,
    MIN(risk_band) AS min_risk_band,
    MAX(risk_band) AS max_risk_band
FROM analytics.vw_credit_risk_analysis;


-- Faixas inesperadas.
-- Esperado: 0 linhas.

SELECT risk_band
FROM analytics.vw_credit_risk_analysis
WHERE risk_band NOT IN ('A', 'B', 'C', 'D', 'E')
   OR risk_band IS NULL;


-- Reconciliação de volumes e valores por faixa de risco.
-- Esperado: diferenças iguais a zero.

SELECT
    SUM(total_applications)
      - (SELECT COUNT(*)
         FROM analytics.vw_credit_application_360)
      AS application_count_difference,

    SUM(approved_applications)
      - (SELECT COUNT(*)
         FROM analytics.vw_credit_application_360
         WHERE approved IS TRUE)
      AS approved_count_difference,

    SUM(rejected_applications)
      - (SELECT COUNT(*)
         FROM analytics.vw_credit_application_360
         WHERE approved IS FALSE)
      AS rejected_count_difference,

    ROUND(
        SUM(total_requested_amount)
        - (SELECT SUM(requested_amount)
           FROM analytics.vw_credit_application_360),
        2
    ) AS requested_amount_difference,

    ROUND(
        SUM(total_approved_amount)
        - (SELECT COALESCE(SUM(approved_amount), 0)
           FROM analytics.vw_credit_application_360
           WHERE approved IS TRUE),
        2
    ) AS approved_amount_difference
FROM analytics.vw_credit_risk_analysis;


-- Taxas e contagens inválidas no mart de risco.
-- Esperado: todos os contadores iguais a 0.

SELECT
    COUNT(*) FILTER (
        WHERE approval_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_approval_rates,

    COUNT(*) FILTER (
        WHERE default_rate_90d_pct NOT BETWEEN 0 AND 100
    ) AS invalid_default_rates,

    COUNT(*) FILTER (
        WHERE fraud_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_fraud_rates,

    COUNT(*) FILTER (
        WHERE approved_applications + rejected_applications
              <> total_applications
    ) AS invalid_decision_counts
FROM analytics.vw_credit_risk_analysis;


-- ============================================================================
-- 7. VALIDAÇÃO DO MONITORAMENTO DE FRAUDE
-- Como cada solicitação pertence a uma combinação única de data + UF + canal,
-- a soma dos grupos deve reconciliar com a visão 360.
-- Esperado: diferenças iguais a zero.
-- ============================================================================

SELECT
    SUM(total_applications)
      - (SELECT COUNT(*)
         FROM analytics.vw_credit_application_360)
      AS application_count_difference,

    SUM(confirmed_fraud_cases)
      - (SELECT COUNT(*)
         FROM analytics.vw_credit_application_360
         WHERE fraud_confirmed IS TRUE)
      AS fraud_count_difference,

    ROUND(
        SUM(requested_amount_confirmed_fraud)
        - (SELECT COALESCE(SUM(requested_amount), 0)
           FROM analytics.vw_credit_application_360
           WHERE fraud_confirmed IS TRUE),
        2
    ) AS fraud_requested_amount_difference,

    ROUND(
        SUM(approved_exposure_confirmed_fraud)
        - (SELECT COALESCE(SUM(approved_amount), 0)
           FROM analytics.vw_credit_application_360
           WHERE approved IS TRUE
             AND fraud_confirmed IS TRUE),
        2
    ) AS fraud_approved_exposure_difference
FROM analytics.vw_fraud_monitoring;


-- Chave de agrupamento duplicada ou métricas inválidas.
-- Esperado: todos os contadores iguais a 0.

SELECT
    COUNT(*) - COUNT(DISTINCT (application_date, uf, channel))
        AS duplicate_group_keys,

    COUNT(*) FILTER (
        WHERE application_date IS NULL
           OR uf IS NULL
           OR channel IS NULL
    ) AS null_group_keys,

    COUNT(*) FILTER (
        WHERE fraud_rate_pct NOT BETWEEN 0 AND 100
    ) AS invalid_fraud_rates,

    COUNT(*) FILTER (
        WHERE confirmed_fraud_cases > total_applications
    ) AS fraud_count_greater_than_total
FROM analytics.vw_fraud_monitoring;


-- ============================================================================
-- 8. VALIDAÇÃO DA BASE DE MODELAGEM
-- Esperado:
--   - 8000 linhas
--   - 8000 application_id distintos
--   - 0 duplicidades
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360) AS application_360_rows,

    COUNT(*) AS training_rows,
    COUNT(DISTINCT application_id) AS distinct_applications,

    COUNT(*) FILTER (WHERE eligible_default_model IS TRUE)
        AS eligible_default_rows,

    COUNT(*) FILTER (WHERE eligible_fraud_model IS TRUE)
        AS eligible_fraud_rows
FROM analytics.vw_model_training_dataset;


-- Duplicidades na base de modelagem.
-- Esperado: 0 linhas.

SELECT
    application_id,
    COUNT(*) AS occurrences
FROM analytics.vw_model_training_dataset
GROUP BY application_id
HAVING COUNT(*) > 1;


-- Consistência dos indicadores de elegibilidade.
-- Esperado: todos os contadores iguais a 0.

SELECT
    COUNT(*) FILTER (
        WHERE eligible_default_model IS TRUE
          AND NOT (
              selection_approved IS TRUE
              AND target_default_90d IS NOT NULL
              AND target_fraud_confirmed IS FALSE
          )
    ) AS invalid_default_eligibility,

    COUNT(*) FILTER (
        WHERE eligible_fraud_model IS TRUE
          AND target_fraud_confirmed IS NULL
    ) AS invalid_fraud_eligibility,

    COUNT(*) FILTER (
        WHERE eligible_default_model IS FALSE
          AND selection_approved IS TRUE
          AND target_default_90d IS NOT NULL
          AND target_fraud_confirmed IS FALSE
    ) AS missing_default_eligibility,

    COUNT(*) FILTER (
        WHERE eligible_fraud_model IS FALSE
          AND target_fraud_confirmed IS NOT NULL
    ) AS missing_fraud_eligibility
FROM analytics.vw_model_training_dataset;


-- Distribuição dos targets e das amostras elegíveis.
-- Consulta informativa: não há um valor único esperado, mas os totais devem
-- ser plausíveis e reconciliáveis com a visão 360.

SELECT
    selection_approved,
    target_default_90d,
    target_fraud_confirmed,
    eligible_default_model,
    eligible_fraud_model,
    COUNT(*) AS rows
FROM analytics.vw_model_training_dataset
GROUP BY
    selection_approved,
    target_default_90d,
    target_fraud_confirmed,
    eligible_default_model,
    eligible_fraud_model
ORDER BY
    selection_approved DESC,
    target_default_90d DESC,
    target_fraud_confirmed DESC;


-- Verificação de colunas pós-decisão que não devem estar presentes como
-- features na base de modelagem.
-- Esperado: 0 linhas.

SELECT
    column_name
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND table_name = 'vw_model_training_dataset'
  AND column_name IN (
      'approved_amount',
      'interest_rate_monthly',
      'decision_status',
      'approved_flag',
      'default_90d_flag',
      'fraud_confirmed_flag'
  );


-- ============================================================================
-- 9. RESUMO EXECUTIVO DE VALIDAÇÃO
-- Resultado informativo para evidência do pipeline.
-- ============================================================================

SELECT
    (SELECT COUNT(*)
     FROM trusted.fact_credit_applications) AS fact_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_credit_application_360) AS application_360_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_credit_kpis_daily) AS daily_kpi_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_credit_risk_analysis) AS risk_band_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_fraud_monitoring) AS fraud_monitoring_rows,

    (SELECT COUNT(*)
     FROM analytics.vw_model_training_dataset) AS model_training_rows;