NOTE
### SQL vs. Excel
Anything achievable in SQL can also be accomplished in Excel. However, the choice depends on several factors like:
- Client needs and preferences  
- Size of the dataset  
- Complexity of the data..

### Cleaning Method Used
For this dataset, the cleaning process was performed using SQL (specifically MySQL) within the phpMyAdmin interface.

---

-- Lowercase and trim all relevant columns

```sql
UPDATE cars_datasets_2025
SET
  company_names = TRIM(LOWER(company_names)),
  cars_names = TRIM(LOWER(cars_names)),
 ...;
```

---

-- Remove unnecessary symbols from each column, such as `$`, `,`, `km/h`...

```sql
UPDATE cars_datasets_2025
SET
  cars_prices = REPLACE(REPLACE(cars_prices, ',', ''), '$', ''),
  cc_battery_capacity = REPLACE(cc_battery_capacity, ',', ''),
  torque_nm = REPLACE(torque_nm, ',', ''),
  ...;
```

---

another trimming.. .

---

next, some changes in table names to unify their format:  
- all names should be lowercase  
- `horsepower` → `horse_power`  
- `totalspeed` → `total_speed`  
- remove spaces in `performance..`  
- add `sec` in `torque` for clarity, since people familiar with cars may not know it is measured in nm. After deleting `nm` from that column, update the table name to `torque_nm`  
- apply trimming on both sides  

these changes ensure a unified table name structure and improve data understandability after removing measurement units from the columns.

```sql
ALTER TABLE cars_datasets_2025
  CHANGE company_names company_names VARCHAR(255),
  CHANGE cars_names cars_names VARCHAR(255),
  ...;
```

---

see if there are any exact duplicates (rows where all values are identical, not just some cells)  

```sql
SELECT * 
FROM cars_datasets_2025 
GROUP BY company_names, cars_names, engines, cc_battery_capacity, horse_power, total_speed, performance_0_100_kmh_sec, cars_prices, fuel_types, seats, torque_nm 
HAVING COUNT(*) > 1;
```

note: if there is a primary key, use `ANY_VALUE(id)` alongside the selection (with explicit table names if needed) as a workaround, otherwise an error will be generated.

to handle mirrored duplicates, the simplest way is to first add a primary key id (if it does not already exist). this allows inline editing in phpMyAdmin or selecting rows by their ids.
however, if there are many duplicates, inline deletion becomes inefficient. in that case, after adding the primary key, use a query like this to delete duplicates while keeping one instance:

```sql
ALTER TABLE cars_datasets_2025 
ADD id INT AUTO_INCREMENT PRIMARY KEY FIRST;
```

note that this code will lead to an error because you cannot delete (or update) from the same query you are selecting with `DELETE FROM cars_datasets_2025 WHERE id NOT IN (SELECT MIN(id) ...)`.  

instead, the workaround is to nest two `SELECT` statements, like this:

```sql
DELETE FROM cars_datasets_2025
WHERE id NOT IN (
  SELECT id FROM (
    SELECT MIN(id) AS id
    FROM cars_datasets_2025
    GROUP BY
      company_names, cars_names, engines, cc_battery_capacity,
      horse_power, total_speed, performance_0_100_kmh_sec,
      cars_prices, fuel_types, seats, torque_nm
  ) AS safe_ids
);
```

---

after splitting the prices it will be meaningless to have typically the same car duplicated with differnet prices so
check if there is a duplicates in prices for the same car (technically: same rows except for the price) 

```sql
SELECT company_names, cars_names, engines, cc_battery_capacity, 
       horse_power, total_speed, performance_0_100_kmh_sec, 
       fuel_types, seats, torque_nm, COUNT(*) AS duplicate_count
FROM cars_datasets_2025
GROUP BY company_names, cars_names, engines, cc_battery_capacity, 
         horse_power, total_speed, performance_0_100_kmh_sec, 
         fuel_types, seats, torque_nm
HAVING COUNT(*) > 1
ORDER BY cars_datasets_2025.cars_names ASC;
```  

for more clearence:

```sql
SELECT *
FROM cars_datasets_2025
WHERE (company_names, cars_names, engines, cc_battery_capacity,
       horse_power, total_speed, performance_0_100_kmh_sec, fuel_types,
      seats, torque_nm)
       IN (
    SELECT company_names, cars_names, engines, cc_battery_capacity, horse_power, total_speed, performance_0_100_kmh_sec, fuel_types, seats, torque_nm
    FROM cars_datasets_2025 
    GROUP BY company_names, cars_names, engines, cc_battery_capacity, horse_power, total_speed, performance_0_100_kmh_sec, fuel_types, seats, torque_nm
    HAVING COUNT(*) > 1
)
ORDER BY cars_names, cars_prices;
```

so now we can
* Groups records by all vehicle attributes except `cars_prices`.
* Filters groups that contain more than one distinct price.
* Returns full records for those duplicated vehicle configurations.
* Orders results by car name and price for clear comparison.

---

so to handle this, I preferred to calculate the average price within each duplicated group (or, if the client prefers, use the higher price instead of averaging). this way, we consolidate duplicates into a single row.  

first, the update process:  

```sql
UPDATE cars_datasets_2025 t
JOIN (
    SELECT company_names,
           cars_names, engines, cc_battery_capacity,
           horse_power, total_speed, performance_0_100_kmh_sec,
           fuel_types, seats, torque_nm,
           AVG(cars_prices) AS avg_price
    FROM cars_datasets_2025
    GROUP BY company_names,
             cars_names,  engines, cc_battery_capacity,  horse_power,
             total_speed, performance_0_100_kmh_sec, fuel_types, seats,  torque_nm
    HAVING COUNT(*) > 1
) g
ON t.company_names = g.company_names
AND t.cars_names = g.cars_names
AND t.engines = g.engines
AND t.cc_battery_capacity = g.cc_battery_capacity
AND t.horse_power = g.horse_power
AND t.total_speed = g.total_speed
AND t.performance_0_100_kmh_sec = g.performance_0_100_kmh_sec
AND t.fuel_types = g.fuel_types
AND t.seats = g.seats
AND t.torque_nm = g.torque_nm
SET t.cars_prices = g.avg_price;
```

---

then after making sure every duplicate group now has the same averaged price, I can delete one of the produced pure duplicates:  

```sql
DELETE t1
FROM cars_datasets_2025 t1
JOIN cars_datasets_2025 t2
  ON t1.company_names = t2.company_names
 AND t1.cars_names = t2.cars_names
 AND t1.engines = t2.engines
 AND t1.cc_battery_capacity = t2.cc_battery_capacity
 AND t1.horse_power = t2.horse_power
 AND t1.total_speed = t2.total_speed
 AND t1.performance_0_100_kmh_sec = t2.performance_0_100_kmh_sec
 AND t1.fuel_types = t2.fuel_types
 AND t1.seats = t2.seats
 AND t1.torque_nm = t2.torque_nm
 AND t1.id > t2.id;
```

---

moving on to the next step: **normalization**. this stage is critical, so I create a savepoint before starting. I ensure every correct transaction or operation up to this point is safely stored (either in a private GitHub repo or in a backup table). this way, if a false commitment occurs, I can roll back to the latest correct savepoint.  

throughout the cleaning process, I also update checkpoints to track progress and maintain a reliable rollback strategy. this ensures that normalization is done safely and systematically without risking data integrity.

---

now after deleting the pure duplicates, i can safely and without confusion move on to the normalization of rows, (primary key here is mandatory for ease the normalization logics)

i observed that some data contains / or - symbols, such as 145-146. in certain columns, these symbols represent two distinct values, while in others they serve as semantic markers. therefore, I prefer to treat columns where these symbols may indicate multiple values (for example, the price column) as delimiters and selectively split them. the second value after - or / can be placed in a new column, while the remaining attributes remain identical, since they often refer to the same company_names and possibly the same cars_names (sometimes even the same engine or nearly identical rows except for one column).

however, there is an important exception: in the seats column, a value like 2-2 does not indicate two separate cars. instead, it describes a single car configuration, meaning two seats in the front and decorative or uncomfortable rear seats. this distinction must be preserved during normalization.

selectively having a sharp look (to avoid committing wrong normalization as `/` or `-` might be semantic symbols) on each column separately that contains these characters and might act as delimiters. then, review their whole rows to see if they truly hold two values that could be split.  

```sql
SELECT *
FROM cars_datasets_2025
WHERE cars_names LIKE '%-%'
   OR cars_names LIKE '%/%';
```

after that selection, i found that this column is not usable for splitting, meaning all of its values are just one value and `/` or `-` are considered semantic.  

the same selection process should be applied to all other columns (except for `company_names`, since it is impossible for multiple companies to share identical values across all other cells. however, i still checked this column to ensure no human errors introduced multiple values).

i expected that the second value is matched with the other second value in the other cells (otherwise, if we suppose i contacted the client and he told me it's not necessarily like that, that will lead to a way more microscopic exploration and might require client recommendations and making a suited logic for comparing between the two values)


after the last selection, i specified the ids whose rows will be split, but only in the smallest possible grouping. this is because some rows contain almost all numeric columns with two values, others only one, and others just a single value. there is no fixed rule that can be applied universally — a logic that works fine for one stack may fail for another, leading to incorrect results. this is especially risky in non‑numeric columns like `engine`, where wrong normalization could produce invalid values such as `-v4`.
during exploring, i found that some data contains more than one `/`, and in some cases a name indicates both values but is typed as one, for example: `1.0l ecoboost / 1.5l`.

---

made a and specific tailored insert and update for thoese selections portion, making sure each taliored logic fit it's refered column precisly 

```sql
INSERT INTO cars_datasets_2025 (
  company_names, cars_names, engines, cc_battery_capacity,
  horse_power, total_speed, performance_0_100_kmh_sec,
  cars_prices, fuel_types, seats, torque_nm
)
SELECT
  company_names,
  cars_names,
  TRIM(SUBSTRING_INDEX(engines, '/', -1)),
  IF(cc_battery_capacity REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(cc_battery_capacity, IF(LOCATE('/', cc_battery_capacity), '/', '-'), -1)), cc_battery_capacity),
  IF(horse_power REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(horse_power, IF(LOCATE('/', horse_power), '/', '-'), -1)), horse_power),
  total_speed,
  IF(performance_0_100_kmh_sec REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(performance_0_100_kmh_sec, IF(LOCATE('/', performance_0_100_kmh_sec), '/', '-'), -1)), performance_0_100_kmh_sec),
  IF(cars_prices REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(cars_prices, IF(LOCATE('/', cars_prices), '/', '-'), -1)), cars_prices),
  IF(fuel_types REGEXP '[/|,|-]', TRIM(SUBSTRING_INDEX(fuel_types, IF(LOCATE(',', fuel_types), ',', IF(LOCATE('/', fuel_types), '/', '-')), -1)), fuel_types),
  seats,
  IF(torque_nm REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(torque_nm, IF(LOCATE('/', torque_nm), '/', '-'), -1)), torque_nm)
FROM cars_datasets_2025
WHERE engines LIKE '%/%';
```

same logic for update ..
```sql
UPDATE cars_datasets_2025
SET
  engines = TRIM(SUBSTRING_INDEX(engines, '/', 1)),
  cc_battery_capacity = IF(cc_battery_capacity REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(cc_battery_capacity, IF(LOCATE('/', cc_battery_capacity), '/', '-'), 1)), cc_battery_capacity),
  horse_power = IF(horse_power REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(horse_power, IF(LOCATE('/', horse_power), '/', '-'), 1)), horse_power),
  performance_0_100_kmh_sec = IF(performance_0_100_kmh_sec REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(performance_0_100_kmh_sec, IF(LOCATE('/', performance_0_100_kmh_sec), '/', '-'), 1)), performance_0_100_kmh_sec),
  cars_prices = IF(cars_prices REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(cars_prices, IF(LOCATE('/', cars_prices), '/', '-'), 1)), cars_prices),
  fuel_types = IF(fuel_types REGEXP '[/|,|-]', TRIM(SUBSTRING_INDEX(fuel_types, IF(LOCATE(',', fuel_types), ',', IF(LOCATE('/', fuel_types), '/', '-')), 1)), fuel_types),
  torque_nm = IF(torque_nm REGEXP '[/|-]', TRIM(SUBSTRING_INDEX(torque_nm, IF(LOCATE('/', torque_nm), '/', '-'), 1)), torque_nm)
WHERE engines LIKE '%/%';
```

---
then apply the same search, insert, and update (based on the searched result) logic for both symbols `-` and `/` separately, for each column individually, just like what I did above for the `engine` column.  

again, the reason for this approach is that there are no fixed or guaranteed rules or patterns to control all cases in one go. what seems correct for some rows might lead to wrong entries in others. handling the process in smaller portions column by column ensures more accuracy and avoids mis‑normalization.

---

general explanation of the logic regardless of its internal changes:  
i inserted the second value part into a new row (if any exists; if not, then the same single value is used for both rows).  
then the original row is updated by removing the second value part (if any; if not, it remains unchanged).  
this ensures that untouched columns such as `cars_names` or `company_names` are shared consistently across both rows.  

along the way i trim to make sure after edits and manipulation, they got trimmed for easy referencing

---

```sql
INSERT INTO cars_datasets_2025 (
  company_names, cars_names, engines, cc_battery_capacity,
  horse_power, total_speed, performance_0_100_kmh_sec,
  cars_prices, fuel_types, seats, torque_nm
)
SELECT
  company_names,
  cars_names,
  engines,
  TRIM(SUBSTRING_INDEX(cc_battery_capacity, '/', -1)),
  horse_power,
  total_speed,
  performance_0_100_kmh_sec,
  IF(cars_prices REGEXP '[-]', TRIM(SUBSTRING_INDEX(cars_prices, IF(LOCATE('-', cars_prices), '-', cars_prices), -1)), cars_prices),
  fuel_types,
  seats,
  torque_nm 
FROM cars_datasets_2025
WHERE cc_battery_capacity LIKE '%/%' 
  AND cc_battery_capacity != 'n/a';
```

```sql
UPDATE cars_datasets_2025
SET
  cc_battery_capacity = TRIM(SUBSTRING_INDEX(cc_battery_capacity, '/', 1)),
  cars_prices = IF(cars_prices REGEXP '[-]', TRIM(SUBSTRING_INDEX(cars_prices, IF(LOCATE('-', cars_prices), '-', cars_prices), 1)), cars_prices)
  -- apply the same selective update logic for other columns as needed
WHERE cc_battery_capacity LIKE '%/%' 
  AND cc_battery_capacity != 'n/a';
```  

this same pattern should be applied **separately for each column** and for each symbol (`/` and `-`), since no universal rule fits all cases.. .

now after normalizing rows,
recall the trimming and checking for pure duplicates one more time, since some of the data inserted after splitting might already exist separately.
this final sweep keeps the dataset clean and consistent before moving forward with further analysis or reporting.

Now moving on to the next stage of cleaning, which involves checking each column’s values by grouping them to identify and address misspellings, typos, unnecessary parentheses, unusual entries, and other inconsistencies.  
Before beginning this process, it is essential to create a checkpoint to ensure that, in the event of any errors during the upcoming steps, the previous work will not need to be repeated and so can be rolled back as a backup.

---------------------##################################################################

---

note that grouping by a column that has (almost) unique values is generally meaningless, since the number of unique values will typically approximate the number of rows. however, taking a quick glance at such groupings can still be useful, as it may help catch obvious typos or inconsistencies.  

example:  

```sql
SELECT * 
FROM cars_datasets_2025 
GROUP BY company_names 
ORDER BY company_names;
```  

this way, even though the grouping doesn’t provide strong aggregation insights, it can still highlight spelling errors or unusual entries that stand out visually.

---

I noticed that another important step in normalization, beyond correcting misspellings, is to **remove parentheses, colons, and dashes** when they are inconsistently applied. Some cells include these symbols while others with the same value do not, which can cause problems later in aggregation and searching during analysis.  

Cleaning these inconsistencies is also a good practice to **unify the way of typing** across the dataset. At the same time, care must be taken with symbols that are embedded directly between words without spacing.

Phase 1: Replace Symbols with a Space  
Replace `-`, `,`, `(`, and `)` with a single space, regardless of whether they are attached to words or surrounded by spaces. This ensures consistent separation.  

```sql
UPDATE cars_datasets_2025
SET
  cars_names = REPLACE(REPLACE(REPLACE(REPLACE(cars_names, '-', ' '), ',', ' '), '(', ' '), ')', ' '),
  engines = REPLACE(REPLACE(REPLACE(REPLACE(engines, '-', ' '), ',', ' '), '(', ' '), ')', ' '),
  cc_battery_capacity = REPLACE(REPLACE(REPLACE(REPLACE(cc_battery_capacity, '-', ' '), ',', ' '), '(', ' '), ')', ' '),
  fuel_types = REPLACE(REPLACE(REPLACE(REPLACE(fuel_types, '-', ' '), ',', ' '), '(', ' '), ')', ' ');
```

Phase 2: Trim and Detect Double Spaces
Now we trim leading/trailing spaces and check for any remaining double spaces between words—indicating leftover gaps from symbol removal.

```sql
UPDATE cars_datasets_2025
SET
  cars_names = TRIM(cars_names),
  engines = TRIM(engines),
  cc_battery_capacity = TRIM(cc_battery_capacity),
  fuel_types = TRIM(fuel_types);
```  

---

```sql
SELECT 
    id, cars_names, engines, cc_battery_capacity, fuel_types
FROM cars_datasets_2025
WHERE 
    cars_names LIKE '%  %'
    OR engines LIKE '%  %'
    OR cc_battery_capacity LIKE '%  %'
    OR fuel_types LIKE '%  %';
```

```sql
SELECT
  id,
  IF(company_names LIKE '%  %', company_names, '-') AS company_names,
  IF(cars_names LIKE '%  %', cars_names, '-') AS cars_names,
  IF(engines LIKE '%  %', engines, '-') AS engines,
  ...;
FROM cars_datasets_2025
WHERE
  company_names LIKE '%  %' OR
  cars_names LIKE '%  %' OR
  engines LIKE '%  %' OR
  ...;
```
```sql
UPDATE cars_datasets_2025
SET
  company_names = REPLACE(company_names, '  ', ' '),
  cars_names = REPLACE(cars_names, '  ', ' '),
  engines = REPLACE(engines, '  ', ' '),
  ...;
```

---

After that, group each column to identify typos or unnecessary words such as "estimated 1475" or "up to 320."  
For numeric-like columns, select cells containing letters to determine whether they can be removed or handled appropriately, ensuring the column is ready for numeric use.

```sql
SELECT cc_battery_capacity
FROM cars_datasets_2025
GROUP BY cc_battery_capacity
ORDER BY cc_battery_capacity;
```

```sql
SELECT *
FROM cars_datasets_2025
WHERE cc_battery_capacity REGEXP '[a-zA-Z]';
```

After searching for letters in numeric-like columns, I found that certain values cannot be directly converted into integers. For example, entries containing the abbreviation **kWh** represent battery capacity, while plain numbers without units indicate **cc** (engine displacement). To differentiate between the two: remove the most common format to standardize the column then retain the less common format (e.g., kWh) to preserve meaning and avoid misclassification.

In the columns horse_power, total_speed, performance_0_100_kmh_sec, torque_nm, and cars_prices, all values can be safely converted into numeric data types after handling nulls and null-like entries.

Some values contain words such as "electric." When selecting rows with letters, only a few were found. These can be removed to ensure the columns contain only numbers, unless the client considers those words insightful.

---

For handling `NULL`, `N/A`, blank, and `-` values, the approach depends on whether the row contributes meaningfully to analysis or aggregation, and on client recommendations:

- **Descriptive fields**  
  - Use terms like *Not Available*, *Missing*, or *Unknown* if the value could exist but was not captured.  
  - Use *Not Applicable* when the field genuinely does not apply (e.g., fuel type for electric-only models).  
  - Leave as `NULL` if downstream logic or reporting explicitly handles nulls.

- **Numeric fields**  
  - Apply **Outlier Sentinels** instead of 0 or negative placeholders.  
    - Choose extreme high values that are outside the valid range, easy to filter, and preserve numeric type for aggregation.  
  - Use `-1` only if the column can naturally hold negative values (e.g., net gain/loss).  
  - Use `NULL` if downstream logic explicitly accommodates nulls.

This ensures clarity in descriptive reporting while maintaining numeric integrity for calculations and aggregations.

sql```
UPDATE cars_datasets_2025
SET
 company_names = IF(company_names IN ('-', 'null', 'n/a', ''), 'missing', company_names ),
  cars_names = IF(cars_names IN ('-', 'null', 'n/a', ''), 'missing', cars_names),
  engines = IF(engines IN ('-', 'null', 'n/a', ''), 'missing', engines),
  ...;

 UPDATE cars_datasets_2025
SET
  horse_power = IF(horse_power IN ('-', 'null', 'n/a', ''), -9, horse_power),
  total_speed = IF(total_speed IN ('-', 'null', 'n/a', ''), -9, total_speed),
  performance_0_100_kmh_sec = IF(performance_0_100_kmh_sec IN ('-', 'null', 'n/a', ''), -9, performance_0_100_kmh_sec),
  cars_prices = IF(cars_prices IN ('-', 'null', 'n/a', ''), -9, cars_prices),
torque_na = IF(torque_na IN ('-', 'null', 'n/a', ''), -9, torque_nm)
```


confirm:
```sql
SELECT
  id,
  IF(company_names IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS company_names_status,
  IF(cars_names IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS cars_names_status,
  IF(engines IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS engines_status,
  IF(cc_battery_capacity IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS cc_battery_capacity_status,
  IF(horse_power IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS horse_power_status,
  IF(total_speed IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS total_speed_status,
  IF(performance_0_100_kmh_sec IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS performance_status,
  IF(cars_prices IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS cars_prices_status,
  IF(fuel_types IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS fuel_types_status,
  IF(seats IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS seats_status,
  IF(torque_nm IN ('-', 'null', 'n/a', ''), 'missing', 'exist') AS torque_nm_status
FROM cars_datasets_2025;
```

---

lastely covert the pure numaric into numeric data_type 

```sql
ALTER TABLE cars_datasets_2025
MODIFY horse_power DECIMAL(10,2) NULL DEFAULT NULL,
MODIFY total_speed DECIMAL(10,2) NULL DEFAULT NULL,
MODIFY performance_0_100_kmh_sec DECIMAL(10,2) NULL DEFAULT NULL,
MODIFY cars_prices DECIMAL(10,2) NULL DEFAULT NULL,
MODIFY torque_nm DECIMAL(10,2) NULL DEFAULT NULL;
```

---

now after making sure data is celan, moving on to further eda process:
selects all rows where any of the numeric fields hold -9 or any of the string fields hold 'missing'
This gives a full view of all rows where any field is flagged as missing, based on the sentinel values

```sql
SELECT *
FROM cars_datasets_2025
WHERE
  horse_power = -9
  OR total_speed = -9
  OR performance_0_100_kmh_sec = -9
  OR cars_prices = -9
  OR torque_nm = -9
  OR cars_names = 'missing'
  OR engines = 'missing'
  OR cc_battery_capacity = 'missing'
  OR fuel_types = 'missing'
  OR seats = 'missing';
```
