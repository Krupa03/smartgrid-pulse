# SmartGrid Pulse ⚡

A real-time IoT sensor monitoring platform that simulates an energy distribution grid — ingesting streaming sensor data, storing it in a time-series database, running automated anomaly detection via PL/pgSQL, and surfacing live KPIs through a Tableau dashboard.

Built to demonstrate production-grade database engineering using TimescaleDB hypertables, PL/pgSQL triggers, Python-based data ingestion, and time-series analytics at scale.

---

## Why this project?

Energy grids generate millions of sensor readings per day. This project models that environment to show how time-series data infrastructure is designed, built, and queried — from raw ingestion through to executive dashboards.

---

## Tech stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL 16 + TimescaleDB |
| Stored logic | PL/pgSQL (functions, triggers, procedures) |
| Data ingestion | Python 3.11 (psycopg2, pandas) |
| Sensor simulation | Python (synthetic time-series with injected anomalies) |
| Visualisation | Tableau Public |
| Schema management | SQL migration scripts |

---

## Architecture

```
Sensor Simulator (Python)
        │
        ▼
  Ingestion Layer (Python / psycopg2)
        │
        ▼
┌──────────────────────────────────────────┐
│          PostgreSQL + TimescaleDB         │
│                                          │
│  sensor_readings (hypertable)            │
│    └─ chunk interval: 1 hour             │
│    └─ retention policy: 90 days          │
│                                          │
│  PL/pgSQL                                │
│    └─ anomaly_check() trigger            │
│    └─ generate_hourly_summary() proc     │
│    └─ alert_log table                    │
│    └─ continuous aggregates              │
└──────────────────────────────────────────┘
        │
        ▼
  Tableau Dashboard (live PostgreSQL connection)
```

---

## Key features

**TimescaleDB hypertables**
- `sensor_readings` is a hypertable partitioned by time (1-hour chunks)
- Continuous aggregates auto-compute hourly averages
- Retention policy drops data older than 90 days automatically

**PL/pgSQL automation**
- `anomaly_check()` trigger fires on every INSERT — flags readings outside ±2σ of the rolling 1-hour mean
- `generate_hourly_summary()` aggregates readings into a `kpi_summary` table
- Alert log records anomalies with severity (warning / critical)

**Python ingestion**
- Simulator generates realistic waveform data (voltage, current, temperature) with injected anomalies
- Batch inserts via psycopg2 — configurable throughput (default: 100 readings/sec)
- Retry logic and connection pooling

**Tableau dashboard**
- Live connection to PostgreSQL
- Panels: real-time sensor status · anomaly timeline · hourly KPI trends · alert log
- Screenshots in `/tableau/screenshots/`

---

## Project structure

```
smartgrid-pulse/
├── sql/
│   ├── 01_schema.sql          # Table definitions + hypertable setup
│   ├── 02_functions.sql       # PL/pgSQL functions and triggers
│   ├── 03_aggregates.sql      # Continuous aggregates + retention policy
│   └── 04_seed_data.sql       # Sample sensor metadata
├── python/
│   ├── simulator.py           # Sensor data simulator
│   ├── ingestion.py           # Batch insert + connection handling
│   └── config.py              # DB connection config
├── tableau/
│   └── screenshots/           # Dashboard screenshots
├── requirements.txt
└── README.md
```

---

## Getting started

**Prerequisites:** PostgreSQL 15, TimescaleDB extension, Python 3.11+

```bash
# Clone the repo
git clone https://github.com/Krupa03/smartgrid-pulse.git
cd smartgrid-pulse

# Install Python dependencies
pip install -r requirements.txt

# Set up the database
psql -U postgres -c "CREATE DATABASE smartgrid;"
psql -U postgres -d smartgrid -f sql/01_schema.sql
psql -U postgres -d smartgrid -f sql/02_functions.sql
psql -U postgres -d smartgrid -f sql/03_aggregates.sql
psql -U postgres -d smartgrid -f sql/04_seed_data.sql

# Configure connection (edit python/config.py)
# Then start the simulator
python python/simulator.py
```

---

## Sample queries

```sql
-- Last 10 minutes of readings for a specific sensor
SELECT time, sensor_id, voltage, current, temperature
FROM sensor_readings
WHERE sensor_id = 'GRID-A-01'
  AND time > NOW() - INTERVAL '10 minutes'
ORDER BY time DESC;

-- Hourly average voltage per sensor (continuous aggregate)
SELECT bucket, sensor_id, avg_voltage
FROM sensor_hourly_summary
WHERE bucket > NOW() - INTERVAL '24 hours'
ORDER BY bucket DESC;

-- Recent anomalies
SELECT detected_at, sensor_id, metric, value, severity
FROM alert_log
WHERE detected_at > NOW() - INTERVAL '1 hour'
ORDER BY detected_at DESC;
```

---

## Status

🟡 **In progress** — schema and ingestion complete; PL/pgSQL triggers and Tableau dashboard in development.

---

## Author

**Krupa Ashoksinh Parmar** — Data Analyst | SQL · Python · PostgreSQL · TimescaleDB · Tableau · Power BI

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Krupa%20Parmar-0A66C2?style=flat&logo=linkedin)](https://linkedin.com/in/krupa-parmar-a7996210a)
[![GitHub](https://img.shields.io/badge/GitHub-Krupa03-181717?style=flat&logo=github)](https://github.com/Krupa03)
