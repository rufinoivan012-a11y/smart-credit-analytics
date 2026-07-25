-- ============================================================
-- Abre formalmente o lote da carga histórica inicial.
-- Execute antes da ingestão da RAW em uma reconstrução completa.
-- ============================================================

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM governance.etl_batch_control
        WHERE pipeline_name = 'credit_bootstrap_initial_load'
          AND status = 'running'
    ) THEN
        RAISE EXCEPTION
            'Já existe um lote running para credit_bootstrap_initial_load. Finalize ou corrija o lote atual antes de iniciar outro.';
    END IF;
END;
$$;

INSERT INTO governance.etl_batch_control (
    pipeline_name,
    load_type,
    source_file,
    status
)
VALUES (
    'credit_bootstrap_initial_load',
    'bootstrap',
    'fintech_credit_risk_dataset.csv',
    'running'
)
RETURNING
    batch_id,
    pipeline_name,
    load_type,
    source_file,
    status,
    started_at;

COMMIT;