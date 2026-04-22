-- =============================================================
-- SmartGrid Pulse | 04_seed_data.sql
-- Sample sensor registry + 48 hours of synthetic readings
-- =============================================================

-- -------------------------------------------------------------
-- Sensor registry
-- -------------------------------------------------------------
INSERT INTO sensors (sensor_id, location, grid_zone, sensor_type) VALUES
    ('GRID-A-01', 'Substation Alpha - Panel 1',  'ZONE-A', 'three-phase-meter'),
    ('GRID-A-02', 'Substation Alpha - Panel 2',  'ZONE-A', 'three-phase-meter'),
    ('GRID-B-01', 'Substation Beta  - Panel 1',  'ZONE-B', 'three-phase-meter'),
    ('GRID-B-02', 'Substation Beta  - Panel 2',  'ZONE-B', 'single-phase-meter'),
    ('GRID-C-01', 'Distribution Hub - Feeder 1', 'ZONE-C', 'smart-meter'),
    ('GRID-C-02', 'Distribution Hub - Feeder 2', 'ZONE-C', 'smart-meter')
ON CONFLICT (sensor_id) DO NOTHING;

-- -------------------------------------------------------------
-- 48 hours of synthetic readings (one per minute per sensor)
-- Generates realistic waveforms with natural variation
-- and a few injected anomalies for testing alert detection
-- -------------------------------------------------------------
INSERT INTO sensor_readings (time, sensor_id, voltage, current, temperature, power_factor, frequency)
SELECT
    ts,
    s.sensor_id,

    -- Voltage: nominal 230V with ±5V natural drift + time-of-day load effect
    ROUND((
        230.0
        + 5.0  * SIN(EXTRACT(EPOCH FROM ts) / 3600.0)
        + 2.0  * SIN(EXTRACT(EPOCH FROM ts) / 900.0)
        + (RANDOM() - 0.5) * 2.0
        -- Inject voltage spike anomaly for GRID-A-01 every ~8 hours
        + CASE
            WHEN s.sensor_id = 'GRID-A-01'
             AND MOD(EXTRACT(EPOCH FROM ts)::BIGINT, 28800) BETWEEN 0 AND 59
            THEN 25.0
            ELSE 0
          END
    )::NUMERIC, 3),

    -- Current: 10–30A depending on time of day (peak 08:00–20:00)
    ROUND((
        15.0
        + 8.0  * SIN(EXTRACT(EPOCH FROM ts) / 43200.0 * PI())
        + (RANDOM() - 0.5) * 3.0
    )::NUMERIC, 3),

    -- Temperature: 35–55°C with ambient and load variation
    ROUND((
        40.0
        + 8.0  * SIN(EXTRACT(EPOCH FROM ts) / 43200.0 * PI())
        + (RANDOM() - 0.5) * 4.0
        -- Inject temperature anomaly for GRID-B-01 every ~12 hours
        + CASE
            WHEN s.sensor_id = 'GRID-B-01'
             AND MOD(EXTRACT(EPOCH FROM ts)::BIGINT, 43200) BETWEEN 0 AND 119
            THEN 18.0
            ELSE 0
          END
    )::NUMERIC, 2),

    -- Power factor: 0.85–0.98
    ROUND((0.90 + (RANDOM() - 0.5) * 0.10)::NUMERIC, 3),

    -- Frequency: 50Hz ±0.2Hz
    ROUND((50.0 + (RANDOM() - 0.5) * 0.4)::NUMERIC, 2)

FROM
    generate_series(
        NOW() - INTERVAL '48 hours',
        NOW(),
        INTERVAL '1 minute'
    ) AS ts,
    sensors s
WHERE s.is_active = TRUE;

-- Confirm row counts
SELECT
    sensor_id,
    COUNT(*)            AS readings_inserted,
    MIN(time)           AS earliest,
    MAX(time)           AS latest
FROM sensor_readings
GROUP BY sensor_id
ORDER BY sensor_id;
