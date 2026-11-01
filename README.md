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
