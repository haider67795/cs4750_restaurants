CREATE DATABASE IF NOT EXISTS restaurants;
USE restaurants;

CREATE TABLE `User` (
  user_id INT AUTO_INCREMENT,
  display_name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id)
);

CREATE TABLE Cuisine (
  cuisine_id INT AUTO_INCREMENT,
  cuisine_name VARCHAR(100) NOT NULL UNIQUE,
  PRIMARY KEY (cuisine_id)
);

CREATE TABLE Location (
  location_id INT AUTO_INCREMENT,
  location_name VARCHAR(150),
  street_address VARCHAR(255),
  city VARCHAR(100),
  state VARCHAR(50),
  postal_code VARCHAR(20),
  latitude DECIMAL(9,6) NOT NULL,
  longitude DECIMAL(9,6) NOT NULL,
  PRIMARY KEY (location_id),
  CONSTRAINT chk_latitude CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT chk_longitude CHECK (longitude BETWEEN -180 AND 180)
);

CREATE TABLE Vendor (
  vendor_id INT AUTO_INCREMENT,
  name VARCHAR(150) NOT NULL,
  description TEXT,
  vendor_type VARCHAR(50) NOT NULL,
  phone_number VARCHAR(30),
  website_url VARCHAR(500),
  listing_status VARCHAR(30) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  timezone VARCHAR(50) NOT NULL,
  submitted_by_user_id INT NOT NULL,
  PRIMARY KEY (vendor_id),
  FOREIGN KEY (submitted_by_user_id) REFERENCES `User`(user_id)
);

CREATE TABLE OperatingStop (
  stop_id INT AUTO_INCREMENT,
  vendor_id INT NOT NULL,
  location_id INT NOT NULL,
  scheduled_start DATETIME NOT NULL,
  scheduled_end DATETIME NOT NULL,
  actual_start DATETIME,
  actual_end DATETIME,
  stop_status VARCHAR(30) NOT NULL,
  notes TEXT,
  PRIMARY KEY (stop_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  FOREIGN KEY (location_id) REFERENCES Location(location_id),
  CONSTRAINT chk_sched_order CHECK (scheduled_end > scheduled_start),
  CONSTRAINT chk_actual_order CHECK (actual_end IS NULL OR (actual_start IS NOT NULL AND actual_end > actual_start))
);

CREATE TABLE OperatingHours (
  vendor_id INT NOT NULL,
  hours_number INT NOT NULL,
  day_of_week ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
  opening_time TIME NOT NULL,
  closing_time TIME NOT NULL,
  PRIMARY KEY (vendor_id, hours_number),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id)
);

CREATE TABLE MenuItem (
  menu_item_id INT AUTO_INCREMENT,
  vendor_id INT NOT NULL,
  item_name VARCHAR(150) NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  category VARCHAR(100),
  availability_status VARCHAR(30) NOT NULL,
  PRIMARY KEY (menu_item_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  CONSTRAINT chk_price CHECK (price >= 0)
);

CREATE TABLE Review (
  review_id INT AUTO_INCREMENT,
  author_user_id INT NOT NULL,
  vendor_id INT NOT NULL,
  rating INT NOT NULL,
  review_text TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL,
  PRIMARY KEY (review_id),
  FOREIGN KEY (author_user_id) REFERENCES `User`(user_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  CONSTRAINT chk_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE TABLE Photo (
  photo_id INT AUTO_INCREMENT,
  uploader_user_id INT NOT NULL,
  vendor_id INT NOT NULL,
  image_url VARCHAR(500) NOT NULL,
  caption VARCHAR(255),
  uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (photo_id),
  FOREIGN KEY (uploader_user_id) REFERENCES `User`(user_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id)
);

CREATE TABLE FoodPermit (
  permit_id INT AUTO_INCREMENT,
  vendor_id INT NOT NULL,
  permit_number VARCHAR(100) NOT NULL,
  issuing_authority VARCHAR(150) NOT NULL,
  permit_type VARCHAR(100) NOT NULL,
  issued_date DATE,
  expiration_date DATE,
  document_url VARCHAR(500),
  PRIMARY KEY (permit_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  CONSTRAINT uq_permit UNIQUE (issuing_authority, permit_number)
);

CREATE TABLE Manages (
  user_id INT NOT NULL,
  vendor_id INT NOT NULL,
  management_role VARCHAR(50) NOT NULL,
  granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, vendor_id),
  FOREIGN KEY (user_id) REFERENCES `User`(user_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id)
);

CREATE TABLE Favorites (
  user_id INT NOT NULL,
  vendor_id INT NOT NULL,
  saved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, vendor_id),
  FOREIGN KEY (user_id) REFERENCES `User`(user_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id)
);

CREATE TABLE VendorCuisine (
  vendor_id INT NOT NULL,
  cuisine_id INT NOT NULL,
  PRIMARY KEY (vendor_id, cuisine_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  FOREIGN KEY (cuisine_id) REFERENCES Cuisine(cuisine_id)
);

CREATE TABLE VendorBase (
  vendor_id INT NOT NULL,
  location_id INT NOT NULL,
  PRIMARY KEY (vendor_id),
  FOREIGN KEY (vendor_id) REFERENCES Vendor(vendor_id),
  FOREIGN KEY (location_id) REFERENCES Location(location_id)
);

CREATE TABLE ReviewPhoto (
  photo_id INT NOT NULL,
  review_id INT NOT NULL,
  PRIMARY KEY (photo_id),
  FOREIGN KEY (photo_id) REFERENCES Photo(photo_id),
  FOREIGN KEY (review_id) REFERENCES Review(review_id)
);

CREATE TABLE MenuItemPhoto (
  photo_id INT NOT NULL,
  menu_item_id INT NOT NULL,
  PRIMARY KEY (photo_id),
  FOREIGN KEY (photo_id) REFERENCES Photo(photo_id),
  FOREIGN KEY (menu_item_id) REFERENCES MenuItem(menu_item_id)
);