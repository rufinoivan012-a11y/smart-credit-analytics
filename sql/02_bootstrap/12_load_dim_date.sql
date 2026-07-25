INSERT INTO trusted.dim_date (
    date_key,
    full_date,
    day,
    month,
    month_name,
    quarter,
    year,
    week_of_year,
    day_of_week,
    day_name,
    is_weekend
)
SELECT
    TO_CHAR(d::DATE, 'YYYYMMDD')::INT AS date_key,
    d::DATE AS full_date,
    EXTRACT(DAY FROM d)::INT AS day,
    EXTRACT(MONTH FROM d)::INT AS month,
    TO_CHAR(d, 'FMMonth') AS month_name,
    EXTRACT(QUARTER FROM d)::INT AS quarter,
    EXTRACT(YEAR FROM d)::INT AS year,
    EXTRACT(WEEK FROM d)::INT AS week_of_year,
    EXTRACT(ISODOW FROM d)::INT AS day_of_week,
    TO_CHAR(d, 'FMDay') AS day_name,
    EXTRACT(ISODOW FROM d)::INT IN (6, 7) AS is_weekend
FROM GENERATE_SERIES(
    (SELECT MIN(application_date) FROM staging.stg_credit_applications),
    (SELECT MAX(application_date) FROM staging.stg_credit_applications),
    INTERVAL '1 day'
) AS g(d)
ON CONFLICT (date_key) DO UPDATE
SET
    full_date = EXCLUDED.full_date,
    day = EXCLUDED.day,
    month = EXCLUDED.month,
    month_name = EXCLUDED.month_name,
    quarter = EXCLUDED.quarter,
    year = EXCLUDED.year,
    week_of_year = EXCLUDED.week_of_year,
    day_of_week = EXCLUDED.day_of_week,
    day_name = EXCLUDED.day_name,
    is_weekend = EXCLUDED.is_weekend;
