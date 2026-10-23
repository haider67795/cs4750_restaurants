USE restaurants;

-- Query 1
SELECT vendor_id, name, vendor_type FROM Vendor ORDER BY name;

-- Query 2
SELECT vendor_id, name FROM Vendor
WHERE name LIKE '%pizza%' OR description LIKE '%pizza%';

-- Query 3
SELECT v.vendor_id, v.name
FROM Vendor v
JOIN VendorCuisine vc ON vc.vendor_id = v.vendor_id
JOIN Cuisine c ON c.cuisine_id = vc.cuisine_id
WHERE c.cuisine_name = 'Italian';

-- Query 4
SELECT vendor_id, name FROM Vendor
WHERE vendor_id IN (
    SELECT vb.vendor_id FROM VendorBase vb
    JOIN Location l ON l.location_id = vb.location_id
    WHERE l.city = 'Alexandria'
    UNION
    SELECT s.vendor_id FROM OperatingStop s
    JOIN Location l ON l.location_id = s.location_id
    WHERE l.city = 'Alexandria' AND s.scheduled_end >= UTC_TIMESTAMP()
      AND s.stop_status NOT IN ('cancelled', 'demo_cancelled')
);

-- Query 5
SELECT vendor_id, name FROM Vendor WHERE vendor_type = 'food_truck';

-- Query 6
SELECT v.vendor_id, v.name, ROUND(AVG(r.rating), 2) AS average_rating,
       COUNT(r.review_id) AS review_count
FROM Vendor v
LEFT JOIN Review r ON r.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.name
ORDER BY average_rating DESC;

-- Query 7
SELECT v.vendor_id, v.name, l.location_name,
       ST_Distance_Sphere(POINT(l.longitude, l.latitude),
                          POINT(-78.476678, 38.029306)) / 1000 AS distance_km
FROM Vendor v
JOIN (
    SELECT vendor_id, location_id FROM VendorBase
    UNION
    SELECT vendor_id, location_id FROM OperatingStop
    WHERE scheduled_start <= UTC_TIMESTAMP() AND scheduled_end > UTC_TIMESTAMP()
      AND stop_status NOT IN ('cancelled', 'demo_cancelled')
) locations ON locations.vendor_id = v.vendor_id
JOIN Location l ON l.location_id = locations.location_id
ORDER BY distance_km;

-- Query 8
SELECT v.*, l.street_address, l.city, l.state, l.postal_code
FROM Vendor v
LEFT JOIN VendorBase vb ON vb.vendor_id = v.vendor_id
LEFT JOIN Location l ON l.location_id = vb.location_id
WHERE v.vendor_id = 1;

-- Query 9
SELECT c.cuisine_name FROM Cuisine c
JOIN VendorCuisine vc ON vc.cuisine_id = c.cuisine_id
WHERE vc.vendor_id = 1;

-- Query 10
SELECT menu_item_id, item_name, description, price, category, availability_status
FROM MenuItem WHERE vendor_id = 1 ORDER BY price;

-- Query 11
SELECT m.item_name, p.image_url, p.caption
FROM MenuItem m
JOIN MenuItemPhoto mp ON mp.menu_item_id = m.menu_item_id
JOIN Photo p ON p.photo_id = mp.photo_id
WHERE m.vendor_id = 1;

-- Query 12
SELECT day_of_week, opening_time, closing_time
FROM OperatingHours WHERE vendor_id = 1
ORDER BY day_of_week, opening_time;

-- Query 13
SELECT s.*, l.location_name, l.city, l.latitude, l.longitude
FROM OperatingStop s
JOIN Location l ON l.location_id = s.location_id
WHERE s.vendor_id = 1 ORDER BY s.scheduled_start;

-- Query 14
SELECT r.review_id, u.display_name, r.rating, r.review_text, r.created_at
FROM Review r
JOIN User u ON u.user_id = r.author_user_id
WHERE r.vendor_id = 1 ORDER BY r.created_at DESC;

-- Query 15
SELECT rp.review_id, p.image_url, p.caption
FROM ReviewPhoto rp
JOIN Review r ON r.review_id = rp.review_id
JOIN Photo p ON p.photo_id = rp.photo_id
WHERE r.vendor_id = 1;

-- Query 16
SELECT * FROM FoodPermit WHERE vendor_id = 1;

-- Query 17
SELECT v.vendor_id, v.name, f.saved_at
FROM Favorites f JOIN Vendor v ON v.vendor_id = f.vendor_id
WHERE f.user_id = 13947;

-- Query 18
SELECT user_id, display_name, email, joined_at FROM User WHERE user_id = 13947;

-- Query 19
SELECT r.review_id, v.name, r.rating, r.review_text
FROM Review r JOIN Vendor v ON v.vendor_id = r.vendor_id
WHERE r.author_user_id = 13947;

-- Query 20
SELECT v.vendor_id, v.name, m.management_role
FROM Manages m JOIN Vendor v ON v.vendor_id = m.vendor_id
WHERE m.user_id = 13866;

-- Query 21
SELECT user_id, display_name, password_hash FROM User
WHERE email = 'demo.customer.001@example.invalid'
  AND password_hash NOT LIKE '!IMPORTED_NO_LOGIN!%';

-- Query 22
SELECT r.review_id, r.rating, r.review_text, r.created_at
FROM Review r JOIN Manages m ON m.vendor_id = r.vendor_id
WHERE r.vendor_id = 1 AND m.user_id = 13866;

-- Query 23
SELECT v.* FROM Vendor v JOIN Manages m ON m.vendor_id = v.vendor_id
WHERE v.vendor_id = 1 AND m.user_id = 13866;

-- Query 24
SELECT s.* FROM OperatingStop s JOIN Manages m ON m.vendor_id = s.vendor_id
WHERE s.vendor_id = 1 AND m.user_id = 13866;

START TRANSACTION;

-- Query 25
INSERT INTO User (display_name, email, password_hash, joined_at)
VALUES ('Query Demo User', CONCAT('query-demo-', UUID(), '@example.invalid'),
        '$2y$10$OrsTj3NedJZ8oeMzYVdt2O8aZZW901CYshgDr75b2VBFGrtlBjzXS', UTC_TIMESTAMP());
SET @new_user_id = LAST_INSERT_ID();

-- Query 26
UPDATE User SET display_name = 'Updated Query Demo User' WHERE user_id = @new_user_id;

-- Query 27
INSERT INTO Vendor (name, description, vendor_type, phone_number, website_url,
                    listing_status, created_at, timezone, submitted_by_user_id)
VALUES ('[DEMO] Query Practice Vendor', 'Disposable SQL learning example', 'food_truck',
        NULL, NULL, 'demo', UTC_TIMESTAMP(), 'America/New_York', @new_user_id);
SET @new_vendor_id = LAST_INSERT_ID();

-- Query 28
INSERT INTO Manages (user_id, vendor_id, management_role, granted_at)
VALUES (@new_user_id, @new_vendor_id, 'demo_owner', UTC_TIMESTAMP());

-- Query 29
INSERT INTO Location (location_name, street_address, city, state, postal_code, latitude, longitude)
VALUES ('[DEMO] Practice Stop', NULL, 'Charlottesville', 'VA', NULL, 38.029306, -78.476678);
SET @new_location_id = LAST_INSERT_ID();
INSERT INTO VendorBase (vendor_id, location_id) VALUES (@new_vendor_id, @new_location_id);

-- Query 30
SET @existing_cuisine_id = (SELECT cuisine_id FROM Cuisine ORDER BY cuisine_id LIMIT 1);
INSERT INTO VendorCuisine (vendor_id, cuisine_id) VALUES (@new_vendor_id, @existing_cuisine_id);

-- Query 31
INSERT INTO OperatingHours (vendor_id, hours_number, day_of_week, opening_time, closing_time)
VALUES (@new_vendor_id, 1, 'Monday', '11:00:00', '19:00:00');

-- Query 32
INSERT INTO OperatingStop (vendor_id, location_id, scheduled_start, scheduled_end,
                          actual_start, actual_end, stop_status, notes)
SELECT @new_vendor_id, @new_location_id, UTC_TIMESTAMP() + INTERVAL 1 DAY,
       UTC_TIMESTAMP() + INTERVAL 1 DAY + INTERVAL 4 HOUR,
       NULL, NULL, 'demo_scheduled', '[DEMO] Query practice stop'
WHERE EXISTS (SELECT 1 FROM Manages WHERE vendor_id = @new_vendor_id AND user_id = @new_user_id);
SET @new_stop_id = LAST_INSERT_ID();
UPDATE OperatingStop s
SET s.notes = '[DEMO] Updated practice stop'
WHERE s.stop_id = @new_stop_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = s.vendor_id AND m.user_id = @new_user_id);

UPDATE OperatingStop s
SET s.location_id = @new_location_id,
    s.scheduled_start = UTC_TIMESTAMP() + INTERVAL 2 DAY,
    s.scheduled_end = UTC_TIMESTAMP() + INTERVAL 2 DAY + INTERVAL 4 HOUR
WHERE s.stop_id = @new_stop_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = s.vendor_id AND m.user_id = @new_user_id);

UPDATE OperatingHours h SET h.opening_time = '12:00:00', h.closing_time = '20:00:00'
WHERE h.vendor_id = @new_vendor_id AND h.hours_number = 1
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = h.vendor_id AND m.user_id = @new_user_id);

UPDATE OperatingStop s
SET s.actual_start = s.scheduled_start, s.actual_end = s.scheduled_end,
    s.stop_status = 'demo_completed'
WHERE s.stop_id = @new_stop_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = s.vendor_id AND m.user_id = @new_user_id);

-- Query 33
INSERT INTO MenuItem (vendor_id, item_name, description, price, category, availability_status)
SELECT @new_vendor_id, '[DEMO] Practice Dish', 'Disposable learning example', 10.00, 'Demo', 'demo_available'
WHERE EXISTS (SELECT 1 FROM Manages WHERE vendor_id = @new_vendor_id AND user_id = @new_user_id);
SET @new_item_id = LAST_INSERT_ID();
UPDATE MenuItem mi SET mi.price = 11.50
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);

-- Query 34
UPDATE Vendor v SET v.description = '[DEMO] Updated description', v.phone_number = '+1-202-555-0199',
    v.website_url = 'https://query-demo.example.invalid'
WHERE v.vendor_id = @new_vendor_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = v.vendor_id AND m.user_id = @new_user_id);

-- Query 35
INSERT INTO Review (author_user_id, vendor_id, rating, review_text, created_at, updated_at)
VALUES (@new_user_id, @new_vendor_id, 4, '[DEMO] Query practice review', UTC_TIMESTAMP(), NULL);
SET @new_review_id = LAST_INSERT_ID();
UPDATE Review SET rating = 5, review_text = '[DEMO] Updated practice review', updated_at = UTC_TIMESTAMP()
WHERE review_id = @new_review_id AND author_user_id = @new_user_id;

-- Query 36
INSERT INTO Photo (uploader_user_id, vendor_id, image_url, caption, uploaded_at)
VALUES (@new_user_id, @new_vendor_id,
        'https://www.themealdb.com/images/media/meals/ustsqw1468250014.jpg',
        '[DEMO] Illustrative pasta photo', UTC_TIMESTAMP());
SET @new_photo_id = LAST_INSERT_ID();
INSERT INTO ReviewPhoto (photo_id, review_id)
SELECT p.photo_id, r.review_id FROM Photo p JOIN Review r ON r.vendor_id = p.vendor_id
WHERE p.photo_id = @new_photo_id AND r.review_id = @new_review_id
  AND p.uploader_user_id = @new_user_id AND r.author_user_id = @new_user_id;
INSERT INTO MenuItemPhoto (photo_id, menu_item_id)
SELECT p.photo_id, mi.menu_item_id FROM Photo p JOIN MenuItem mi ON mi.vendor_id = p.vendor_id
WHERE p.photo_id = @new_photo_id AND mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = p.vendor_id AND m.user_id = @new_user_id);

-- Query 37
INSERT INTO Favorites (user_id, vendor_id, saved_at)
VALUES (@new_user_id, @new_vendor_id, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE saved_at = Favorites.saved_at;
DELETE FROM Favorites WHERE user_id = @new_user_id AND vendor_id = @new_vendor_id;

-- Query 38
INSERT INTO FoodPermit (vendor_id, permit_number, issuing_authority, permit_type,
                        issued_date, expiration_date, document_url)
SELECT @new_vendor_id, CONCAT('QUERY-DEMO-', @new_vendor_id), 'DEMO AUTHORITY - NOT VALID',
       'demo_food_service', UTC_DATE(), UTC_DATE() + INTERVAL 1 YEAR, NULL
WHERE EXISTS (SELECT 1 FROM Manages WHERE vendor_id = @new_vendor_id AND user_id = @new_user_id);
SET @new_permit_id = LAST_INSERT_ID();
UPDATE FoodPermit fp SET fp.expiration_date = UTC_DATE() + INTERVAL 2 YEAR
WHERE fp.permit_id = @new_permit_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = fp.vendor_id AND m.user_id = @new_user_id);

-- Query 39
DELETE rp FROM ReviewPhoto rp JOIN Review r ON r.review_id = rp.review_id
WHERE r.review_id = @new_review_id AND r.author_user_id = @new_user_id;
DELETE FROM Review WHERE review_id = @new_review_id AND author_user_id = @new_user_id;

-- Query 40
DELETE mp FROM MenuItemPhoto mp JOIN MenuItem mi ON mi.menu_item_id = mp.menu_item_id
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);
DELETE mi FROM MenuItem mi
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);

-- Query 41
UPDATE Vendor v SET v.listing_status = 'inactive'
WHERE v.vendor_id = @new_vendor_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = v.vendor_id AND m.user_id = @new_user_id);

-- Query 42
DELETE FROM ReviewPhoto WHERE photo_id = @new_photo_id;
DELETE FROM MenuItemPhoto WHERE photo_id = @new_photo_id;
DELETE FROM Photo WHERE photo_id = @new_photo_id AND uploader_user_id = @new_user_id;

ROLLBACK;
