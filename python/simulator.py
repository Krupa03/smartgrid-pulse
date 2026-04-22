# =============================================================
# SmartGrid Pulse | simulator.py
# Generates synthetic IoT sensor readings and streams them
# to the ingestion layer in configurable batches.
# =============================================================

import time
import random
import math
from datetime import datetime, timezone
from ingestion import insert_batch
from config import SIMULATOR, SENSOR_IDS


def generate_reading(sensor_id: str, ts: datetime) -> dict:
    """
    Generate one synthetic sensor reading with realistic waveforms.
    Injects random anomalies at the configured rate.
    """
    epoch = ts.timestamp()
    is_anomaly = random.random() < SIMULATOR["anomaly_rate"]

    # Voltage: 230V nominal with sinusoidal load variation + noise
    voltage = (
        230.0
        + 5.0 * math.sin(epoch / 3600.0)
        + 2.0 * math.sin(epoch / 900.0)
        + random.gauss(0, 1.0)
    )
    if is_anomaly:
        voltage += random.choice([-30, 30])   # inject spike/sag

    # Current: 10–30A, peaks during daytime hours
    hour = ts.hour + ts.minute / 60.0
    day_factor = max(0, math.sin((hour - 6) / 24.0 * math.pi * 2))
    current = 10.0 + 20.0 * day_factor + random.gauss(0, 1.5)
    if is_anomaly:
        current += random.choice([-8, 8])

    # Temperature: 35–55°C following load curve
    temperature = 38.0 + 15.0 * day_factor + random.gauss(0, 2.0)
    if is_anomaly:
        temperature += random.choice([-10, 15])

    # Power factor: 0.85–0.98
    power_factor = max(0.80, min(1.0, random.gauss(0.92, 0.03)))

    # Frequency: 50Hz ±0.2Hz
    frequency = 50.0 + random.gauss(0, 0.08)

    return {
        "time":         ts.isoformat(),
        "sensor_id":    sensor_id,
        "voltage":      round(voltage, 3),
        "current":      round(max(0, current), 3),
        "temperature":  round(temperature, 2),
        "power_factor": round(power_factor, 3),
        "frequency":    round(frequency, 2),
    }


def run():
    """
    Main simulation loop.
    Generates readings for all sensors, batches them, and inserts.
    """
    batch_size = SIMULATOR["batch_size"]
    interval   = SIMULATOR["interval_seconds"]

    print(f"SmartGrid Pulse simulator started.")
    print(f"Sensors: {SENSOR_IDS}")
    print(f"Batch size: {batch_size} | Interval: {interval}s")
    print("-" * 50)

    total_inserted = 0

    try:
        while True:
            batch = []
            ts = datetime.now(timezone.utc)

            for sensor_id in SENSOR_IDS:
                for _ in range(batch_size // len(SENSOR_IDS)):
                    batch.append(generate_reading(sensor_id, ts))

            inserted = insert_batch(batch)
            total_inserted += inserted

            print(
                f"[{ts.strftime('%H:%M:%S')}] "
                f"Inserted {inserted} readings | "
                f"Total: {total_inserted:,}"
            )

            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\nSimulator stopped. Total readings inserted: {total_inserted:,}")


if __name__ == "__main__":
    run()
