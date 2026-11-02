CREATE TABLE roles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL
);

CREATE TABLE permissions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(120) NOT NULL UNIQUE,
    description VARCHAR(255) NOT NULL
);

CREATE TABLE role_permissions (
    role_id BIGINT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    permission_id BIGINT NOT NULL,
    FOREIGN KEY (permission_id) REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    email VARCHAR(320),
    google_subject VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);

-- The default utf8mb4 collation is case-insensitive, so plain unique indexes give the same
-- guarantee as the old LOWER() indexes; NULL e-mails / subjects stay unrestricted.
CREATE UNIQUE INDEX ux_users_username_ci ON users (username);
CREATE UNIQUE INDEX ux_users_email_ci ON users (email);
CREATE UNIQUE INDEX ux_users_google_subject ON users (google_subject);

CREATE TABLE user_roles (
    user_id BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    role_id BIGINT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE branches (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL,
    address TEXT,
    latitude DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180),
    geofence_radius_m INTEGER NOT NULL DEFAULT 100 CHECK (geofence_radius_m > 0),
    require_gps BOOLEAN NOT NULL DEFAULT TRUE,
    require_wifi BOOLEAN NOT NULL DEFAULT TRUE,
    require_registered_device BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK ((latitude IS NULL) = (longitude IS NULL))
);

CREATE TABLE departments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL
);

CREATE TABLE positions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL
);

CREATE TABLE employees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE,
    FOREIGN KEY (user_id) REFERENCES users(id),
    employee_code VARCHAR(80) NOT NULL UNIQUE,
    full_name VARCHAR(200) NOT NULL,
    birth_date DATE,
    phone VARCHAR(50),
    address TEXT,
    branch_id BIGINT NOT NULL,
    FOREIGN KEY (branch_id) REFERENCES branches(id),
    department_id BIGINT,
    FOREIGN KEY (department_id) REFERENCES departments(id),
    position_id BIGINT,
    FOREIGN KEY (position_id) REFERENCES positions(id),
    manager_id BIGINT,
    FOREIGN KEY (manager_id) REFERENCES employees(id),
    hire_date DATE NOT NULL,
    termination_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'terminated')),
    CHECK (termination_date IS NULL OR termination_date >= hire_date)
);

CREATE INDEX ix_employee_department ON employees (department_id, status);