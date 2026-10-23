USE restaurants;

-- User
DESC `User`;
SELECT COUNT(*) AS row_count FROM `User`;
SELECT * FROM `User` LIMIT 3;

-- Vendor
DESC `Vendor`;
SELECT COUNT(*) AS row_count FROM `Vendor`;
SELECT * FROM `Vendor` LIMIT 3;

-- Cuisine
DESC `Cuisine`;
SELECT COUNT(*) AS row_count FROM `Cuisine`;
SELECT * FROM `Cuisine` LIMIT 3;

-- Location
DESC `Location`;
SELECT COUNT(*) AS row_count FROM `Location`;
SELECT * FROM `Location` LIMIT 3;

-- OperatingHours
DESC `OperatingHours`;
SELECT COUNT(*) AS row_count FROM `OperatingHours`;
SELECT * FROM `OperatingHours` LIMIT 3;

-- Review
DESC `Review`;
SELECT COUNT(*) AS row_count FROM `Review`;
SELECT * FROM `Review` LIMIT 3;

-- Photo
DESC `Photo`;
SELECT COUNT(*) AS row_count FROM `Photo`;
SELECT * FROM `Photo` LIMIT 3;

-- VendorCuisine
DESC `VendorCuisine`;
SELECT COUNT(*) AS row_count FROM `VendorCuisine`;
SELECT * FROM `VendorCuisine` LIMIT 3;

-- VendorBase
DESC `VendorBase`;
SELECT COUNT(*) AS row_count FROM `VendorBase`;
SELECT * FROM `VendorBase` LIMIT 3;

-- OperatingStop
DESC `OperatingStop`;
SELECT COUNT(*) AS row_count FROM `OperatingStop`;
SELECT * FROM `OperatingStop` LIMIT 3;

-- MenuItem
DESC `MenuItem`;
SELECT COUNT(*) AS row_count FROM `MenuItem`;
SELECT * FROM `MenuItem` LIMIT 3;

-- FoodPermit
DESC `FoodPermit`;
SELECT COUNT(*) AS row_count FROM `FoodPermit`;
SELECT * FROM `FoodPermit` LIMIT 3;

-- Manages
DESC `Manages`;
SELECT COUNT(*) AS row_count FROM `Manages`;
SELECT * FROM `Manages` LIMIT 3;

-- Favorites
DESC `Favorites`;
SELECT COUNT(*) AS row_count FROM `Favorites`;
SELECT * FROM `Favorites` LIMIT 3;

-- ReviewPhoto
DESC `ReviewPhoto`;
SELECT COUNT(*) AS row_count FROM `ReviewPhoto`;
SELECT * FROM `ReviewPhoto` LIMIT 3;

-- MenuItemPhoto
DESC `MenuItemPhoto`;
SELECT COUNT(*) AS row_count FROM `MenuItemPhoto`;
SELECT * FROM `MenuItemPhoto` LIMIT 3;

