# Hospital Management System — Backend API

A backend for hospital operations — patients, doctors, appointments, insurance —
written in Spring Boot 3 on Java 21. The interesting parts are under the hood:
Patient and Doctor share a primary key with User via `@MapsId`, authentication
supports both JWT and OAuth2 with auto-provisioning on first social login, and
authorization is split across two layers — URL rules and method-level guards —
backed by a Role → Permission map rather than raw role checks.

The flow is straightforward: a user signs up and gets a Patient profile
automatically. An admin can onboard any existing user as a Doctor, assigning
them a specialization and department. Patients book appointments, doctors manage
their schedules, and insurance can be attached or detached from a patient at any
point — all behind the same auth layer.

---

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [Project Structure](#project-structure)
- [Security & Authorization](#security--authorization)
- [Setup & Running](#setup--running)
- [Configuration Reference](#configuration-reference)
- [Seed Data](#seed-data)
- [API Reference](#api-reference)
- [Error Handling](#error-handling)
- [Running Tests](#running-tests)

---

## Tech Stack

| Category | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.5.3 |
| Database | PostgreSQL |
| ORM | Spring Data JPA / Hibernate |
| Security | Spring Security 6, jjwt 0.12.6, OAuth2 Client |
| DTO Mapping | ModelMapper 3.2.0 |
| Build Tool | Maven 3.9.10 (via Maven Wrapper) |
| Boilerplate | Lombok |

---

## Architecture

**Layered request flow:**

```
HTTP Request
    │
    ▼
JwtAuthFilter          (OncePerRequestFilter — extracts Bearer token, populates SecurityContext)
    │
    ▼
Controller             (DTOs in/out, delegates to service)
    │
    ▼
Service                (@Transactional, method-level @PreAuthorize / @Secured)
    │
    ▼
Repository             (Spring Data JPA — derived queries, JPQL, native, pagination)
    │
    ▼
PostgreSQL (hospitalRDB)
```

**JWT login flow:**

```
POST /api/v1/auth/login  { username, password }
    │
    ▼
AuthenticationManager.authenticate()
    │
    ▼
CustomUserDetailsService.loadUserByUsername()   ← loads User from DB
    │
    ▼
AuthUtil.generateAccessToken()                  ← HMAC-SHA, 10-min expiry
    │
    ▼
Response: { jwt, userId }
```

**OAuth2 login flow:**

```
GET /oauth2/authorization/google  (or /github)
    │
    ▼
Spring OAuth2 Client → provider redirect → callback
    │
    ▼
OAuth2SuccessHandler.onAuthenticationSuccess()
    │
    ▼
AuthService.handleOAuth2LoginRequest()
    ├─ User not found by providerId or email  → signUpInternal() → creates User + Patient
    ├─ User found by providerId              → syncs email if changed
    └─ Email exists under different provider → throws BadCredentialsException (403)
    │
    ▼
Response: { jwt, userId }   (written directly to HttpServletResponse as JSON)
```

---

## Database Schema

Database: `hospitalRDB`, schema: `public`.

### Tables

**`app_user`**
| Column | Type | Notes |
|---|---|---|
| `id` | BIGSERIAL PK | |
| `username` | VARCHAR UNIQUE NOT NULL | Typically an email |
| `password` | VARCHAR | BCrypt; null for OAuth2 users |
| `provider_id` | VARCHAR | Provider's unique user ID |
| `provider_type` | VARCHAR | `EMAIL` `GOOGLE` `GITHUB` `FACEBOOK` `TWITTER` |

Index: `(provider_id, provider_type)` — used during OAuth2 lookup.

**`user_roles`** — `@ElementCollection` on `app_user`
| Column | Type |
|---|---|
| `user_id` | BIGINT FK → app_user |
| `roles` | VARCHAR — `ADMIN` `DOCTOR` `PATIENT` |

**`patient`** — shares PK with `app_user` via `@MapsId`
| Column | Type | Notes |
|---|---|---|
| `user_id` | BIGINT PK FK | |
| `name` | VARCHAR(40) NOT NULL | |
| `birth_date` | DATE | Indexed (`idx_patient_birth_date`) |
| `email` | VARCHAR UNIQUE NOT NULL | |
| `gender` | VARCHAR | |
| `blood_group` | VARCHAR | `A_POSITIVE` `A_NEGATIVE` `B_POSITIVE` `B_NEGATIVE` `AB_POSITIVE` `AB_NEGATIVE` `O_POSITIVE` `O_NEGATIVE` |
| `patient_insurance_id` | BIGINT FK → insurance | Nullable; owning side |
| `created_at` | TIMESTAMP | Auto-set on creation |

Unique constraint: `(name, birth_date)`.

**`doctor`** — shares PK with `app_user` via `@MapsId`
| Column | Type | Notes |
|---|---|---|
| `user_id` | BIGINT PK FK | |
| `name` | VARCHAR(100) NOT NULL | |
| `specialization` | VARCHAR(100) | |
| `email` | VARCHAR(100) UNIQUE | |

**`department`**
| Column | Type | Notes |
|---|---|---|
| `id` | BIGSERIAL PK | |
| `name` | VARCHAR(100) UNIQUE NOT NULL | |
| `head_doctor_user_id` | BIGINT FK → doctor | OneToOne |

**`my_dpt_doctors`** — ManyToMany join: department ↔ doctor
| Column | Type |
|---|---|
| `dpt_id` | BIGINT FK → department |
| `doctor_id` | BIGINT FK → doctor |

**`insurance`**
| Column | Type | Notes |
|---|---|---|
| `id` | BIGSERIAL PK | |
| `policy_number` | VARCHAR(50) UNIQUE NOT NULL | |
| `provider` | VARCHAR(100) NOT NULL | |
| `valid_until` | DATE NOT NULL | |
| `created_at` | TIMESTAMP | Auto-set on creation |

**`appointment`**
| Column | Type | Notes |
|---|---|---|
| `id` | BIGSERIAL PK | |
| `appointment_time` | TIMESTAMP NOT NULL | |
| `reason` | VARCHAR(500) | |
| `doctor_user_id` | BIGINT FK → doctor | NOT NULL |
| `patient_id` | BIGINT FK → patient | NOT NULL |

### Entity Relationships

| Relationship | Details |
|---|---|
| `patient` ↔ `app_user` | OneToOne via `@MapsId` |
| `doctor` ↔ `app_user` | OneToOne via `@MapsId` |
| `patient` → `insurance` | OneToOne; Patient owns FK; cascade ALL + orphanRemoval |
| `patient` → `appointment` | OneToMany; cascade REMOVE + orphanRemoval; `FetchType.EAGER` |
| `doctor` → `appointment` | OneToMany; `FetchType.LAZY` |
| `department` ↔ `doctor` | ManyToMany via `my_dpt_doctors` |
| `department` → `doctor` | OneToOne (headDoctor) |

---

## Project Structure

```
src/main/java/com/yogeshs/hospitalManagement/
│
├── HospitalManagementApplication.java
│
├── config/
│   └── AppConfig.java                   ← Beans: ModelMapper, BCryptPasswordEncoder, AuthenticationManager
│
├── controller/
│   ├── AuthController.java              ← /auth/login  /auth/signup
│   ├── AdminController.java             ← /admin/patients  /admin/onBoardNewDoctor
│   ├── DoctorController.java            ← /doctors/appointments
│   ├── PatientController.java           ← /patients/appointments  /patients/profile
│   └── HospitalController.java          ← /public/doctors
│
├── dto/
│   ├── LoginRequestDto.java             ← { username, password }
│   ├── LoginResponseDto.java            ← { jwt, userId }
│   ├── SignUpRequestDto.java            ← { username, password, name, roles }
│   ├── SignupResponseDto.java           ← { id, username }
│   ├── PatientResponseDto.java          ← { id, name, gender, birthDate, bloodGroup }
│   ├── DoctorResponseDto.java           ← { id, name, specialization, email }
│   ├── AppointmentResponseDto.java      ← { id, appointmentTime, reason, doctor }
│   ├── CreateAppointmentRequestDto.java ← { doctorId, patientId, appointmentTime, reason }
│   ├── OnboardDoctorRequestDto.java     ← { userId, specialization, name }
│   └── BloodGroupCountResponseEntity.java ← { bloodGroupType, count }  [no HTTP endpoint yet]
│
├── entity/
│   ├── User.java                        ← Implements UserDetails; roles as @ElementCollection
│   ├── Patient.java                     ← @MapsId User; has insurance, appointments
│   ├── Doctor.java                      ← @MapsId User; has departments, appointments
│   ├── Department.java                  ← ManyToMany doctors; OneToOne headDoctor
│   ├── Insurance.java                   ← policyNumber, provider, validUntil
│   ├── Appointment.java                 ← ManyToOne Patient, ManyToOne Doctor
│   └── type/
│       ├── RoleType.java                ← ADMIN, DOCTOR, PATIENT
│       ├── PermissionType.java          ← enum with .getPermission() → "appointment:delete" etc.
│       ├── AuthProviderType.java        ← EMAIL, GOOGLE, GITHUB, FACEBOOK, TWITTER
│       └── BloodGroupType.java          ← A_POSITIVE … O_NEGATIVE (8 values)
│
├── repository/
│   ├── UserRepository.java              ← findByUsername; findByProviderIdAndProviderType
│   ├── PatientRepository.java           ← Custom JPQL + native queries; pagination (see below)
│   ├── DoctorRepository.java            ← JpaRepository only
│   ├── AppointmentRepository.java       ← JpaRepository only
│   ├── DepartmentRepository.java        ← JpaRepository only
│   └── InsuranceRepository.java         ← JpaRepository only
│
├── security/
│   ├── WebSecurityConfig.java           ← SecurityFilterChain; URL rules; stateless; CSRF off
│   ├── JwtAuthFilter.java               ← OncePerRequestFilter; validates Bearer token
│   ├── AuthService.java                 ← login(), signup(), handleOAuth2LoginRequest()
│   ├── AuthUtil.java                    ← JWT build/parse; OAuth2 provider ID extraction
│   ├── CustomUserDetailsService.java    ← loadUserByUsername from DB
│   ├── OAuth2SuccessHandler.java        ← Writes JWT JSON to response after OAuth2 success
│   └── RolePermissionMapping.java       ← Static Role → Set<PermissionType> map
│
├── service/
│   ├── AppointmentService.java          ← createNewAppointment; reAssignToDoctor; getAllForDoctor
│   ├── DoctorService.java               ← getAllDoctors; onBoardNewDoctor
│   ├── InsuranceService.java            ← assignInsuranceToPatient; disassociateInsurance  [no HTTP endpoint]
│   └── PatientService.java              ← getPatientById; getAllPatients (paginated)
│
└── error/
    ├── ApiError.java                    ← { timeStamp, error, statusCode }
    └── GlobalExceptionHandler.java      ← @RestControllerAdvice; maps exceptions to ApiError

src/main/resources/
├── application.properties              ← DB, JPA, JWT, context path
├── application.yml                     ← OAuth2 client registrations
└── data.sql                            ← Seed data (disabled by default)
```

### PatientRepository — Implemented Custom Queries

All of these exist in code but **no HTTP endpoint currently exposes them**:

| Method | Type | Description |
|---|---|---|
| `findByName(String)` | Derived | Exact name match |
| `findByBirthDateOrEmail(LocalDate, String)` | Derived | OR condition |
| `findByBirthDateBetween(LocalDate, LocalDate)` | Derived | Date range |
| `findByNameContainingOrderByIdDesc(String)` | Derived | Name search, descending by ID |
| `findByBloodGroup(BloodGroupType)` | JPQL | Filter by blood group |
| `findByBornAfterDate(LocalDate)` | JPQL | Born after a date |
| `countEachBloodGroupType()` | JPQL | Returns `List<BloodGroupCountResponseEntity>` |
| `findAllPatients(Pageable)` | Native SQL | Paginated; used by `GET /admin/patients` |
| `updateNameWithId(String, Long)` | JPQL `@Modifying` | Bulk name update |
| `findAllPatientWithAppointment()` | JPQL `LEFT JOIN FETCH` | Avoids N+1 when loading appointments |

---

## Security & Authorization

### Role → Permission Mapping

Defined in `RolePermissionMapping.java`. `User.getAuthorities()` returns both `ROLE_<n>` and all fine-grained permission strings (e.g. `"appointment:delete"`) as `SimpleGrantedAuthority` — populated via `permission.getPermission()`, not `permission.name()`.

| Role | Permissions |
|---|---|
| `PATIENT` | `patient:read`, `appointment:read`, `appointment:write` |
| `DOCTOR` | `patient:read`, `appointment:read`, `appointment:write`, `appointment:delete` |
| `ADMIN` | All above + `patient:write`, `user:manage`, `report:view` |

### URL Access Rules

Evaluated top-to-bottom in `WebSecurityConfig`. Sessions are `STATELESS`. CSRF is disabled.

| Pattern | Rule |
|---|---|
| `/public/**`, `/auth/**` | Public |
| `DELETE /admin/**` | `hasAnyAuthority(APPOINTMENT_DELETE.name(), USER_MANAGE.name())` |
| `/admin/**` | Requires `ROLE_ADMIN` |
| `/doctors/**` | Requires `ROLE_DOCTOR` or `ROLE_ADMIN` |
| `/patients/**` | No URL-level role restriction — falls through to `anyRequest().authenticated()` |
| All others | Must be authenticated |

### Method-Level Security

`@EnableMethodSecurity` is active. Applied at the service layer:

| Method | Guard | Rule |
|---|---|---|
| `AppointmentService.createNewAppointment()` | `@Secured("ROLE_PATIENT")` | PATIENT only |
| `AppointmentService.reAssignAppointmentToAnotherDoctor(appointmentId, doctorId)` | `@PreAuthorize` | Has `appointment:write` permission OR the authenticated user's ID equals the `doctorId` being assigned to |
| `AppointmentService.getAllAppointmentsOfDoctor(doctorId)` | `@PreAuthorize` | ADMIN sees any; DOCTOR only if their ID matches `doctorId` |

### JWT Details

| Property | Value |
|---|---|
| Algorithm | HMAC-SHA |
| Claims | `sub` (username), `userId` (as String), `iat`, `exp` |
| Expiry | 10 minutes (`1000 * 60 * 10` ms) |
| Header | `Authorization: Bearer <token>` |

---

## Setup & Running

Maven is not required — the Maven Wrapper (`mvnw` / `mvnw.cmd`) downloads it automatically.

### Prerequisites

| Tool | Version |
|---|---|
| Java | 21 |
| PostgreSQL | 14+ |
| Git | Any |

### 1 — Clone

```bash
git clone https://github.com/shendeyogesh11/Hospital-Management-System.git
cd Hospital-Management-System
```

### 2 — Create the Database

**macOS (Homebrew):**
```bash
brew services start postgresql@16
psql postgres -c 'CREATE DATABASE "hospitalRDB";'
```

**Windows (pgAdmin or psql):**
```sql
CREATE DATABASE "hospitalRDB";
```

### 3 — Configure

Edit `src/main/resources/application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/hospitalRDB
spring.datasource.username=postgres
spring.datasource.password=YOUR_POSTGRES_PASSWORD

jwt.secretKey=SOME_LONG_RANDOM_STRING_MINIMUM_64_CHARACTERS_FOR_HMAC_SHA
```

> **macOS Homebrew default:** The PostgreSQL superuser is your system username with no password. Set `username` to your system username and leave `password` blank.

**OAuth2 (optional):**

`application.yml` reads credentials from environment variables — `${GOOGLE_CLIENT_ID}` is not a placeholder to fill in the file, it means the app reads from your shell environment at startup. Set them before running:

**macOS / Linux:**
```bash
export GOOGLE_CLIENT_ID=your_google_client_id
export GOOGLE_CLIENT_SECRET=your_google_client_secret
export GITHUB_CLIENT_ID=your_github_client_id
export GITHUB_CLIENT_SECRET=your_github_client_secret
```

**Windows (Command Prompt):**
```cmd
set GOOGLE_CLIENT_ID=your_google_client_id
set GOOGLE_CLIENT_SECRET=your_google_client_secret
set GITHUB_CLIENT_ID=your_github_client_id
set GITHUB_CLIENT_SECRET=your_github_client_secret
```

If OAuth2 is not needed, remove or comment out the `google` and `github` registration blocks in `application.yml` to avoid startup errors from unresolved variables.

OAuth2 redirect URIs to register in your provider console:
- Google: `http://localhost:8080/login/oauth2/code/google`
- GitHub: `http://localhost:8080/login/oauth2/code/github`

> **Twitter OAuth2** is configured in `application.yml` with hardcoded placeholder credentials. It is non-functional and should be ignored or removed.

### 4 — Run

**macOS / Linux** (make wrapper executable first time only):
```bash
chmod +x mvnw
./mvnw spring-boot:run
```

**Windows:**
```cmd
mvnw.cmd spring-boot:run
```

To build and run a JAR:
```bash
# macOS / Linux
./mvnw clean package -DskipTests
java -jar target/hospitalManagement-0.0.1-SNAPSHOT.jar

# Windows
mvnw.cmd clean package -DskipTests
java -jar target\hospitalManagement-0.0.1-SNAPSHOT.jar
```

### 5 — Verify

App runs on port `8080` with context path `/api/v1`:

```bash
curl http://localhost:8080/api/v1/public/doctors
# Returns [] if no seed data, or the list of doctors
```

---

## Configuration Reference

`src/main/resources/application.properties`:

| Property | Default | Description |
|---|---|---|
| `spring.datasource.url` | `jdbc:postgresql://localhost:5432/hospitalRDB` | DB connection URL |
| `spring.datasource.username` | `postgres` | DB user |
| `spring.datasource.password` | — | DB password |
| `server.servlet.context-path` | `/api/v1` | All endpoints are prefixed with this |
| `spring.jpa.hibernate.ddl-auto` | `update` | Auto-creates/updates schema on startup |
| `spring.jpa.show-sql` | `true` | Logs generated SQL to console |
| `spring.jpa.defer-datasource-initialization` | `true` | Ensures `data.sql` runs after Hibernate creates the schema |
| `spring.sql.init.mode` | `never` | Set to `always` once to run `data.sql`, then revert |
| `spring.sql.init.continue-on-error` | `true` | Seed duplicate inserts don't abort startup |
| `jwt.secretKey` | — | HMAC-SHA signing key; minimum 64 characters |

---

## Seed Data

`data.sql` is disabled by default (`spring.sql.init.mode=never`). To load it: set to `always`, start the app once, then revert to `never`.

**Users (IDs 1–8), all with password `password123`:**

| ID | Email | Role | Detail |
|---|---|---|---|
| 1 | aarav.sharma@example.com | PATIENT | Blood: O+ |
| 2 | diya.patel@example.com | PATIENT | Blood: A+ |
| 3 | dishant.verma@example.com | PATIENT | Blood: A+ |
| 4 | neha.iyer@example.com | PATIENT | Blood: AB+ |
| 5 | kabir.singh@example.com | PATIENT | Blood: O+ |
| 6 | rakesh.mehta@example.com | DOCTOR | Cardiology |
| 7 | sneha.kapoor@example.com | DOCTOR | Dermatology |
| 8 | arjun.nair@example.com | DOCTOR | Orthopedics |

**Appointments seeded:**

| Patient | Doctor | Reason |
|---|---|---|
| Diya (2) | Dr. Rakesh (6) | General Checkup |
| Diya (2) | Dr. Sneha (7) | Skin Rash |
| Dishant (3) | Dr. Arjun (8) | Knee Pain |
| Aarav (1) | Dr. Rakesh (6) | Follow-up Visit |
| Neha (4) | Dr. Rakesh (6) | Consultation |
| Kabir (5) | Dr. Sneha (7) | Allergy Treatment |

---

## API Reference

**Base URL:** `http://localhost:8080/api/v1`

Protected endpoints require: `Authorization: Bearer <jwt>`

---

### Auth

#### `POST /auth/signup`

Registers a new user and auto-creates a linked Patient record.

**Auth:** None

**Request:**
```json
{
  "username": "john.doe@example.com",
  "password": "securePassword123",
  "name": "John Doe",
  "roles": ["PATIENT"]
}
```

**Response `200 OK`:**
```json
{
  "id": 9,
  "username": "john.doe@example.com"
}
```

**Errors:** `500` if username already exists (`IllegalArgumentException` caught by global handler).

---

#### `POST /auth/login`

**Auth:** None

**Request:**
```json
{
  "username": "john.doe@example.com",
  "password": "securePassword123"
}
```

**Response `200 OK`:**
```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "userId": 9
}
```

**Errors:** `401` bad credentials, `404` user not found.

---

#### `GET /oauth2/authorization/google`
#### `GET /oauth2/authorization/github`

Browser-initiated redirect flow. On success, returns `{ jwt, userId }` written to the response body. On failure, forwarded to the global exception handler as JSON.

---

### Public

#### `GET /public/doctors`

**Auth:** None

**Response `200 OK`:**
```json
[
  { "id": 6, "name": "Dr. Rakesh Mehta", "specialization": "Cardiology", "email": "rakesh.mehta@example.com" },
  { "id": 7, "name": "Dr. Sneha Kapoor", "specialization": "Dermatology", "email": "sneha.kapoor@example.com" }
]
```

---

### Patient

#### `POST /patients/appointments`

Books a new appointment. No URL-level role rule on `/patients/**` — access is controlled entirely by `@Secured("ROLE_PATIENT")` at the service layer.

**Auth:** `ROLE_PATIENT` (method-level)

**Request:**
```json
{
  "doctorId": 6,
  "patientId": 1,
  "appointmentTime": "2025-11-10T14:30:00",
  "reason": "Chest pain follow-up"
}
```

**Response `201 Created`:**
```json
{
  "id": 7,
  "appointmentTime": "2025-11-10T14:30:00",
  "reason": "Chest pain follow-up",
  "doctor": {
    "id": 6,
    "name": "Dr. Rakesh Mehta",
    "specialization": "Cardiology",
    "email": "rakesh.mehta@example.com"
  }
}
```

**Errors:** `403` insufficient role, `500` doctor or patient ID not found.

---

#### `GET /patients/profile`

**Auth:** Any authenticated user (no role restriction at URL or method level)

**Response `200 OK`:**
```json
{
  "id": 4,
  "name": "Neha Iyer",
  "gender": "FEMALE",
  "birthDate": "1992-12-01",
  "bloodGroup": "AB_POSITIVE"
}
```

---

### Doctor

#### `GET /doctors/appointments`

Returns all appointments for the currently authenticated doctor. The doctor's ID is pulled from the JWT principal in the controller, then passed to the service where `@PreAuthorize` enforces that a DOCTOR can only retrieve their own; ADMIN can retrieve any doctor's.

**Auth:** `ROLE_DOCTOR` or `ROLE_ADMIN` (URL-level)

**Response `200 OK`:**
```json
[
  {
    "id": 1,
    "appointmentTime": "2025-07-01T10:30:00",
    "reason": "General Checkup",
    "doctor": {
      "id": 6,
      "name": "Dr. Rakesh Mehta",
      "specialization": "Cardiology",
      "email": "rakesh.mehta@example.com"
    }
  }
]
```

---

### Admin

#### `GET /admin/patients`

Paginated list of all patients.

**Auth:** `ROLE_ADMIN`

**Query params:**

| Param | Default | Description |
|---|---|---|
| `page` | `0` | Page index (0-based) |
| `size` | `10` | Page size |

**Response `200 OK`:**
```json
[
  { "id": 1, "name": "Aarav Sharma", "gender": "MALE", "birthDate": "1990-05-10", "bloodGroup": "O_POSITIVE" }
]
```

---

#### `POST /admin/onBoardNewDoctor`

Promotes an existing `app_user` to Doctor. Creates a `doctor` record and adds `ROLE_DOCTOR` to the user's roles.

**Auth:** `ROLE_ADMIN`

**Request:**
```json
{
  "userId": 9,
  "name": "Dr. John Doe",
  "specialization": "Neurology"
}
```

**Response `201 Created`:**
```json
{
  "id": 9,
  "name": "Dr. John Doe",
  "specialization": "Neurology",
  "email": null
}
```

**Errors:** `500` if userId not found or user is already a doctor.

---

## Error Handling

All errors return a standardized `ApiError` body:

```json
{
  "timeStamp": "2025-11-10T14:30:00.123456",
  "error": "Authentication failed: Bad credentials",
  "statusCode": "UNAUTHORIZED"
}
```

| Exception | Status |
|---|---|
| `UsernameNotFoundException` | `404 Not Found` |
| `AuthenticationException` | `401 Unauthorized` |
| `JwtException` | `401 Unauthorized` |
| `AccessDeniedException` | `403 Forbidden` |
| Any other `Exception` | `500 Internal Server Error` |

JWT and access-denied exceptions thrown inside the filter chain are forwarded via `HandlerExceptionResolver`, so they return JSON rather than Spring Security's default HTML error page.

---

## Running Tests

Tests use `@SpringBootTest` (full application context + real DB). PostgreSQL must be running and `hospitalRDB` must exist.

```bash
# macOS / Linux
./mvnw test

# Windows
mvnw.cmd test
```

| Class | Coverage |
|---|---|
| `HospitalManagementApplicationTests` | Verifies the Spring context loads without errors |
| `InsuranceTests` | Calls `InsuranceService.assignInsuranceToPatient()` and `disassociateInsuranceFromPatient()` against the real DB. Also contains a stub for `createNewAppointment` with the body commented out. |
| `PatientTests` | Calls `patientRepository.findAllPatientWithAppointment()` and `findAllPatients(Pageable)`. Other query method calls are present but commented out — they serve as usage examples. |

---

## Author

**Yogesh Shende** — [@shendeyogesh11](https://github.com/shendeyogesh11)
