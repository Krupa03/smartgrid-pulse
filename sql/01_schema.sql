-- =============================================================
-- SmartGrid Pulse | 01_schema.sql
-- Database schema: sensors, readings hypertable, alert log
-- =============================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- -------------------------------------------------------------
-- Sensor registry: metadata for each grid sensor
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sensors (
    sensor_id       VARCHAR(20) PRIMARY KEY,
    location        VARCHAR(100) NOT NULL,
    grid_zone       VARCHAR(10)  NOT NULL,
    sensor_type     VARCHAR(50)  NOT NULL,
    installed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

-- -------------------------------------------------------------
-- Raw sensor readings (converted to hypertable below)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sensor_readings (
    time            TIMESTAMPTZ  NOT NULL,
    sensor_id       VARCHAR(20)  NOT NULL REFERENCES sensors(sensor_id),
    voltage         NUMERIC(8,3) NOT NULL,   -- Volts
    current         NUMERIC(8,3) NOT NULL,   -- Amps
    temperature     NUMERIC(6,2) NOT NULL,   -- Celsius
    power_factor    NUMERIC(4,3),            -- 0.0 - 1.0
    frequency       NUMERIC(5,2)             -- Hz
);

-- Convert to TimescaleDB hypertable partitioned by time (1-hour chunks)
SELECT create_hypertable(
    'sensor_readings',
    'time',
    chunk_time_interval => INTERVAL '1 hour',
    if_not_exists       => TRUE
);

-- Index for fast sensor-specific queries
CREATE INDEX IF NOT EXISTS idx_readings_sensor_time
    ON sensor_readings (sensor_id, time DESC);

-- -------------------------------------------------------------
-- Anomaly alert log
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alert_log (
    alert_id        BIGSERIAL    PRIMARY KEY,
    detected_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    sensor_id       VARCHAR(20)  NOT NULL REFERENCES sensors(sensor_id),
    metric          VARCHAR(20)  NOT NULL,   -- 'voltage','current','temperature'
    value           NUMERIC(10,3) NOT NULL,
    mean_1h         NUMERIC(10,3),           -- rolling 1-hour mean at alert time
    stddev_1h       NUMERIC(10,3),           -- rolling 1-hour stddev at alert time
    severity        VARCHAR(10)  NOT NULL    -- 'warning' | 'critical'
        CHECK (severity IN ('warning', 'critical')),
    resolved        BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_alert_sensor_time
    ON alert_log (sensor_id, detected_at DESC);

-- -------------------------------------------------------------
-- KPI summary table (populated by hourly procedure)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kpi_summary (
    bucket          TIMESTAMPTZ  NOT NULL,
    sensor_id       VARCHAR(20)  NOT NULL REFERENCES sensors(sensor_id),
    avg_voltage     NUMERIC(8,3),
    avg_current     NUMERIC(8,3),
    avg_temperature NUMERIC(6,2),
    avg_power_factor NUMERIC(4,3),
    reading_count   INTEGER,
    alert_count     INTEGER,
    PRIMARY KEY (bucket, sensor_id)
);
