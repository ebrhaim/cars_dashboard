-- View: cars_metrics_summary_flat
-- Purpose: Summarizes key numeric metrics (min, avg, max) across cleaned fields
-- Excludes rows with sentinel values (-9 for numerics, 'missing' for seats)

CREATE OR REPLACE VIEW cars_metrics_summary_flat AS

-- Horsepower stats
SELECT 'horse_power' AS metric,
       MIN(horse_power) AS min_val,
       ROUND(AVG(horse_power), 2) AS avg_val,
       MAX(horse_power) AS max_val
FROM cars_datasets_2025
WHERE horse_power <> -9 AND seats <> 'missing'

UNION ALL

-- Total speed stats
SELECT 'total_speed',
       MIN(total_speed),
       ROUND(AVG(total_speed), 2),
       MAX(total_speed)
FROM cars_datasets_2025
WHERE total_speed <> -9 AND seats <> 'missing'

UNION ALL

-- 0–100 km/h performance stats
SELECT 'performance_0_100_kmh_sec',
       MIN(performance_0_100_kmh_sec),
       ROUND(AVG(performance_0_100_kmh_sec), 2),
       MAX(performance_0_100_kmh_sec)
FROM cars_datasets_2025
WHERE performance_0_100_kmh_sec <> -9 AND seats <> 'missing'

UNION ALL

-- Price stats
SELECT 'cars_prices',
       MIN(cars_prices),
       ROUND(AVG(cars_prices), 2),
       MAX(cars_prices)
FROM cars_datasets_2025
WHERE cars_prices <> -9 AND seats <> 'missing'

UNION ALL

-- Torque stats
SELECT 'torque_nm',
       MIN(torque_nm),
       ROUND(AVG(torque_nm), 2),
       MAX(torque_nm)
FROM cars_datasets_2025
WHERE torque_nm <> -9 AND seats <> 'missing';
