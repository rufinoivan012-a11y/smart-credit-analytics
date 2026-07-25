BEGIN;

TRUNCATE TABLE trusted.fact_credit_applications RESTART IDENTITY;

INSERT INTO trusted.fact_credit_applications (
    application_id,
    customer_key,
    location_key,
    channel_key,
    credit_profile_key,
    digital_risk_key,
    date_key,
    application_date,
    requested_amount,
    loan_purpose,
    term_months,
    estimated_installment,
    credit_score_internal,
    risk_band,
    approved,
    approved_amount,
    interest_rate_monthly,
    default_90d,
    fraud_confirmed
)
SELECT
    s.application_id,
    c.customer_key,
    l.location_key,
    ch.channel_key,
    cp.credit_profile_key,
    dr.digital_risk_key,
    d.date_key,
    s.application_date,
    s.requested_amount,
    s.loan_purpose,
    s.term_months,
    s.estimated_installment,
    s.credit_score_internal,
    s.risk_band,
    s.approved,
    s.approved_amount,
    s.interest_rate_monthly,
    s.default_90d,
    s.fraud_confirmed
FROM staging.stg_credit_applications s
JOIN trusted.dim_customer c
    ON c.customer_id = s.customer_id
JOIN trusted.dim_location l
    ON l.uf = s.uf
JOIN trusted.dim_acquisition_channel ch
    ON ch.channel = s.channel
JOIN trusted.dim_credit_profile_snapshot cp
    ON cp.previous_loans IS NOT DISTINCT FROM s.previous_loans
   AND cp.previous_defaults IS NOT DISTINCT FROM s.previous_defaults
   AND cp.bureau_inquiries_90d IS NOT DISTINCT FROM s.bureau_inquiries_90d
   AND cp.open_credit_lines IS NOT DISTINCT FROM s.open_credit_lines
   AND cp.credit_utilization IS NOT DISTINCT FROM s.credit_utilization
   AND cp.delinquency_12m IS NOT DISTINCT FROM s.delinquency_12m
   AND cp.avg_payment_delay_days IS NOT DISTINCT FROM s.avg_payment_delay_days
   AND cp.monthly_existing_debt IS NOT DISTINCT FROM s.monthly_existing_debt
   AND cp.debt_to_income IS NOT DISTINCT FROM s.debt_to_income
JOIN trusted.dim_digital_risk_profile dr
    ON dr.digital_behavior_score IS NOT DISTINCT FROM s.digital_behavior_score
   AND dr.device_age_months IS NOT DISTINCT FROM s.device_age_months
   AND dr.email_age_months IS NOT DISTINCT FROM s.email_age_months
   AND dr.phone_verified IS NOT DISTINCT FROM s.phone_verified
   AND dr.document_consistency IS NOT DISTINCT FROM s.document_consistency
   AND dr.ip_risk_score IS NOT DISTINCT FROM s.ip_risk_score
JOIN trusted.dim_date d
    ON d.full_date = s.application_date;

COMMIT;
