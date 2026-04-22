-- =============================================================
-- SmartGrid Pulse | 02_functions.sql
-- PL/pgSQL: anomaly detection trigger + summary procedure
-- =============================================================

-- -------------------------------------------------------------
-- Function: anomaly_check()
-- Fires on every INSERT into sensor_readings.
-- Compares the new reading against the rolling 1-hour mean
-- and stddev. Flags anything outside ±2σ as warning,
-- outside ±3σ as critical.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION anomaly_check()
RETURNS TRIGGER AS $$
DECLARE
    v_mean_voltage   NUMERIC;
    v_std_voltage    NUMERIC;
    v_mean_temp      NUMERIC;
    v_std_temp       NUMERIC;
    v_mean_current   NUMERIC;
    v_std_current    NUMERIC;
    v_severity       VARCHAR(10);
BEGIN
    -- Compute rolling stats for the past 1 hour for this sensor
    SELECT
        AVG(voltage),   STDDEV(voltage),
        AVG(current),   STDDEV(current),
        AVG(temperature), STDDEV(temperature)
    INTO
        v_mean_voltage,  v_std_voltage,
        v_mean_current,  v_std_current,
        v_mean_temp,     v_std_temp
    FROM sensor_readings
    WHERE sensor_id = NEW.sensor_id
      AND time > NEW.time - INTERVAL '1 hour';

    -- Skip check if fewer than 10 readings (not enough history)
    IF v_std_voltage IS NULL OR v_std_voltage = 0 THEN
        RETURN NEW;
    END IF;

    -- Check voltage
    IF ABS(NEW.voltage - v_mean_voltage) > 3 * v_std_voltage THEN
        v_severity := 'critical';
    ELSIF ABS(NEW.voltage - v_mean_voltage) > 2 * v_std_voltage THEN
        v_severity := 'warning';
    END IF;

    IF v_severity IS NOT NULL THEN
        INSERT INTO alert_log (sensor_id, metric, value, mean_1h, stddev_1h, severity)
        VALUES (NEW.sensor_id, 'voltage', NEW.voltage, v_mean_voltage, v_std_voltage, v_severity);
        v_severity := NULL;
    END IF;

    -- Check current
    IF v_std_current > 0 THEN
        IF ABS(NEW.current - v_mean_current) > 3 * v_std_current THEN
            v_severity := 'critical';
        ELSIF ABS(NEW.current - v_mean_current) > 2 * v_std_current THEN
            v_severity := 'warning';
        END IF;

        IF v_severity IS NOT NULL THEN
            INSERT INTO alert_log (sensor_id, metric, value, mean_1h, stddev_1h, severity)
            VALUES (NEW.sensor_id, 'current', NEW.current, v_mean_current, v_std_current, v_severity);
            v_severity := NULL;
        END IF;
    END IF;

    -- Check temperature
    IF v_std_temp > 0 THEN
        IF ABS(NEW.temperature - v_mean_temp) > 3 * v_std_temp THEN
            v_severity := 'critical';
        ELSIF ABS(NEW.temperature - v_mean_temp) > 2 * v_std_temp THEN
            v_severity := 'warning';
        END IF;

        IF v_severity IS NOT NULL THEN
            INSERT INTO alert_log (sensor_id, metric, value, mean_1h, stddev_1h, severity)
            VALUES (NEW.sensor_id, 'temperature', NEW.temperature, v_mean_temp, v_std_temp, v_severity);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to sensor_readings
DROP TRIGGER IF EXISTS trg_anomaly_check ON sensor_readings;
CREATE TRIGGER trg_anomaly_check
    AFTER INSERT ON sensor_readings
    FOR EACH ROW
    EXECUTE FUNCTION anomaly_check();


-- -------------------------------------------------------------
-- Procedure: generate_hourly_summary()
-- Aggregates the last completed hour of readings into kpi_summary.
-- Run this on a schedule (e.g. pg_cron every hour).
-- -------------------------------------------------------------
CREATE OR REPLACE PROCEDURE generate_hourly_summary()
LANGUAGE plpgsql AS $$
DECLARE
    v_bucket TIMESTAMPTZ := date_trunc('hour', NOW() - INTERVAL '1 hour');
BEGIN
    INSERT INTO kpi_summary (
        bucket, sensor_id,
        avg_voltage, avg_current, avg_temperature, avg_power_factor,
        reading_count, alert_count
    )
    SELECT
        v_bucket,
        r.sensor_id,
        ROUND(AVG(r.voltage)::NUMERIC,      3),
        ROUND(AVG(r.current)::NUMERIC,      3),
        ROUND(AVG(r.temperature)::NUMERIC,  2),
        ROUND(AVG(r.power_factor)::NUMERIC, 3),
        COUNT(*)                                AS reading_count,
        COALESCE(a.alert_count, 0)              AS alert_count
    FROM sensor_readings r
    LEFT JOIN (
        SELECT sensor_id, COUNT(*) AS alert_count
        FROM alert_log
        WHERE detected_at >= v_bucket
          AND detected_at <  v_bucket + INTERVAL '1 hour'
        GROUP BY sensor_id
    ) a ON a.sensor_id = r.sensor_id
    WHERE r.time >= v_bucket
      AND r.time <  v_bucket + INTERVAL '1 hour'
    GROUP BY r.sensor_id, a.alert_count
    ON CONFLICT (bucket, sensor_id) DO UPDATE SET
        avg_voltage      = EXCLUDED.avg_voltage,
        avg_current      = EXCLUDED.avg_current,
        avg_temperature  = EXCLUDED.avg_temperature,
        avg_power_factor = EXCLUDED.avg_power_factor,
        reading_count    = EXCLUDED.reading_count,
        alert_count      = EXCLUDED.alert_count;

    RAISE NOTICE 'KPI summary generated for bucket: %', v_bucket;
END;
$$;


-- -------------------------------------------------------------
-- Function: get_sensor_health(sensor_id, lookback_minutes)
-- Returns a quick health snapshot for a given sensor.
-- Useful for dashboard queries.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_sensor_health(
    p_sensor_id      VARCHAR(20),
    p_lookback_mins  INTEGER DEFAULT 60
)
RETURNS TABLE (
    sensor_id       VARCHAR(20),
    avg_voltage     NUMERIC,
    avg_current     NUMERIC,
    avg_temperature NUMERIC,
    reading_count   BIGINT,
    alert_count     BIGINT,
    last_reading_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.sensor_id,
        ROUND(AVG(r.voltage)::NUMERIC,      2) AS avg_voltage,
        ROUND(AVG(r.current)::NUMERIC,      2) AS avg_current,
        ROUND(AVG(r.temperature)::NUMERIC,  2) AS avg_temperature,
        COUNT(*)                                AS reading_count,
        (
            SELECT COUNT(*) FROM alert_log al
            WHERE al.sensor_id = p_sensor_id
              AND al.detected_at > NOW() - (p_lookback_mins || ' minutes')::INTERVAL
        )                                       AS alert_count,
        MAX(r.time)                             AS last_reading_at
    FROM sensor_readings r
    WHERE r.sensor_id = p_sensor_id
      AND r.time > NOW() - (p_lookback_mins || ' minutes')::INTERVAL
    GROUP BY r.sensor_id;
END;
$$ LANGUAGE plpgsql;
