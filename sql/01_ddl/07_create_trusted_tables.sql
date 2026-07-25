CREATE SCHEMA IF NOT EXISTS trusted;

CREATE TABLE trusted.dim_customer(
customer_key BIGSERIAL PRIMARY KEY,
customer_id VARCHAR(30) UNIQUE NOT NULL,
age INT,
gender VARCHAR(20),
education VARCHAR(50),
employment_type VARCHAR(50),
months_employed INT,
monthly_income DECIMAL(12,2),
marital_status VARCHAR(30),
dependents INT,
housing_status VARCHAR(50),
bank_relationship_months INT,
credit_history_months INT 
);

CREATE TABLE trusted.dim_location (
location_key BIGSERIAL PRIMARY KEY,
uf VARCHAR(2) UNIQUE NOT NULL,
region VARCHAR(20),
country VARCHAR(30)
);


CREATE TABLE trusted.dim_acquisition_channel (
channel_key BIGSERIAL PRIMARY KEY,
channel VARCHAR(50) UNIQUE NOT NULL,
channel_group VARCHAR(50)
);

CREATE TABLE trusted.dim_credit_profile_snapshot (
credit_profile_key BIGSERIAL PRIMARY KEY,
previous_loans INT,
previous_defaults INT,
bureau_inquiries_90d INT,
open_credit_lines INT,
credit_utilization DECIMAL(6,3),
delinquency_12m INT,
avg_payment_delay_days DECIMAL(12,2),
monthly_existing_debt DECIMAL(12,2),
debt_to_income DECIMAL(6,3)
);

CREATE TABLE trusted.dim_digital_risk_profile(
digital_risk_key BIGSERIAL PRIMARY KEY,
digital_behavior_score DECIMAL(5,2),
device_age_months INT,
email_age_months INT,
phone_verified BOOLEAN,
document_consistency BOOLEAN,
ip_risk_score DECIMAL(5,2)
);

CREATE TABLE trusted.dim_date (
date_key INT PRIMARY KEY,
full_date DATE UNIQUE NOT NULL,
day INT,
month INT,
month_name VARCHAR(20),
quarter INT,
year INT,
week_of_year INT,
day_of_week INT,
day_name VARCHAR(20),
is_weekend BOOLEAN
);

CREATE TABLE trusted.fact_credit_applications (
application_key BIGSERIAL PRIMARY KEY,
application_id VARCHAR(30) UNIQUE NOT NULL,

customer_key BIGINT NOT NULL, 
location_key BIGINT NOT NULL,
channel_key BIGINT NOT NULL,
credit_profile_key BIGINT NOT NULL,
digital_risk_key BIGINT NOT NULL,
date_key INT NOT NULL,

application_date DATE,
requested_amount DECIMAL(12,2),
loan_purpose VARCHAR(50),
term_months INT,
estimated_installment DECIMAL(12,2),
credit_score_internal INT,
risk_band CHAR(1),
approved BOOLEAN,
approved_amount DECIMAL(12,2),
interest_rate_monthly DECIMAL(6,4),
default_90d BOOLEAN,
fraud_confirmed BOOLEAN,

CONSTRAINT fk_customer
	FOREIGN KEY (customer_key)
	REFERENCES trusted.dim_customer(customer_key),

CONSTRAINT fk_location
	FOREIGN KEY (location_key)
	REFERENCES trusted.dim_location(location_key),

CONSTRAINT fk_channel
	FOREIGN KEY (channel_key)
	REFERENCES trusted.dim_acquisition_channel(channel_key),

CONSTRAINT fk_credit_profile
	FOREIGN KEY (credit_profile_key)
	REFERENCES trusted.dim_credit_profile_snapshot(credit_profile_key),

CONSTRAINT fk_digital_risk
	FOREIGN KEY (digital_risk_key)
	REFERENCES trusted.dim_digital_risk_profile(digital_risk_key),

CONSTRAINT fk_date
	FOREIGN KEY (date_key)
	REFERENCES trusted.dim_date(date_key)
);
