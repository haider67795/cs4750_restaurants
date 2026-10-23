USE restaurants;

-- Advanced type 1: CHECK constraints, already present in create_tables.sql.
-- Review: rating BETWEEN 1 AND 5.
-- MenuItem: price >= 0.
-- Location: latitude/longitude ranges.
-- OperatingStop: scheduled and actual times must be ordered correctly.
SELECT tc.TABLE_NAME, tc.CONSTRAINT_NAME, cc.CHECK_CLAUSE
FROM information_schema.TABLE_CONSTRAINTS tc
JOIN information_schema.CHECK_CONSTRAINTS cc
  ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
 AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
WHERE tc.CONSTRAINT_SCHEMA = DATABASE() AND tc.CONSTRAINT_TYPE = 'CHECK';

-- Advanced type 2: a stored procedure used when the app posts a review.
-- Its single-statement body needs no DELIMITER command.
-- Foreign keys validate the author/vendor; CHECK validates the rating;
-- NOT NULL validates the required text. Authentication remains in the app.
DROP PROCEDURE IF EXISTS AddReview;
CREATE PROCEDURE AddReview (
    IN p_author_user_id INT,
    IN p_vendor_id INT,
    IN p_rating INT,
    IN p_review_text TEXT
)
INSERT INTO Review (author_user_id, vendor_id, rating, review_text, created_at, updated_at)
VALUES (p_author_user_id, p_vendor_id, p_rating, p_review_text, UTC_TIMESTAMP(), NULL);

-- Successful-call demonstration, rolled back so the seed remains unchanged.
SET @review_demo_user = (SELECT user_id FROM User WHERE email = 'demo.customer.001@example.invalid');
START TRANSACTION;
CALL AddReview(@review_demo_user, 1, 5, '[DEMO] Stored procedure test');
SET @procedure_review_id = LAST_INSERT_ID();
SELECT review_id, author_user_id, vendor_id, rating, review_text
FROM Review WHERE review_id = @procedure_review_id;
ROLLBACK;

-- Run separately for a negative test: rating 6 should fail the CHECK constraint.
-- CALL AddReview(@review_demo_user, 1, 6, '[DEMO] Invalid rating test');
