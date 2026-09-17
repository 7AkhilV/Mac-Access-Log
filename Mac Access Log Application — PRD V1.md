# Mac Access Log Application
## Product Requirements Document — V1

### 1. Purpose

Build a lightweight native macOS application that records every time a user logs into or unlocks the Mac.

After the user successfully enters their macOS password and gains access to the Mac session, the application must open and ask the user to provide:

- Name
- Purpose of access

The application automatically records the date and time.

The record is first stored locally in SQLite. When internet connectivity is available, the record is synchronized to the configured Google Sheet.

---

# 2. User Flow

The application must handle the following situations:

### Mac Restart

```text
Mac Restart
    ↓
macOS Login Screen
    ↓
User enters macOS password
    ↓
macOS session unlocked
    ↓
Access Log Application opens
    ↓
Name + Purpose
    ↓
Submit
```

### Mac Shutdown → Power On

```text
Mac powered on
    ↓
macOS Login Screen
    ↓
User enters password
    ↓
Access Log Application opens
```

### Mac Locked

```text
Mac Locked
    ↓
User enters macOS password
    ↓
Mac unlocked
    ↓
Access Log Application opens
```

### Normal Session

The application should also handle the normal macOS login/session startup case.

The important requirement is:

> **Whenever the user successfully authenticates with the macOS password and enters/unlocks the macOS session, the Access Log application should open.**

---

# 3. Access Log Form

The application will display a simple form.

```text
┌─────────────────────────────────┐
│                                 │
│          Access Log             │
│                                 │
│  Name                           │
│  ┌───────────────────────────┐  │
│  │                           │  │
│  └───────────────────────────┘  │
│                                 │
│  Purpose                        │
│  ┌───────────────────────────┐  │
│  │                           │  │
│  │                           │  │
│  └───────────────────────────┘  │
│                                 │
│          [ Submit ]              │
│                                 │
└─────────────────────────────────┘
```

The form contains only:

1. Name
2. Purpose
3. Submit button

---

# 4. Name

The user must enter their name.

The field is mandatory.

If the user attempts to submit without a name, the application must display a validation message.

Example:

```text
Please enter your name.
```

---

# 5. Purpose

The user must enter the reason for accessing the system.

The field is mandatory.

If the user attempts to submit without a purpose, the application must display a validation message.

Example:

```text
Please enter the purpose of access.
```

---

# 6. Date and Time

The user will not enter the date or time.

The application automatically generates the timestamp when the user submits the form.

Example:

```text
Name:     Akhil
Purpose:  System maintenance

Date:     17-09-2026
Time:     09:45:32
```

The Mac's local system time will be used.

---

# 7. Local Database

The application will use SQLite for local storage.

Every successfully submitted access record must be stored locally.

### Record structure

```text
access_logs

id
name
purpose
created_at
sync_status
synced_at
```

Example:

```text
id:           1001
name:         Akhil
purpose:      System maintenance
created_at:   2026-09-17 09:45:32
sync_status:  PENDING
synced_at:    NULL
```

---

# 8. Offline Operation

The application must work without an internet connection.

If the internet is unavailable:

```text
User submits form
       ↓
Save to SQLite
       ↓
sync_status = PENDING
```

The user should still receive a successful submission message because the record has been safely stored locally.

The application must not lose the record because of an internet outage.

---

# 9. Google Sheets Synchronization

The access records will be synchronized to the configured Google Sheet.

When internet connectivity is available, the application will attempt to synchronize records that are still marked as `PENDING`.

Example:

```text
SQLite

1001 → SYNCED
1002 → SYNCED
1003 → PENDING
1004 → PENDING

          ↓

Internet available

          ↓

Google Sheets

1003
1004
```

After successful synchronization, the local records will be marked as:

```text
SYNCED
```

---

# 10. Google Sheet Format

The Google Sheet will contain the access records in tabular form.

Example:

| ID | Name | Purpose | Date | Time |
|---|---|---|---|---|
| 1001 | Akhil | System maintenance | 17-09-2026 | 09:45:32 |
| 1002 | Ravi | Inspection | 17-09-2026 | 10:12:04 |

---

# 11. Synchronization Failure

If synchronization fails:

```text
SQLite
    ↓
PENDING
```

The local record must remain stored.

It must not be deleted.

The application should attempt synchronization again when connectivity is available.

---

# 12. Duplicate Prevention

A single access record must not result in multiple rows in Google Sheets because of a retry or temporary network failure.

Each SQLite record will have a unique ID that can be used to identify the record during synchronization.

---

# 13. Application Technology

### macOS Application

**Swift + SwiftUI**

The application should be a native macOS application.

### Local Database

**SQLite**

### Google Sheets

**Google Sheets API**

### Networking

Native Swift networking APIs.

---

# 14. Application Requirements

The application should:

- Be lightweight.
- Start quickly.
- Have a simple interface.
- Work without internet.
- Store data locally first.
- Synchronize pending records when possible.
- Automatically record date and time.
- Not require a separate backend server.

---

# 15. Authentication Boundary

There is no separate login or authentication system inside the application.

The user authenticates using the existing macOS password.

The application begins its access-log flow after the macOS session has been successfully authenticated/unlocked.

The application itself only collects:

```text
Name
Purpose
```

---

# 16. Success Behavior

After a valid submission:

```text
Name + Purpose
       ↓
Validate
       ↓
Generate Date/Time
       ↓
Save SQLite
       ↓
Attempt Google Sheets sync
       ↓
Show success
       ↓
Clear form
```

Example:

```text
✓ Access recorded successfully
```

If the Mac is offline, the message can indicate that the record was saved locally and will synchronize later.

---

# 17. Required Behavior After Login/Unlock

The application must be configured so that it opens whenever the user successfully enters their macOS password and enters the active session.

This includes:

- Mac restart
- Mac shutdown and subsequent startup
- User logout and login
- Mac lock and subsequent unlock

The application should therefore treat **macOS session authentication/unlock** as the trigger for displaying the access-log form.

---

# 18. V1 Deliverable

The completed V1 will consist of one lightweight native macOS application providing this complete flow:

```text
             macOS
               │
               │
        Password entered
               │
               ▼
          Mac unlocked
               │
               ▼
      ┌─────────────────┐
      │   Access Log    │
      │                 │
      │ Name            │
      │ Purpose         │
      │                 │
      │    [Submit]     │
      └────────┬────────┘
               │
               ▼
            SQLite
               │
        ┌──────┴──────┐
        │             │
     Online         Offline
        │             │
        ▼             ▼
 Google Sheets     PENDING
        │             │
        │       Internet returns
        │             │
        └──────┬──────┘
               ▼
          Google Sheets
```

This is the complete scope for V1.