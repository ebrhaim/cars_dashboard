CREATE ALGORITHM = UNDEFINED DEFINER = `root`@`localhost` SQL SECURITY DEFINER VIEW `fuel_usage_by_company` AS
WITH `company_cars_count_cte` AS
(
	SELECT  `cars_datasets_2025`.`company_names`        AS `company_names`
	       ,COUNT(`cars_datasets_2025`.`company_names`) AS `company_cars_count`
	FROM `cars_datasets_2025`
	GROUP BY  `cars_datasets_2025`.`company_names`
)
SELECT  `cars_datasets_2025`.`company_names`                                                                           AS `company_names`
       ,`cars_datasets_2025`.`fuel_types`                                                                              AS `fuel_types`
       ,COUNT(`cars_datasets_2025`.`fuel_types`)                                                                       AS `fuel_usage_count`
       ,truncate(((COUNT(`cars_datasets_2025`.`fuel_types`) / `company_cars_count_cte`.`company_cars_count`) * 100),2) AS `fuel_usage_percentage`
FROM
(`cars_datasets_2025`
	JOIN `company_cars_count_cte` on
	((`cars_datasets_2025`.`company_names` = `company_cars_count_cte`.`company_names`)
	)
)
GROUP BY  `cars_datasets_2025`.`company_names`
         ,`cars_datasets_2025`.`fuel_types`
ORDER BY  `cars_datasets_2025`.`company_names`
         ,COUNT(`cars_datasets_2025`.`fuel_types`) desc