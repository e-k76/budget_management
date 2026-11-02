# مدیریت مالی پروژه‌ها (Budget Management)

Offline Flutter Windows desktop app (Persian RTL, Dana font). SQLite via `sqflite_common_ffi`;
no web server, no network ports.

* Database: shared file on the DFS server; the path is `AppConfig.dbPath` in `lib/core/app_config.dart` (created on first run; WAL + `busy_timeout=5000`).
* First login: `admin` / `admin123` — change it from the Users screen.
* Roles: **admin** (everything), **manager** (add/edit income & expenses, approve, print), **viewer** (read-only).
* `incomes` is an extra table (beyond the given schema) so income entries can be listed/edited/deleted; `projects.total_income` is kept in sync in the same transaction.

## Layout
`lib/core` config, theme, formatters, calculator engine · `lib/models` · `lib/services` (database, auth, PDF report) ·
`lib/providers` (app state) · `lib/screens` · `lib/widgets`.

## Build (Windows)
Requires Windows **Developer Mode** (plugins need symlinks): `start ms-settings:developers`.
```
flutter pub get
flutter test
flutter build windows --release
```
Portable bundle: copy the whole `build\windows\x64\runner\Release\` folder; run `budget_management.exe`. No installer needed.

## Git
```
git init
git add .
git commit -m "Initial commit: budget management desktop app"
git branch -M main
git remote add origin https://github.com/<user>/<repo>.git
git push -u origin main
```

## Two databases (offline-first)
* **Local** `Desktop\project_manage\projects.db` is always written and is the only copy used when the share is unreachable.
* **Share** the `projects.db` on the DFS server (see `AppConfig.remoteDbPath`) is written too whenever it is reachable, and is what the app reads from while connected.
* Changes made while the share is unreachable are saved locally and queued (`pending_ops`). The app checks every 10 s; when the share is back it replays the queue in order, then pulls the share's current data into the local copy. The sidebar badge shows the state; click it to retry.
* First connection to a share that has no projects/expenses/incomes publishes this machine's data (users included). If the share already has data it wins, and the local file is first copied to `projects.db.pre-sync-<time>`.
* Expenses and incomes carry a unique `uid` so rows can be matched across the two files.
* `tool/import_access.dart` only touches the local file; the app pushes it to an empty share on the next sync.

## Sharing changes between PCs (v1.1)
* Every change is written to the shared DB immediately, while other PCs keep the app open (no need to close anything).
* Other PCs pull the new data when the user clicks **Refresh** (dashboard, project, expense and income screens, or the connection badge). Refresh reconnects to the share with a fresh handle, sends any pending local changes, and reloads every open screen. If the share is down it says so and keeps showing the local copy.
* Optional automatic refresh: the shared DB has a change counter (`sync_state`, bumped by triggers). Set `DatabaseService.autoRefresh = true` to make every PC poll it each second and reload on its own. It is off by default.
* The shared file prefers the rollback journal (`journal_mode = DELETE`) because WAL does not work reliably between PCs over a network share. The switch needs exclusive access, so it is tried once at connect with a very short wait and skipped if other PCs are connected; it happens the next time the app starts while nobody else is connected. Everything works either way.
* A momentary `database is locked` (another PC writing) no longer drops the app to offline mode: connect/writes retry, and only real connection failures go offline. Pending changes are kept in the local copy and sent automatically.
* Managers can now delete expenses (admins also delete incomes).

## Moving to a new shared folder
The shared DB now lives in `...\Cost\DB\projects.db` (`AppConfig.defaultRemoteDbPath`). Create the empty `DB` folder on the share, then start the app on the PC whose local copy has the data (and any pending changes) **first**: when the shared file is new/empty the app publishes that PC's whole local database (users included, pending changes already applied) and clears its pending queue. Other PCs then connect and sync from it. To point one PC somewhere else without rebuilding, put the full path of `projects.db` on the first line of `Desktop\project_manage\server_path.txt`.

## Changing the shared database without a new app version (pointer file)
Create a text file on the server: `\\dfs\Moasese Samavat\مدیریت فنی و مهندسی\Cost\db_path.txt` (`AppConfig.pointerFilePath`). Its first non-empty line (lines starting with `#` are ignored) is the full path of the current shared database, for example:

```
\\dfs\Moasese Samavat\مدیریت فنی و مهندسی\Cost\DB\projects.db
```
Every running app re-reads this file every 10 seconds. When the path changes, each app first sends its pending changes and pulls the latest data from the old database, then switches to the new one and publishes/syncs there (if the new file is empty, the first PC that connects uploads its whole local copy). The last known path is remembered, so an offline start still uses it. A path whose folder cannot be reached is ignored (the badge/tooltip shows why), so a typo cannot cut anyone off. Save the file as UTF-8 (Notepad's default). A PC with its own `Desktop\project_manage\server_path.txt` ignores the pointer file.
Tip before moving: have everyone click Refresh, so the switch starts from the latest data.

## Printing / exporting (PDF, A4 landscape)
Button «پرینت / خروجی چاپی» on: the dashboard (all projects), each project page (summary + expenses + incomes), the expense list and the income list. The print preview lets you print or save as PDF. Project page and lists export exactly what is shown (search and filters applied, noted in the report header).
In the dashboard and project reports the column «هزینه کرد کلی» counts **only approved (checked) expenses**; «مانده هزینه» = unapproved expenses; «تراز کلی» = budget − approved expenses. Expense reports list every row with its approval status and totals for all / approved / unapproved.

## Search by date range
The expense list, income list and each project page have «از تاریخ / تا تاریخ» boxes (type a Jalali date or use the calendar; the calendar-range button offers this month / last month / last 30 days / this year; ✕ clears). Both ends are inclusive and either can be left empty. It combines with the other search/filters, the totals and counts follow it, and the printed report uses the same range (shown in its header). On a project page one range applies to both the expenses and incomes tabs. Rows whose date cannot be read are hidden while a range is active.

## Sorting by date
In the expense list and in a project's expenses tab, click the «تاریخ» column header to flip between newest first (default, ↓) and oldest first (↑). Sorting uses the real calendar date (so `1405/9/1` comes before `1405/10/1` even if stored without zero padding); same-day rows stay in entry order and unreadable dates go last. The printed expense report uses the same order. The sort order is per screen and resets when the screen is reopened.

## Remember login
The login screen has «ذخیره نام کاربری و رمز عبور». Tick it and log in: the username and password are saved on this PC (encrypted with the Windows user account via `flutter_secure_storage`, not plain text) and pre-fill the form next time (no auto-login, so logging out and switching user still works). A wrong password is never saved; unticking the box and logging in forgets the saved login. If the password is changed later, the old saved one fails once — log in with the new one to update it. `path_provider_android` is pinned below 2.3 in `pubspec.yaml` so the `jni` Java bridge (needs a JDK on Windows) is not pulled in.

## In-app update («به‌روزرسانی برنامه»)
Instead of replacing the program folder by hand, each PC can update itself from a folder on the server.

**Publishing a new version (once, by whoever builds it)**
1. Take the build zip from GitHub Actions («Build Windows» → Artifacts) and unzip it.
2. Copy ALL its contents (`budget_management.exe`, `data\`, the DLLs and `version.txt`) into the update folder on the server: `\\dfs\Moasese Samavat\مدیریت فنی و مهندسی\Cost\App_Update` (`AppConfig.defaultUpdateFolder`; a different folder can be named on the first line of `Cost\update_path.txt`). Replace what is there.
3. Optional: put a short description of the changes in `notes.txt` in that folder (UTF-8); users see it before updating.

**Updating a PC**: open the app, click «به‌روزرسانی برنامه» in the side menu (an orange dot appears by itself when a newer version is waiting), then «دریافت و نصب». The app copies the new files to a temp folder, closes, a small PowerShell helper backs up the program folder, copies the new files over it (undoing everything if the copy fails) and starts the app again; the next start says whether it worked. Your data (`Desktop\project_manage`) is never touched.

How "newer" is decided: `version.txt` (the CI build number, written into every build) in the update folder vs. the one next to the exe. Builds made before this feature have no `version.txt` and count as 0, so the first updater-enabled build has to be installed by hand once. The program folder must be writable by the signed-in user WITHOUT administrator rights: run the app from a folder in your own profile (e.g. `Desktop\BudgetApp` or `Documents\BudgetApp`), not from `C:\` directly or `C:\Program Files`. The app checks this first and says so if it is not. The helper log is `%TEMP%\budget_management_update.log`.

## Tickets («تیکت‌ها»)
Every signed-in user (admin, manager, viewer) has a «ثبت تیکت» page in the side menu: choose a type (bug / suggestion / other), write a subject and a message, send. The sender does not see a list of tickets. **Only an admin** sees the tickets: for admins the menu item is «تیکت‌ها» (with a badge showing how many are not done yet) — a searchable list with a status filter; click a ticket to read it, mark it «در حال بررسی» / «انجام شد» (or back to «جدید»), or delete it. Admins can also create a ticket themselves.
Tickets travel like all other data: saved on this PC and in the shared database, queued while the server is down, and a new one shows up on the admin's PC after Refresh. The shared database is upgraded automatically the first time a PC with this version connects; older program versions simply ignore tickets. The "admin only" rule is enforced inside the program; as with all data, someone who opens the database file directly with other software could still read it.
