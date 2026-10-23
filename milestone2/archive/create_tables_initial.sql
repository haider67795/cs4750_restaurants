CREATE TABLE IF NOT EXISTS User (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    joined_at DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS Vendor (
    vendor_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    vendor_type VARCHAR(100) NOT NULL,
    phone_number VARCHAR(50),
    website_url VARCHAR(2048),
    listing_status VARCHAR(100) NOT NULL,
    created_at DATETIME NOT NULL,
    timezone VARCHAR(100) NOT NULL,
    submitted_by_user_id INT NOT NULL,
    FOREIGN KEY (submitted_by_user_id) REFERENCES User(user_id)
);
