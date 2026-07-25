-- ============================================================
-- Fecha o lote de bootstrap após a validação da camada TRUSTED.
-- Execute somente depois de 15_validate_trusted.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM governance.etl_batch_control
        WHERE pipeline_name = 'credit_bootstrap_initial_load'
          AND status = 'running'
    ) THEN
        RAISE EXCEPTION
            'Não existe lote running para credit_bootstrap_initial_load. O script 08 precisa ter sido executado nesta reconstrução.';
    END IF;
END;
$$;

WITH metrics AS (
    SELECT
        (SELECT COUNT(*) FROM raw.credit_applications) AS raw_rows,
        (SELECT COUNT(*) FROM staging.stg_credit_applications) AS valid_rows,
        (SELECT COUNT(*) FROM staging.rejected_credit_applications) AS rejected_rows,
        (SELECT COUNT(*) FROM trusted.fact_credit_applications) AS fact_rows
),
active_batch AS (
    SELECT batch_id
    FROM governance.etl_batch_control
    WHERE pipeline_name = 'credit_bootstrap_initial_load'
      AND status = 'running'
    ORDER BY started_at DESC
    LIMIT 1
)
UPDATE governance.etl_batch_control b
SET
    completed_at = CURRENT_TIMESTAMP,
    raw_rows = m.raw_rows,
    valid_rows = m.valid_rows,
    rejected_rows = m.rejected_rows,
    fact_rows = m.fact_rows,
    status = CASE
        WHEN m.raw_rows = m.valid_rows + m.rejected_rows
         AND m.valid_rows = m.fact_rows
        THEN 'completed'
        ELSE 'failed'
    END,
    error_message = CASE
        WHEN m.raw_rows <> m.valid_rows + m.rejected_rows
        THEN FORMAT(
            'Falha de reconciliação RAW/STAGING: raw=%s, valid=%s, rejected=%s',
            m.raw_rows,
            m.valid_rows,
            m.rejected_rows
        )
        WHEN m.valid_rows <> m.fact_rows
        THEN FORMAT(
            'Falha de reconciliação STAGING/FACT: valid=%s, fact=%s',
            m.valid_rows,
            m.fact_rows
        )
        ELSE NULL
    END
FROM metrics m
JOIN active_batch a ON a.batch_id = b.batch_id
RETURNING
    b.batch_id,
    b.pipeline_name,
    b.load_type,
    b.status,
    b.raw_rows,
    b.valid_rows,
    b.rejected_rows,
    b.fact_rows,
    b.started_at,
    b.completed_at,
    b.error_message;

COMMIT;

-- Histórico mais recente do pipeline.
SELECT
    batch_id,
    pipeline_name,
    load_type,
    source_file,
    status,
    raw_rows,
    valid_rows,
    rejected_rows,
    fact_rows,
    started_at,
    completed_at,
    error_message
FROM governance.etl_batch_control
WHERE pipeline_name = 'credit_bootstrap_initial_load'
ORDER BY started_at DESC
LIMIT 5;