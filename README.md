# مدیریت مالی پروژه‌ها — Flutter Desktop (Windows, offline)

Persian RTL financial & project management app. SQLite on a shared path, no web server, no network ports.

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
On open: `PRAGMA busy_timeout = 5000; PRAGMA journal_mode = DELETE; PRAGMA synchronous = FULL;` (see `DatabaseService.journalMode`: WAL does not work across PCs on a network share, so changes appeared late on other PCs). Each client polls a change counter every second and reloads automatically.

## Notes / deviations from the brief
- Added an `incomes` table (ledger) so income items can be listed/edited/deleted; `projects.total_income` is still maintained additively, inside the same transaction.
- Permissions: admin = everything; manager = add/edit income & expenses + approval toggle; viewer = read-only + scratchpad. Deleting and project creation are admin-only. Enforced in `AppState`, not just by hiding buttons.
- "مانده هزینه" = income − expenses. "تراز" = income × budget% / 100 − expenses. Budget % is editable by admin on the project page.
- Dates are stored as `yyyy/mm/dd` Jalali text; the picker is the Material (Gregorian) picker converted to Jalali.
- Passwords are salted SHA-256 (no network exposure, offline); swap for PBKDF2/Argon2 if you need stronger.

## Offline save-and-retry
Every income/expense/approval/project change is first written to a local queue
(`%LOCALAPPDATA%\budget_management\pending_ops.json`) and then sent to the shared DB. If the share is
unreachable the change stays queued (it survives closing the app), an orange banner shows how many are waiting, and the
app resends them in order automatically once the share is back. Each queued write carries a unique id recorded in
`applied_ops`, so a retry never applies a change twice. Changes the server rejects on replay (e.g. editing an income
another PC deleted) are dropped with a red notice. Not queued (need a live connection): user management and project
budget %. You must be able to reach the DB once to log in.

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
