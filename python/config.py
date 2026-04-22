# =============================================================
# SmartGrid Pulse | config.py
# Database connection settings
# =============================================================

DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "smartgrid",
    "user":     "postgres",
    "password": "your_password_here",   # change before running
}

# Simulator settings
SIMULATOR = {
    "batch_size":        100,    # readings per INSERT batch
    "interval_seconds":  1,      # seconds between batches
    "anomaly_rate":      0.02,   # 2% of readings will be anomalies
}

# Sensor IDs to simulate (must match sensors table)
SENSOR_IDS = [
    "GRID-A-01",
    "GRID-A-02",
    "GRID-B-01",
    "GRID-B-02",
    "GRID-C-01",
    "GRID-C-02",
]
