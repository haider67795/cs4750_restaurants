USE restaurants;
START TRANSACTION;
SET @u=(SELECT user_id FROM User WHERE email='demo.customer.001@example.invalid');
SET @r1=(SELECT MIN(review_id) FROM Review WHERE vendor_id=1);
SET @r2=(SELECT MIN(review_id) FROM Review WHERE vendor_id=2);
SET @m1=(SELECT MIN(menu_item_id) FROM MenuItem WHERE vendor_id=1);
SET @m2=(SELECT MIN(menu_item_id) FROM MenuItem WHERE vendor_id=2);
INSERT INTO Photo (uploader_user_id,vendor_id,image_url,caption,uploaded_at)
VALUES (@u,1,'https://example.invalid/trigger-test.jpg','[DEMO] Rolled-back trigger test',UTC_TIMESTAMP());
SET @p=LAST_INSERT_ID();
INSERT INTO ReviewPhoto(photo_id,review_id) VALUES(@p,@r1);
SELECT 'Valid same-vendor review link',COUNT(*) FROM ReviewPhoto WHERE photo_id=@p;
-- Expected rejection 1: change review attachment to another vendor.
UPDATE ReviewPhoto SET review_id=@r2 WHERE photo_id=@p;
-- Expected rejection 2: change photo vendor while attached to review.
UPDATE Photo SET vendor_id=2 WHERE photo_id=@p;
-- Expected rejection 3: change review vendor while photos are attached.
UPDATE Review SET vendor_id=2 WHERE review_id=@r1;
DELETE FROM ReviewPhoto WHERE photo_id=@p;
-- Expected rejection 4: insert a cross-vendor review attachment.
INSERT INTO ReviewPhoto(photo_id,review_id) VALUES(@p,@r2);
INSERT INTO MenuItemPhoto(photo_id,menu_item_id) VALUES(@p,@m1);
SELECT 'Valid same-vendor menu link',COUNT(*) FROM MenuItemPhoto WHERE photo_id=@p;
-- Expected rejection 5: change menu attachment to another vendor.
UPDATE MenuItemPhoto SET menu_item_id=@m2 WHERE photo_id=@p;
-- Expected rejection 6: change item vendor while a photo is attached.
UPDATE MenuItem SET vendor_id=2 WHERE menu_item_id=@m1;
DELETE FROM MenuItemPhoto WHERE photo_id=@p;
-- Expected rejection 7: insert a cross-vendor menu attachment.
INSERT INTO MenuItemPhoto(photo_id,menu_item_id) VALUES(@p,@m2);
ROLLBACK;
