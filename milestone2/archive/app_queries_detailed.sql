-- CS4750 app query examples: existing restaurants schema.
-- SQL is the database language. PHP/Python executes ONE relevant query per action.
-- @variables are console examples. In your app, bind values with prepared statements.
-- Authenticated user IDs come from the server-side login session, not form fields.
-- Read queries run first. ALL write examples are in a transaction ending in ROLLBACK.
-- Run the entire write section, or ROLLBACK if you stop midway. IDs can have gaps.
-- Do not run this file inside another transaction. No DELIMITER commands are used.

USE restaurants;
SET @queries_old_timezone = @@SESSION.time_zone;
SET SESSION time_zone = '+00:00';
SET @vendor_id = 1;
SET @customer_id = (SELECT user_id FROM User WHERE email LIKE 'demo.customer.%@example.invalid' ORDER BY user_id LIMIT 1);
SET @manager_id = (SELECT user_id FROM Manages WHERE vendor_id = @vendor_id ORDER BY user_id LIMIT 1);
SET @keyword = '';
SET @city = NULL;
SET @cuisine = NULL;
SET @vendor_type = NULL;

-- Q01 DISCOVERY: browse/search/filter vendors, highest rated first.
-- NULL means no filter. Change @keyword, @city, @cuisine, @vendor_type to experiment.
-- Reviews are aggregated BEFORE joining other tables, preventing inflated counts.
SELECT v.vendor_id, v.name, v.vendor_type, v.listing_status,
       l.city, l.state, l.latitude, l.longitude,
       r.average_rating, COALESCE(r.review_count, 0) AS review_count
FROM Vendor v
LEFT JOIN VendorBase vb ON vb.vendor_id = v.vendor_id
LEFT JOIN Location l ON l.location_id = vb.location_id
LEFT JOIN (
    SELECT vendor_id, ROUND(AVG(rating), 2) AS average_rating, COUNT(*) AS review_count
    FROM Review GROUP BY vendor_id
) r ON r.vendor_id = v.vendor_id
WHERE v.name LIKE CONCAT('%', @keyword, '%')
  AND (@city IS NULL OR l.city = @city OR EXISTS (
      SELECT 1 FROM OperatingStop os JOIN Location sl ON sl.location_id = os.location_id
      WHERE os.vendor_id = v.vendor_id AND sl.city = @city
        AND os.scheduled_end >= UTC_TIMESTAMP()
        AND os.stop_status NOT IN ('cancelled', 'demo_cancelled')
  ))
  AND (@vendor_type IS NULL OR v.vendor_type = @vendor_type)
  AND (@cuisine IS NULL OR EXISTS (
      SELECT 1 FROM VendorCuisine vc JOIN Cuisine c ON c.cuisine_id = vc.cuisine_id
      WHERE vc.vendor_id = v.vendor_id AND c.cuisine_name = @cuisine
  ))
ORDER BY r.average_rating DESC, review_count DESC, v.vendor_id
LIMIT 20 OFFSET 0;
-- In PHP, use separate placeholders for repeated filter values when native PDO
-- prepares are enabled. Sort columns/directions must come from a fixed allowlist.
-- A city can match a base or an upcoming/current dated stop.

-- Q02 VENDOR PROFILE: details plus real aggregate ratings (not stored summaries).
SELECT v.*, l.location_name, l.street_address, l.city, l.state, l.postal_code,
       l.latitude, l.longitude,
       (SELECT ROUND(AVG(rating), 2) FROM Review WHERE vendor_id = v.vendor_id) AS average_rating,
       (SELECT COUNT(*) FROM Review WHERE vendor_id = v.vendor_id) AS review_count
FROM Vendor v
LEFT JOIN VendorBase vb ON vb.vendor_id = v.vendor_id
LEFT JOIN Location l ON l.location_id = vb.location_id
WHERE v.vendor_id = @vendor_id;

-- Q03 PROFILE: cuisine labels.
SELECT c.cuisine_id, c.cuisine_name
FROM VendorCuisine vc JOIN Cuisine c ON c.cuisine_id = vc.cuisine_id
WHERE vc.vendor_id = @vendor_id ORDER BY c.cuisine_name;

-- Q04 PROFILE: menu (photos are a separate query to avoid duplicate item rows).
SELECT menu_item_id, item_name, description, price, category, availability_status
FROM MenuItem WHERE vendor_id = @vendor_id ORDER BY category, item_name;

-- Q05 PROFILE: item photos, joined through MenuItemPhoto.
SELECT m.menu_item_id, p.photo_id, p.image_url, p.caption
FROM MenuItem m JOIN MenuItemPhoto mp ON mp.menu_item_id = m.menu_item_id
JOIN Photo p ON p.photo_id = mp.photo_id AND p.vendor_id = m.vendor_id
WHERE m.vendor_id = @vendor_id ORDER BY m.menu_item_id, p.photo_id;

-- Q06 PROFILE: recurring weekly hours (including split and overnight shifts).
SELECT hours_number, day_of_week, opening_time, closing_time
FROM OperatingHours WHERE vendor_id = @vendor_id
ORDER BY FIELD(day_of_week, 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'), opening_time;

-- Q07 MAP/SCHEDULE: dated stops with their locations; includes mobile vendors.
-- Remove the time filter to see past stops too. Stored datetimes use UTC.
SELECT s.*, l.location_name, l.street_address, l.city, l.latitude, l.longitude
FROM OperatingStop s JOIN Location l ON l.location_id = s.location_id
WHERE s.vendor_id = @vendor_id AND s.scheduled_end >= UTC_TIMESTAMP()
ORDER BY s.scheduled_start;

-- Q08 PROFILE: community reviews, newest first.
SELECT r.review_id, r.rating, r.review_text, r.created_at, r.updated_at,
       u.user_id AS author_user_id, u.display_name
FROM Review r JOIN User u ON u.user_id = r.author_user_id
WHERE r.vendor_id = @vendor_id
ORDER BY r.created_at DESC, r.review_id DESC LIMIT 20;

-- Q09 PROFILE: photos attached to reviews.
SELECT rp.review_id, p.photo_id, p.image_url, p.caption
FROM ReviewPhoto rp JOIN Review r ON r.review_id = rp.review_id
JOIN Photo p ON p.photo_id = rp.photo_id AND p.vendor_id = r.vendor_id
WHERE r.vendor_id = @vendor_id ORDER BY rp.review_id, p.photo_id;

-- Q10 PROFILE: permits, including clearly identified demo permits.
SELECT permit_number, issuing_authority, permit_type, issued_date, expiration_date, document_url
FROM FoodPermit WHERE vendor_id = @vendor_id ORDER BY expiration_date;

-- Q11 USER DASHBOARD: saved vendors.
SELECT v.vendor_id, v.name, v.vendor_type, f.saved_at
FROM Favorites f JOIN Vendor v ON v.vendor_id = f.vendor_id
WHERE f.user_id = @customer_id ORDER BY f.saved_at DESC, v.vendor_id;

-- Q12 USER DASHBOARD: user's own reviews, available for editing/removal.
SELECT r.review_id, r.vendor_id, v.name, r.rating, r.review_text, r.created_at, r.updated_at
FROM Review r JOIN Vendor v ON v.vendor_id = r.vendor_id
WHERE r.author_user_id = @customer_id ORDER BY r.created_at DESC;

-- Q13 OWNER DASHBOARD: vendors this user can manage.
SELECT v.vendor_id, v.name, m.management_role, m.granted_at
FROM Manages m JOIN Vendor v ON v.vendor_id = m.vendor_id
WHERE m.user_id = @manager_id ORDER BY v.name;

-- Q14 LOGIN: retrieve the hash by email; verify the password in PHP.
-- Never compare plaintext passwords in SQL or return this hash to the browser.
-- Imported attribution profiles and the importer are excluded from login.
SET @login_email = (SELECT email FROM User WHERE user_id = @customer_id);
SELECT user_id, display_name, password_hash
FROM User
WHERE email = @login_email
  AND email NOT LIKE 'imported.google.%@example.invalid'
  AND email <> 'dataset-importer@example.invalid'
  AND password_hash NOT LIKE '!IMPORTED_NO_LOGIN!%';

-- Q15 EXPORT: reviews for a vendor managed by the requesting user.
-- PHP turns the returned rows into CSV/JSON and sends a download response.
SELECT r.review_id, r.rating, r.review_text, r.created_at, r.updated_at
FROM Review r
WHERE r.vendor_id = @vendor_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = r.vendor_id AND m.user_id = @manager_id)
ORDER BY r.review_id;

-- Q15B NEARBY MAP RESULTS: distance to base or a current scheduled stop.
-- Each vendor can appear at multiple locations, matching the Milestone 1 rules.
SET @search_latitude = 38.029306;
SET @search_longitude = -78.476678;
WITH candidate_locations AS (
    SELECT vendor_id, location_id, 'base' AS location_kind FROM VendorBase
    UNION ALL
    SELECT vendor_id, location_id, 'current_scheduled_stop' FROM OperatingStop
    WHERE scheduled_start <= UTC_TIMESTAMP() AND scheduled_end > UTC_TIMESTAMP()
      AND stop_status NOT IN ('cancelled', 'demo_cancelled')
)
SELECT v.vendor_id, v.name, cl.location_kind, l.location_id, l.location_name,
       l.latitude, l.longitude,
       6371 * 2 * ASIN(SQRT(LEAST(1, GREATEST(0,
           POW(SIN(RADIANS(l.latitude - @search_latitude) / 2), 2)
           + COS(RADIANS(@search_latitude)) * COS(RADIANS(l.latitude))
           * POW(SIN(RADIANS(l.longitude - @search_longitude) / 2), 2)
       )))) AS distance_km
FROM candidate_locations cl
JOIN Vendor v ON v.vendor_id = cl.vendor_id
JOIN Location l ON l.location_id = cl.location_id
ORDER BY distance_km, v.vendor_id LIMIT 20;

-- =====================================================================
-- WRITE EXAMPLES: changes below are deliberately ROLLED BACK at the end.
-- Newly created records are used so existing reviews/menus are not deleted.
-- In the real app, execute only the statements for that action, then COMMIT.
-- =====================================================================
START TRANSACTION;

-- Q16 REGISTER: PHP must create a fresh hash using password_hash().
-- This bcrypt hash is only for the disposable example password:
-- CS4750-Query-Demo-Only! (do not reuse it for actual registrations).
INSERT INTO User (display_name, email, password_hash, joined_at)
VALUES ('Query Demo User', CONCAT('query-demo-', UUID(), '@example.invalid'),
        '$2y$10$OrsTj3NedJZ8oeMzYVdt2O8aZZW901CYshgDr75b2VBFGrtlBjzXS', UTC_TIMESTAMP());
SET @new_user_id = LAST_INSERT_ID();

-- Q17 EDIT OWN PROFILE: user ID comes from the authenticated session.
UPDATE User SET display_name = 'Updated Query Demo User' WHERE user_id = @new_user_id;

-- Q18 SUBMIT A LISTING: submission alone does not grant ownership.
INSERT INTO Vendor (name, description, vendor_type, phone_number, website_url,
                    listing_status, created_at, timezone, submitted_by_user_id)
VALUES ('[DEMO] Query Practice Vendor', 'Disposable SQL learning example', 'food_truck',
        NULL, NULL, 'demo', UTC_TIMESTAMP(), 'America/New_York', @new_user_id);
SET @new_vendor_id = LAST_INSERT_ID();

-- Q19 GRANT MANAGEMENT: a trusted approval/setup action, not a public form.
INSERT INTO Manages (user_id, vendor_id, management_role, granted_at)
VALUES (@new_user_id, @new_vendor_id, 'demo_owner', UTC_TIMESTAMP());

-- Q20 CREATE A LOCATION AND OPTIONAL BASE RELATIONSHIP.
-- A mobile vendor may omit VendorBase and use dated stops only.
INSERT INTO Location (location_name, street_address, city, state, postal_code, latitude, longitude)
VALUES ('[DEMO] Practice Stop', NULL, 'Charlottesville', 'VA', NULL, 38.029306, -78.476678);
SET @new_location_id = LAST_INSERT_ID();
INSERT INTO VendorBase (vendor_id, location_id) VALUES (@new_vendor_id, @new_location_id);

-- Q21 TAG A VENDOR: reuse an existing cuisine instead of duplicating its name.
SET @existing_cuisine_id = (SELECT cuisine_id FROM Cuisine ORDER BY cuisine_id LIMIT 1);
INSERT INTO VendorCuisine (vendor_id, cuisine_id) VALUES (@new_vendor_id, @existing_cuisine_id);

-- Q22 SET WEEKLY HOURS: owning-vendor discriminator is hours_number.
INSERT INTO OperatingHours (vendor_id, hours_number, day_of_week, opening_time, closing_time)
VALUES (@new_vendor_id, 1, 'Monday', '11:00:00', '19:00:00');

-- Q23 ADD/UPDATE A DATED STOP: moving a vendor creates/edits a stop, not a
-- shared Location row (other vendors may reference the same location).
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

-- Q24 OWNER ADDS/EDITS A MENU ITEM: ownership is checked in the query.
INSERT INTO MenuItem (vendor_id, item_name, description, price, category, availability_status)
SELECT @new_vendor_id, '[DEMO] Practice Dish', 'Disposable learning example', 10.00, 'Demo', 'demo_available'
WHERE EXISTS (SELECT 1 FROM Manages WHERE vendor_id = @new_vendor_id AND user_id = @new_user_id);
SET @new_item_id = LAST_INSERT_ID();
UPDATE MenuItem mi SET mi.price = 11.50
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);

-- Q25 OWNER UPDATES A VENDOR'S DETAILS.
UPDATE Vendor v SET v.description = '[DEMO] Updated description'
WHERE v.vendor_id = @new_vendor_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = v.vendor_id AND m.user_id = @new_user_id);

-- Q26 POST/EDIT A REVIEW: user may only edit their own review.
INSERT INTO Review (author_user_id, vendor_id, rating, review_text, created_at, updated_at)
VALUES (@new_user_id, @new_vendor_id, 4, '[DEMO] Query practice review', UTC_TIMESTAMP(), NULL);
SET @new_review_id = LAST_INSERT_ID();
UPDATE Review SET rating = 5, review_text = '[DEMO] Updated practice review', updated_at = UTC_TIMESTAMP()
WHERE review_id = @new_review_id AND author_user_id = @new_user_id;

-- Q27 ADD A PHOTO AND ATTACH IT TO A REVIEW / MENU ITEM.
-- App validates the URL. INSERT/SELECT checks that referenced vendors match.
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

-- Q28 SAVE/UNSAVE A VENDOR. Repeated save requests do not duplicate the pair.
INSERT INTO Favorites (user_id, vendor_id, saved_at)
VALUES (@new_user_id, @new_vendor_id, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE saved_at = Favorites.saved_at;
DELETE FROM Favorites WHERE user_id = @new_user_id AND vendor_id = @new_vendor_id;

-- Q29 ADD/RENEW A PERMIT: same authority+number identifies an existing permit.
INSERT INTO FoodPermit (vendor_id, permit_number, issuing_authority, permit_type,
                        issued_date, expiration_date, document_url)
SELECT @new_vendor_id, CONCAT('QUERY-DEMO-', @new_vendor_id), 'DEMO AUTHORITY - NOT VALID',
       'demo_food_service', UTC_DATE(), UTC_DATE() + INTERVAL 1 YEAR, NULL
WHERE EXISTS (SELECT 1 FROM Manages WHERE vendor_id = @new_vendor_id AND user_id = @new_user_id);
SET @new_permit_id = LAST_INSERT_ID();
UPDATE FoodPermit fp SET fp.expiration_date = UTC_DATE() + INTERVAL 2 YEAR
WHERE fp.permit_id = @new_permit_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = fp.vendor_id AND m.user_id = @new_user_id);

-- Q30 DELETE OWN REVIEW, KEEPING ITS PHOTO RECORD.
-- Remove relationship rows first to satisfy the existing foreign keys.
DELETE rp FROM ReviewPhoto rp JOIN Review r ON r.review_id = rp.review_id
WHERE r.review_id = @new_review_id AND r.author_user_id = @new_user_id;
DELETE FROM Review WHERE review_id = @new_review_id AND author_user_id = @new_user_id;

-- Q31 REMOVE A MENU ITEM, KEEPING THE PHOTO RECORD.
DELETE mp FROM MenuItemPhoto mp JOIN MenuItem mi ON mi.menu_item_id = mp.menu_item_id
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);
DELETE mi FROM MenuItem mi
WHERE mi.menu_item_id = @new_item_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = mi.vendor_id AND m.user_id = @new_user_id);

-- Q32 TAKE DOWN A VENDOR LISTING: a soft removal preserves related records.
UPDATE Vendor v SET v.listing_status = 'inactive'
WHERE v.vendor_id = @new_vendor_id
  AND EXISTS (SELECT 1 FROM Manages m WHERE m.vendor_id = v.vendor_id AND m.user_id = @new_user_id);

-- Q33 IMPORT: after PHP validates an uploaded menu CSV/JSON, execute Q24 once
-- per valid row in ONE transaction, reusing its prepared statement. Stop and
-- roll back on failure. CSV parsing and download formatting happen in PHP.

-- Inspect disposable records before rollback.
SELECT vendor_id, name, listing_status FROM Vendor WHERE vendor_id = @new_vendor_id;
SELECT menu_item_id FROM MenuItem WHERE vendor_id = @new_vendor_id;

ROLLBACK;
SET SESSION time_zone = @queries_old_timezone;
SELECT 'Write examples rolled back; original application data is unchanged.' AS demo_status;
