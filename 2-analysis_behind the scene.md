Since the dataset size is relatively small, there is no need to perform extensive analysis directly in SQL. This avoids the overhead of creating multiple views and pivot tables in the database. Instead, the data can be efficiently handled in Excel using Power Pivot and Pivot Tables, which allow faster experimentation and full control within Excel.
This approach is well-suited for small to medium datasets. However, I created two SQL views as a backup option, in case real-time, on-the-go data access is required.

---

First, I wanted to get the top 10 most expensive cars. I noticed that one car name is shared between two companies. In a basic pivot table, this would return both, but I only wanted the higher price.

```
mistral
  bugatti   5000000
  nissan      25000
```

Instead of relying on the raw price column, I created a DAX measure to capture the maximum price per car name:

```DAX
max_price :=
VAR MaxPriceForCar =
    CALCULATE (
        MAX ( cars_datasets_2025[cars_prices] ),
        ALLEXCEPT ( cars_datasets_2025, cars_datasets_2025[cars_names] )
    )
RETURN
    IF (
        MAX ( cars_datasets_2025[cars_prices] ) = MaxPriceForCar,
        MaxPriceForCar
    )
```

---

For getting the bottom 10, I wanted to exclude rows where the price equals the sentinel value `-9`. I initially created this measure:

```DAX
min_price :=
IF (
    MAX ( cars_datasets_2025[cars_prices] ) <> -9,
    MAX ( cars_datasets_2025[cars_prices] )
)
```

Then I realized it would be simpler to avoid using DAX for such a minor issue and instead apply a filter in the pivot table to exclude `-9`. The drawback is that this approach will not automatically filter out the sentinel value from slicers later.

---
I wanted to categorize the cars based on price. To do this efficiently, I examined not only the maximum, minimum, and average prices, but also identified outliers. If an outlier was extremely far from the rest, I considered excluding it from the analysis. I performed this exploration using pivot tables, pivot charts, and normal tables, since pivot tables alone do not support box-and-whisker plots or scatter diagrams, which I used to visualize the distribution.

There was one very large outlier that would have caused the Equal‑Range method to place almost all cars into the first category. Given the variety of cars, companies, and price distribution, this did not make sense. I therefore excluded the outlier and used a modified maximum value instead. In the case of a dynamic dashboard that interacts with data regularly, I would rely on quartile calculations instead.

```DAX
VAR MinPrice =
    CALCULATE (
        MIN ( cars_datasets_2025[cars_prices] ),
        FILTER ( ALL ( cars_datasets_2025 ), cars_datasets_2025[cars_prices] <> -9 )
    )

VAR SecondMaxPrice =
    CALCULATE (
        MAX ( cars_datasets_2025[cars_prices] ),
        FILTER (
            ALL ( cars_datasets_2025 ),
            cars_datasets_2025[cars_prices] <> -9
                && cars_datasets_2025[cars_prices] <
                    CALCULATE (
                        MAX ( cars_datasets_2025[cars_prices] ),
                        FILTER ( ALL ( cars_datasets_2025 ), cars_datasets_2025[cars_prices] <> -9 )
                    )
        )
    )

VAR Step = DIVIDE ( SecondMaxPrice - MinPrice, 3 )
VAR Cut1 = MinPrice + Step
VAR Cut2 = MinPrice + ( 2 * Step )
VAR CurrentPrice = cars_datasets_2025[cars_prices]

RETURN
    IF (
        CurrentPrice = -9,
        BLANK (),
        SWITCH (
            TRUE (),
            CurrentPrice <= Cut1, "Economy",
            CurrentPrice <= Cut2, "Regular",
            "Luxury"
        )
    )
```

I found that the earlier approach still didn’t work, since most cars ended up in the first category with only a few marked as regular. It didn’t make sense to see a car costing a million classified as economy. Ideally, the client would provide clear cutoffs for categorization, also the groups of prices are fairly divergent.
Instead, I decided to simply sort the prices and create my own segmentation. I found it more practical to define five categories of prices, which better reflect the variety of cars, companies, and distribution patterns.

```DAX
VAR CurrentPrice = cars_datasets_2025[cars_prices]

RETURN
    IF (
        CurrentPrice = -9,
        BLANK (),
        SWITCH (
            TRUE (),
            CurrentPrice < 9500, "Ultra Economy",
            CurrentPrice < 18500, "Economy",
            CurrentPrice < 50000, "Regular",
            CurrentPrice < 90000, "Premium",
            CurrentPrice < 750000, "Luxury",
            "Super Luxury"
        )
    )
```

---

I wanted to see the correlation between horsepower and price to check if they follow the same trend. Since pivot tables don’t allow scatter plots or combo charts, I copied the pivot table output and pasted it into a regular table. This way, I could use scatter or other chart types to visualize the relationship directly.

---

I wanted to categorize cars into four categories based on seats, but I couldn’t directly convert the seat values into numeric form to simplify the calculated column. To work around this, I created the following DAX expression:

```DAX
VAR SeatText =
    SUBSTITUTE (
        SUBSTITUTE ( cars_datasets_2025[seats], "+", "" ),
        " ",
        ""
    )

VAR DashPos =
    FIND ( "-", SeatText & "-", 1 )

VAR FirstNumberText =
    LEFT ( SeatText, DashPos - 1 )

VAR FirstNumber =
    VALUE ( FirstNumberText )

RETURN
    SWITCH (
        TRUE (),
        FirstNumber <= 2, "Compact",
        FirstNumber <= 4, "Small",
        FirstNumber <= 7, "Family",
        "Van/Bus"
    )
```

---

I wanted to create a custom segmentation for cars, so I built the following DAX expression:

```DAX
VAR FirstChar = LEFT ( cars_datasets_2025[seats], 1 )
VAR FirstNumber = INT ( FirstChar )

RETURN
    SWITCH (
        TRUE (),
        INT ( cars_datasets_2025[cars_prices] ) > 50000 
            && INT ( cars_datasets_2025[horse_power] ) > 300, "Luxury Performance",

        INT ( cars_datasets_2025[cars_prices] ) < 20000 
            && cars_datasets_2025[fuel_types] = "Petrol", "Economic Compact",

        cars_datasets_2025[fuel_types] = "Electric", "Green Tech",

        FirstNumber >= 7 
            && cars_datasets_2025[torque_nm] > 400, "Family Utility",

        cars_datasets_2025[performance_0_100_kmh_sec] < 4, "Sports Car",

        "Other"
    )
```



||||||||||||||||||

I found two issues with the custom segmentation. Most sports cars were either being swallowed inside the *Luxury Performance* category or assigned to the sentinel `-9` value. To solve this, I moved the sports car condition to the top so it wouldn’t overlap, since most cars naturally fall into the luxury performance group.  

I also made the measure more readable by unifying the appropriate values into variables:

```DAX
VAR CurrentPrice = INT ( cars_datasets_2025[cars_prices] )
VAR CurrentHP = INT ( cars_datasets_2025[horse_power] )
VAR CurrentFuel = cars_datasets_2025[fuel_types]
VAR CurrentSeats = INT ( LEFT ( cars_datasets_2025[seats], 1 ) )
VAR CurrentTorque = cars_datasets_2025[torque_nm]
VAR CurrentPerf = cars_datasets_2025[performance_0_100_kmh_sec]

RETURN
    SWITCH (
        TRUE (),
        CurrentPerf < 4, "Sports Car",
        CurrentPrice > 50000 && CurrentHP > 300, "Luxury Performance",
        CurrentPrice < 20000 && CurrentFuel = "Petrol", "Economic Compact",
        CurrentFuel = "Electric", "Green Tech",
        CurrentSeats >= 7 && CurrentTorque > 400, "Family Utility",
        "Other"
    )
```

This way, the sports car classification is prioritized, and the logic is cleaner and easier to maintain.

---

During my exploration, I noticed that several fuel types had very small counts, which made charts harder to interpret. Since grouping is not allowed in pivot tables when data is added as a model, I created a modified column using DAX to handle this issue.

```DAX
FuelType_Grouped :=
VAR FuelCount =
    CALCULATE (
        COUNTROWS ( cars_datasets_2025 ),
        ALLEXCEPT ( cars_datasets_2025, cars_datasets_2025[fuel_types] )
    )
RETURN
    IF ( FuelCount < 10, "Others", cars_datasets_2025[fuel_types] )
```
