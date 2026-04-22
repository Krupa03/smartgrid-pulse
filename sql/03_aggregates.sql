-- =============================================================
-- SmartGrid Pulse | 03_aggregates.sql
-- Continuous aggregates + data retention policy
-- =============================================================

-- -------------------------------------------------------------
-- Continuous aggregate: hourly averages per sensor
-- TimescaleDB auto-refreshes this as new data arrives.
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_hourly_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time)     AS bucket,
    sensor_id,
    ROUND(AVG(voltage)::NUMERIC,      3)  AS avg_voltage,
    ROUND(MIN(voltage)::NUMERIC,      3)  AS min_voltage,
    ROUND(MAX(voltage)::NUMERIC,      3)  AS max_voltage,
    ROUND(AVG(current)::NUMERIC,      3)  AS avg_current,
    ROUND(AVG(temperature)::NUMERIC,  2)  AS avg_temperature,
    ROUND(MAX(temperature)::NUMERIC,  2)  AS max_temperature,
    ROUND(AVG(power_factor)::NUMERIC, 3)  AS avg_power_factor,
    COUNT(*)                              AS reading_count
FROM sensor_readings
GROUP BY bucket, sensor_id
WITH NO DATA;

-- Refresh policy: keep the aggregate up to date automatically
SELECT add_continuous_aggregate_policy(
    'sensor_hourly_summary',
    start_offset => INTERVAL '3 hours',
    end_offset   => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- -------------------------------------------------------------
-- Continuous aggregate: daily summary per grid zone
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS zone_daily_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', r.time)        AS bucket,
    s.grid_zone,
    ROUND(AVG(r.voltage)::NUMERIC,      3)  AS avg_voltage,
    ROUND(AVG(r.current)::NUMERIC,      3)  AS avg_current,
    ROUND(AVG(r.temperature)::NUMERIC,  2)  AS avg_temperature,
    COUNT(*)                                AS reading_count,
    COUNT(DISTINCT r.sensor_id)             AS active_sensors
FROM sensor_readings r
JOIN sensors s ON s.sensor_id = r.sensor_id
GROUP BY bucket, s.grid_zone
WITH NO DATA;

SELECT add_continuous_aggregate_policy(
    'zone_daily_summary',
    start_offset => INTERVAL '3 days',
    end_offset   => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- -------------------------------------------------------------
-- Retention policy: drop raw readings older than 90 days
-- The continuous aggregates retain the summaries indefinitely.
-- -------------------------------------------------------------
SELECT add_retention_policy(
    'sensor_readings',
    INTERVAL '90 days',
    if_not_exists => TRUE
);

-- -------------------------------------------------------------
-- Useful diagnostic queries (run manually as needed)
-- -------------------------------------------------------------

-- Check chunk intervals and sizes
-- SELECT * FROM timescaledb_information.chunks
-- WHERE hypertable_name = 'sensor_readings'
-- ORDER BY range_start DESC LIMIT 10;

-- Check continuous aggregate refresh jobs
-- SELECT * FROM timescaledb_information.jobs
-- WHERE application_name LIKE '%Continuous%';

-- Manually trigger a full refresh if needed
-- CALL refresh_continuous_aggregate('sensor_hourly_summary', NULL, NULL);
