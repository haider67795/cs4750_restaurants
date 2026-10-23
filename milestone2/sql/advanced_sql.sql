-- Advanced types: existing CHECK constraints and same-vendor TRIGGERS.
-- Multiple triggers count as one advanced type. No table definitions change.
DELIMITER //
USE restaurants//

DROP TRIGGER IF EXISTS check_reviewphoto_insert//
CREATE TRIGGER check_reviewphoto_insert
BEFORE INSERT ON ReviewPhoto
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Photo p JOIN Review r ON p.vendor_id = r.vendor_id WHERE p.photo_id = NEW.photo_id AND r.review_id = NEW.review_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Photo and Review must belong to the same vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_reviewphoto_update//
CREATE TRIGGER check_reviewphoto_update
BEFORE UPDATE ON ReviewPhoto
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Photo p JOIN Review r ON p.vendor_id = r.vendor_id WHERE p.photo_id = NEW.photo_id AND r.review_id = NEW.review_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Photo and Review must belong to the same vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_menuitemphoto_insert//
CREATE TRIGGER check_menuitemphoto_insert
BEFORE INSERT ON MenuItemPhoto
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Photo p JOIN MenuItem r ON p.vendor_id = r.vendor_id WHERE p.photo_id = NEW.photo_id AND r.menu_item_id = NEW.menu_item_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Photo and MenuItem must belong to the same vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_menuitemphoto_update//
CREATE TRIGGER check_menuitemphoto_update
BEFORE UPDATE ON MenuItemPhoto
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Photo p JOIN MenuItem r ON p.vendor_id = r.vendor_id WHERE p.photo_id = NEW.photo_id AND r.menu_item_id = NEW.menu_item_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Photo and MenuItem must belong to the same vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_photo_vendor_update//
CREATE TRIGGER check_photo_vendor_update
BEFORE UPDATE ON Photo
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM ReviewPhoto rp JOIN Review r ON r.review_id = rp.review_id WHERE rp.photo_id = OLD.photo_id AND r.vendor_id <> NEW.vendor_id) OR EXISTS (SELECT 1 FROM MenuItemPhoto mp JOIN MenuItem m ON m.menu_item_id = mp.menu_item_id WHERE mp.photo_id = OLD.photo_id AND m.vendor_id <> NEW.vendor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change photo vendor while attached records use another vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_review_vendor_update//
CREATE TRIGGER check_review_vendor_update
BEFORE UPDATE ON Review
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM ReviewPhoto link JOIN Photo p ON p.photo_id = link.photo_id WHERE link.review_id = OLD.review_id AND p.vendor_id <> NEW.vendor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change Review vendor while attached photos use another vendor';
    END IF;
END//

DROP TRIGGER IF EXISTS check_menuitem_vendor_update//
CREATE TRIGGER check_menuitem_vendor_update
BEFORE UPDATE ON MenuItem
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM MenuItemPhoto link JOIN Photo p ON p.photo_id = link.photo_id WHERE link.menu_item_id = OLD.menu_item_id AND p.vendor_id <> NEW.vendor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change MenuItem vendor while attached photos use another vendor';
    END IF;
END//

-- Retire the earlier one-insert procedure.
DROP PROCEDURE IF EXISTS AddReview//
DELIMITER ;
