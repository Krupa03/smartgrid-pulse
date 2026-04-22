# =============================================================
# SmartGrid Pulse | ingestion.py
# Handles batch inserts into PostgreSQL with retry logic
# and connection pooling via psycopg2.
# =============================================================

import time
import logging
import psycopg2
import psycopg2.extras
from psycopg2 import pool
from config import DB_CONFIG

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# Connection pool: 2–10 connections
_pool = None


def get_pool():
    global _pool
    if _pool is None:
        _pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=2,
            maxconn=10,
            **DB_CONFIG
        )
        logger.info("Connection pool initialised.")
    return _pool


INSERT_SQL = """
    INSERT INTO sensor_readings
        (time, sensor_id, voltage, current, temperature, power_factor, frequency)
    VALUES %s
    ON CONFLICT DO NOTHING
"""


def insert_batch(records: list[dict], retries: int = 3) -> int:
    """
    Insert a batch of sensor reading dicts into sensor_readings.
    Returns the number of rows successfully inserted.
    Retries up to `retries` times on transient failures.
    """
    if not records:
        return 0

    values = [
        (
            r["time"],
            r["sensor_id"],
            r["voltage"],
            r["current"],
            r["temperature"],
            r.get("power_factor"),
            r.get("frequency"),
        )
        for r in records
    ]

    pool = get_pool()
    conn = None

    for attempt in range(1, retries + 1):
        try:
            conn = pool.getconn()
            with conn.cursor() as cur:
                psycopg2.extras.execute_values(
                    cur, INSERT_SQL, values, page_size=500
                )
            conn.commit()
            return len(values)

        except psycopg2.OperationalError as e:
            logger.warning(f"DB error (attempt {attempt}/{retries}): {e}")
            if conn:
                conn.rollback()
            if attempt < retries:
                time.sleep(2 ** attempt)   # exponential backoff
            else:
                logger.error("Max retries reached. Batch dropped.")
                return 0

        finally:
            if conn:
                pool.putconn(conn)

    return 0


def fetch_recent_readings(sensor_id: str, minutes: int = 10) -> list[dict]:
    """
    Fetch recent readings for a sensor — useful for quick health checks.
    """
    sql = """
        SELECT time, sensor_id, voltage, current, temperature
        FROM sensor_readings
        WHERE sensor_id = %s
          AND time > NOW() - INTERVAL '%s minutes'
        ORDER BY time DESC
        LIMIT 100
    """
    pool  = get_pool()
    conn  = pool.getconn()
    rows  = []
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, (sensor_id, minutes))
            rows = [dict(r) for r in cur.fetchall()]
    finally:
        pool.putconn(conn)
    return rows


def fetch_active_alerts(limit: int = 20) -> list[dict]:
    """
    Fetch the most recent unresolved alerts across all sensors.
    """
    sql = """
        SELECT detected_at, sensor_id, metric, value, severity
        FROM alert_log
        WHERE resolved = FALSE
        ORDER BY detected_at DESC
        LIMIT %s
    """
    pool  = get_pool()
    conn  = pool.getconn()
    rows  = []
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, (limit,))
            rows = [dict(r) for r in cur.fetchall()]
    finally:
        pool.putconn(conn)
    return rows
