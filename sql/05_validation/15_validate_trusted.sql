-- 1. Contagens principais
SELECT
    (SELECT COUNT(*) FROM staging.stg_credit_applications) AS staging_rows,
    (SELECT COUNT(*) FROM trusted.fact_credit_applications) AS fact_rows,
    (SELECT COUNT(*) FROM trusted.dim_customer) AS customers,
    (SELECT COUNT(*) FROM trusted.dim_location) AS locations,
    (SELECT COUNT(*) FROM trusted.dim_acquisition_channel) AS channels,
    (SELECT COUNT(*) FROM trusted.dim_credit_profile_snapshot) AS credit_profiles,
    (SELECT COUNT(*) FROM trusted.dim_digital_risk_profile) AS digital_profiles,
    (SELECT COUNT(*) FROM trusted.dim_date) AS calendar_days;

-- 2. Falha se a quantidade da fato não corresponder à staging válida
DO $$
DECLARE
    v_staging BIGINT;
    v_fact BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_staging FROM staging.stg_credit_applications;
    SELECT COUNT(*) INTO v_fact FROM trusted.fact_credit_applications;

    IF v_staging <> v_fact THEN
        RAISE EXCEPTION
            'Falha na carga da fato: staging=%, fact=%',
            v_staging, v_fact;
    END IF;
END;
$$;

-- 3. Duplicidade da chave de negócio na fato
SELECT application_id, COUNT(*) AS occurrences
FROM trusted.fact_credit_applications
GROUP BY application_id
HAVING COUNT(*) > 1;

-- 4. Integridade referencial explícita
SELECT COUNT(*) AS orphan_customer
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_customer d ON d.customer_key = f.customer_key
WHERE d.customer_key IS NULL;

SELECT COUNT(*) AS orphan_location
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_location d ON d.location_key = f.location_key
WHERE d.location_key IS NULL;

SELECT COUNT(*) AS orphan_channel
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_acquisition_channel d ON d.channel_key = f.channel_key
WHERE d.channel_key IS NULL;

SELECT COUNT(*) AS orphan_credit_profile
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_credit_profile_snapshot d
    ON d.credit_profile_key = f.credit_profile_key
WHERE d.credit_profile_key IS NULL;

SELECT COUNT(*) AS orphan_digital_profile
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_digital_risk_profile d
    ON d.digital_risk_key = f.digital_risk_key
WHERE d.digital_risk_key IS NULL;

SELECT COUNT(*) AS orphan_date
FROM trusted.fact_credit_applications f
LEFT JOIN trusted.dim_date d ON d.date_key = f.date_key
WHERE d.date_key IS NULL;

-- 5. Regras críticas da fato
SELECT
    COUNT(*) FILTER (WHERE requested_amount <= 0) AS invalid_requested_amount,
    COUNT(*) FILTER (WHERE approved_amount > requested_amount) AS invalid_approved_amount,
    COUNT(*) FILTER (WHERE risk_band NOT IN ('A', 'B', 'C', 'D', 'E')) AS invalid_risk_band,
    COUNT(*) FILTER (WHERE credit_score_internal NOT BETWEEN 250 AND 950) AS invalid_score,
    COUNT(*) FILTER (WHERE date_key <> TO_CHAR(application_date, 'YYYYMMDD')::INT) AS invalid_date_key
FROM trusted.fact_credit_applications;

-- 6. Amostra da fato com dimensões
SELECT
    f.application_id,
    f.application_date,
    c.customer_id,
    l.uf,
    ch.channel,
    f.requested_amount,
    f.approved,
    f.default_90d,
    f.fraud_confirmed
FROM trusted.fact_credit_applications f
JOIN trusted.dim_customer c ON c.customer_key = f.customer_key
JOIN trusted.dim_location l ON l.location_key = f.location_key
JOIN trusted.dim_acquisition_channel ch ON ch.channel_key = f.channel_key
ORDER BY f.application_date, f.application_id
LIMIT 10;
