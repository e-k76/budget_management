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
