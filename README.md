# مدیریت مالی پروژه‌ها — Flutter Desktop (Windows, offline)

Persian RTL financial & project management app. SQLite (WAL) on a shared path, no web server, no network ports.

## Structure
```
lib/
  main.dart, theme.dart
  models/      app_user, project, expense, income
  services/    database_service (schema, PRAGMAs, transactions), auth_service (salted SHA-256), report_service (A4 landscape PDF)
  providers/   app_state (session, RBAC guards, cached dashboard totals)
  screens/     login, dashboard, project_details (fl_chart), expense_form, income_form, users, scratchpad
  widgets/     kpi_card, currency_field (live #,##0), jalali_field, ui helpers
  utils/       format (money, Jalali), calc (safe expression parser)
```

## Setup
1. Install Flutter (>= 3.27) with Windows desktop support + Visual Studio "Desktop development with C++".
2. Vazirmatn fonts (SIL OFL, see `assets/fonts/OFL.txt`) are bundled in `assets/fonts/`.
3. The Windows runner is already in `windows/`:
   ```
   flutter pub get
   flutter test
   flutter run -d windows
   ```
4. First login: `admin` / `admin123` — change it (create a new admin, delete the default one).

Database path: `%USERPROFILE%\Desktop\project_manage\projects.db` (folder auto-created).
On open: `PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL;`.

## Notes / deviations from the brief
- Added an `incomes` table (ledger) so income items can be listed/edited/deleted; `projects.total_income` is still maintained additively, inside the same transaction.
- Permissions: admin = everything; manager = add/edit income & expenses + approval toggle; viewer = read-only + scratchpad. Deleting and project creation are admin-only. Enforced in `AppState`, not just by hiding buttons.
- "مانده هزینه" = income − expenses. "تراز" = income × budget% / 100 − expenses. Budget % is editable by admin on the project page.
- Dates are stored as `yyyy/mm/dd` Jalali text; the picker is the Material (Gregorian) picker converted to Jalali.
- SQLite over SMB/DFS is only as safe as the share's locking. WAL needs shared memory (`-shm`), which is **not reliable across network shares**; if you see "database is locked"/corruption with many simultaneous clients, switch to `journal_mode = DELETE` in `database_service.dart`.
- Passwords are salted SHA-256 (no network exposure, offline); swap for PBKDF2/Argon2 if you need stronger.

## Build the portable bundle
```
flutter build windows --release
```
Copy the whole folder `build\windows\x64\runner\Release\` (exe + `flutter_windows.dll` + `data\` + plugin DLLs, including `sqlite3.dll`) to the target PCs. Run `budget_management.exe` — no installer.

## Git
```
cd budget_management
git init -b main
git add .
git commit -m "Initial commit: Flutter desktop financial & project management app"
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```
