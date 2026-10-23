USE restaurants;

-- Example inputs. The app will supply these from its forms/login session.
SET @vendor_id = 1;
SET @user_id = (SELECT user_id FROM User WHERE email = 'demo.customer.001@example.invalid');
SET @owner_id = (SELECT user_id FROM User WHERE email = 'demo.owner.001@example.invalid');

-- RETRIEVE DATA

-- Browse vendors with ratings.
SELECT v.vendor_id, v.name, v.vendor_type,
       ROUND(AVG(r.rating), 2) AS average_rating,
       COUNT(r.review_id) AS review_count
FROM Vendor v
LEFT JOIN Review r ON r.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.name, v.vendor_type
ORDER BY average_rating DESC;

-- Search by name.
SELECT vendor_id, name, vendor_type
FROM Vendor
WHERE name LIKE '%pizza%';

-- Filter by cuisine and city.
SELECT DISTINCT v.vendor_id, v.name, l.city
FROM Vendor v
JOIN VendorCuisine vc ON vc.vendor_id = v.vendor_id
JOIN Cuisine c ON c.cuisine_id = vc.cuisine_id
JOIN VendorBase vb ON vb.vendor_id = v.vendor_id
JOIN Location l ON l.location_id = vb.location_id
WHERE c.cuisine_name = 'Italian' AND l.city = 'Alexandria';

-- Vendor details, menu, hours, and permits.
SELECT * FROM Vendor WHERE vendor_id = @vendor_id;
SELECT * FROM MenuItem WHERE vendor_id = @vendor_id ORDER BY category, item_name;
SELECT * FROM OperatingHours WHERE vendor_id = @vendor_id;
SELECT * FROM FoodPermit WHERE vendor_id = @vendor_id;

-- Dated locations for restaurants and mobile vendors.
SELECT s.stop_id, s.scheduled_start, s.scheduled_end, s.stop_status,
       l.location_name, l.city, l.latitude, l.longitude
FROM OperatingStop s
JOIN Location l ON l.location_id = s.location_id
WHERE s.vendor_id = @vendor_id
ORDER BY s.scheduled_start;

-- Reviews and their authors.
SELECT r.review_id, u.display_name, r.rating, r.review_text, r.created_at
FROM Review r
JOIN User u ON u.user_id = r.author_user_id
WHERE r.vendor_id = @vendor_id
ORDER BY r.created_at DESC;

-- Menu photos.
SELECT m.item_name, p.image_url, p.caption
FROM MenuItem m
JOIN MenuItemPhoto mp ON mp.menu_item_id = m.menu_item_id
JOIN Photo p ON p.photo_id = mp.photo_id
WHERE m.vendor_id = @vendor_id AND p.vendor_id = m.vendor_id;

-- Review photos.
SELECT r.review_id, p.image_url, p.caption
FROM Review r
JOIN ReviewPhoto rp ON rp.review_id = r.review_id
JOIN Photo p ON p.photo_id = rp.photo_id
WHERE r.vendor_id = @vendor_id AND p.vendor_id = r.vendor_id;

-- Saved vendors and managed vendors.
SELECT v.vendor_id, v.name, f.saved_at
FROM Favorites f JOIN Vendor v ON v.vendor_id = f.vendor_id
WHERE f.user_id = @user_id;

SELECT v.vendor_id, v.name, m.management_role
FROM Manages m JOIN Vendor v ON v.vendor_id = m.vendor_id
WHERE m.user_id = @owner_id;

-- Login lookup: PHP verifies the submitted password against the returned hash.
SELECT user_id, display_name, password_hash
FROM User
WHERE email = 'demo.customer.001@example.invalid'
  AND password_hash NOT LIKE '!IMPORTED_NO_LOGIN!%';

-- ADD DATA
-- The examples below are rolled back at the end. Run the whole section.
START TRANSACTION;

INSERT INTO Review (author_user_id, vendor_id, rating, review_text, created_at)
VALUES (@user_id, @vendor_id, 4, '[DEMO] Review example', UTC_TIMESTAMP());
SET @review_id = LAST_INSERT_ID();

INSERT INTO Favorites (user_id, vendor_id, saved_at)
VALUES (@user_id, @vendor_id, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE saved_at = Favorites.saved_at;

INSERT INTO MenuItem (vendor_id, item_name, description, price, category, availability_status)
SELECT @vendor_id, '[DEMO] Pasta', 'Example menu item', 12.50, 'Main', 'available'
WHERE EXISTS (
    SELECT 1 FROM Manages WHERE user_id = @owner_id AND vendor_id = @vendor_id
);
SET @item_id = LAST_INSERT_ID();

INSERT INTO Vendor (name, vendor_type, listing_status, created_at, timezone, submitted_by_user_id)
VALUES ('[DEMO] New Vendor', 'food_truck', 'demo', UTC_TIMESTAMP(), 'America/New_York', @user_id);
SET @new_vendor_id = LAST_INSERT_ID();

-- UPDATE DATA

UPDATE Review
SET rating = 5, review_text = '[DEMO] Updated review', updated_at = UTC_TIMESTAMP()
WHERE review_id = @review_id AND author_user_id = @user_id;

UPDATE MenuItem mi
SET mi.price = 13.50
WHERE mi.menu_item_id = @item_id
  AND EXISTS (
      SELECT 1 FROM Manages m WHERE m.user_id = @owner_id AND m.vendor_id = mi.vendor_id
  );

UPDATE User
SET display_name = 'Demo Customer'
WHERE user_id = @user_id;

UPDATE Vendor v
SET v.description = '[DEMO] Updated description'
WHERE v.vendor_id = @vendor_id
  AND EXISTS (
      SELECT 1 FROM Manages m WHERE m.user_id = @owner_id AND m.vendor_id = v.vendor_id
  );

-- DELETE DATA

DELETE FROM Favorites
WHERE user_id = @user_id AND vendor_id = @vendor_id;

-- Remove review/photo links before deleting a review with attached photos.
DELETE rp FROM ReviewPhoto rp
JOIN Review r ON r.review_id = rp.review_id
WHERE r.review_id = @review_id AND r.author_user_id = @user_id;

DELETE FROM Review
WHERE review_id = @review_id AND author_user_id = @user_id;

-- This new example item has no photo links.
DELETE mi FROM MenuItem mi
WHERE mi.menu_item_id = @item_id
  AND EXISTS (
      SELECT 1 FROM Manages m WHERE m.user_id = @owner_id AND m.vendor_id = mi.vendor_id
  );

DELETE FROM Vendor
WHERE vendor_id = @new_vendor_id AND submitted_by_user_id = @user_id;

ROLLBACK;
