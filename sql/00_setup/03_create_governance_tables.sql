-- ============================================================
-- Estruturas de governança e controle de execução do pipeline.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance;

CREATE TABLE IF NOT EXISTS governance.etl_batch_control (
    batch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_name VARCHAR(100) NOT NULL,
    source_file TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'running',
    raw_rows BIGINT,
    valid_rows BIGINT,
    rejected_rows BIGINT,
    error_message TEXT
);

-- Colunas adicionais para tornar o controle compatível com o bootstrap
-- e com a futura carga incremental.
ALTER TABLE governance.etl_batch_control
    ADD COLUMN IF NOT EXISTS load_type VARCHAR(20) NOT NULL DEFAULT 'bootstrap',
    ADD COLUMN IF NOT EXISTS fact_rows BIGINT,
    ADD COLUMN IF NOT EXISTS created_by TEXT NOT NULL DEFAULT CURRENT_USER;

-- Impede duas execuções simultâneas do mesmo pipeline.
CREATE UNIQUE INDEX IF NOT EXISTS uq_etl_batch_running_pipeline
    ON governance.etl_batch_control (pipeline_name)
    WHERE status = 'running';

CREATE INDEX IF NOT EXISTS ix_etl_batch_started_at
    ON governance.etl_batch_control (started_at DESC);

CREATE INDEX IF NOT EXISTS ix_etl_batch_status
    ON governance.etl_batch_control (status);