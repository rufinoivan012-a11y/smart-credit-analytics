-- 1. Reconciliação de registros
SELECT
    (SELECT COUNT(*) FROM raw.credit_applications) AS raw_rows,
    (SELECT COUNT(*) FROM staging.stg_credit_applications) AS valid_rows,
    (SELECT COUNT(*) FROM staging.rejected_credit_applications) AS rejected_rows,
    (SELECT COUNT(*) FROM staging.stg_credit_applications)
      + (SELECT COUNT(*) FROM staging.rejected_credit_applications) AS processed_rows;

-- 2. Interrompe a validação se RAW != válidos + rejeitados
DO $$
DECLARE
    v_raw BIGINT;
    v_valid BIGINT;
    v_rejected BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_raw FROM raw.credit_applications;
    SELECT COUNT(*) INTO v_valid FROM staging.stg_credit_applications;
    SELECT COUNT(*) INTO v_rejected FROM staging.rejected_credit_applications;

    IF v_raw <> v_valid + v_rejected THEN
        RAISE EXCEPTION
            'Falha de reconciliação: raw=%, valid=%, rejected=%',
            v_raw, v_valid, v_rejected;
    END IF;
END;
$$;

-- 3. Duplicidades entre registros válidos
SELECT application_id, COUNT(*) AS occurrences
FROM staging.stg_credit_applications
GROUP BY application_id
HAVING COUNT(*) > 1;

-- 4. Campos obrigatórios inválidos
SELECT
    COUNT(*) FILTER (WHERE application_id IS NULL) AS null_application_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE application_date IS NULL) AS null_application_date,
    COUNT(*) FILTER (WHERE source_file IS NULL) AS null_source_file,
    COUNT(*) FILTER (WHERE raw_ingested_at IS NULL) AS null_raw_ingested_at
FROM staging.stg_credit_applications;

-- 5. Regras críticas de domínio
SELECT
    COUNT(*) FILTER (WHERE age NOT BETWEEN 18 AND 80) AS invalid_age,
    COUNT(*) FILTER (WHERE monthly_income <= 0) AS invalid_income,
    COUNT(*) FILTER (WHERE requested_amount <= 0) AS invalid_requested_amount,
    COUNT(*) FILTER (WHERE approved_amount > requested_amount) AS invalid_approved_amount,
    COUNT(*) FILTER (WHERE credit_score_internal NOT BETWEEN 250 AND 950) AS invalid_score,
    COUNT(*) FILTER (WHERE risk_band NOT IN ('A', 'B', 'C', 'D', 'E')) AS invalid_risk_band
FROM staging.stg_credit_applications;

-- 6. Resumo de rejeições
SELECT rejection_reason, COUNT(*) AS rejected_rows
FROM staging.rejected_credit_applications
GROUP BY rejection_reason
ORDER BY rejected_rows DESC, rejection_reason;

-- 7. Amostra da staging válida
SELECT
    application_id,
    application_date,
    age,
    monthly_income,
    requested_amount,
    approved,
    default_90d,
    source_file,
    staging_loaded_at
FROM staging.stg_credit_applications
ORDER BY application_date, application_id
LIMIT 10;
