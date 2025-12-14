-- ===================================================================================
-- 1. INSERT USERS (We need separate Users for Patients AND Doctors)
-- ===================================================================================
-- IDs 1-5: Patients
-- IDs 6-8: Doctors

INSERT INTO app_user (id, username, password, provider_type) VALUES 
-- Patients
(1, 'aarav.sharma@example.com', '{noop}password123', 'EMAIL'),
(2, 'diya.patel@example.com',   '{noop}password123', 'EMAIL'),
(3, 'dishant.verma@example.com','{noop}password123', 'EMAIL'),
(4, 'neha.iyer@example.com',    '{noop}password123', 'EMAIL'),
(5, 'kabir.singh@example.com',  '{noop}password123', 'EMAIL'),
-- Doctors (New Users created specifically for doctors)
(6, 'rakesh.mehta@example.com', '{noop}password123', 'EMAIL'),
(7, 'sneha.kapoor@example.com', '{noop}password123', 'EMAIL'),
(8, 'arjun.nair@example.com',   '{noop}password123', 'EMAIL');

-- ===================================================================================
-- 2. INSERT USER ROLES
-- ===================================================================================

INSERT INTO user_roles (user_id, roles) VALUES 
-- Patients
(1, 'PATIENT'), (2, 'PATIENT'), (3, 'PATIENT'), (4, 'PATIENT'), (5, 'PATIENT'),
-- Doctors
(6, 'DOCTOR'), (7, 'DOCTOR'), (8, 'DOCTOR');

-- ===================================================================================
-- 3. INSERT PATIENTS (IDs 1-5)
-- ===================================================================================
-- 'user_id' matches the app_user.id

INSERT INTO patient (user_id, name, gender, birth_date, email, blood_group, created_at) VALUES
(1, 'Aarav Sharma', 'MALE', '1990-05-10', 'aarav.sharma@example.com', 'O_POSITIVE', NOW()),
(2, 'Diya Patel', 'FEMALE', '1995-08-20', 'diya.patel@example.com', 'A_POSITIVE', NOW()),
(3, 'Dishant Verma', 'MALE', '1988-03-15', 'dishant.verma@example.com', 'A_POSITIVE', NOW()),
(4, 'Neha Iyer', 'FEMALE', '1992-12-01', 'neha.iyer@example.com', 'AB_POSITIVE', NOW()),
(5, 'Kabir Singh', 'MALE', '1993-07-11', 'kabir.singh@example.com', 'O_POSITIVE', NOW());

-- ===================================================================================
-- 4. INSERT DOCTORS (IDs 6-8)
-- ===================================================================================
-- 'user_id' matches the app_user.id (6, 7, 8)

INSERT INTO doctor (user_id, name, specialization, email) VALUES
(6, 'Dr. Rakesh Mehta', 'Cardiology', 'rakesh.mehta@example.com'),
(7, 'Dr. Sneha Kapoor', 'Dermatology', 'sneha.kapoor@example.com'),
(8, 'Dr. Arjun Nair', 'Orthopedics', 'arjun.nair@example.com');

-- ===================================================================================
-- 5. INSERT APPOINTMENTS
-- ===================================================================================
-- NOTICE: The column is 'doctor_user_id' because of the @MapsId relationship in Doctor.java
-- We link Patient IDs (1-5) with Doctor IDs (6-8)

INSERT INTO appointment (appointment_time, reason, doctor_user_id, patient_id) VALUES
('2025-07-01 10:30:00', 'General Checkup', 6, 2), -- Dr. Rakesh (6) with Diya (2)
('2025-07-02 11:00:00', 'Skin Rash',       7, 2), -- Dr. Sneha (7) with Diya (2)
('2025-07-03 09:45:00', 'Knee Pain',       8, 3), -- Dr. Arjun (8) with Dishant (3)
('2025-07-04 14:00:00', 'Follow-up Visit', 6, 1), -- Dr. Rakesh (6) with Aarav (1)
('2025-07-05 16:15:00', 'Consultation',    6, 4), -- Dr. Rakesh (6) with Neha (4)
('2025-07-06 08:30:00', 'Allergy Treatment', 7, 5); -- Dr. Sneha (7) with Kabir (5)

-- ===================================================================================
-- 6. RESET SEQUENCE
-- ===================================================================================
-- We manually inserted up to ID 8. Reset the sequence so new users start at 9.

SELECT setval('app_user_id_seq', (SELECT MAX(id) FROM app_user));