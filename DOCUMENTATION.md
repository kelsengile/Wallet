# DOCUMENTATION | Momentum

Momentum is a minimalist personal tracking application that brings finance, scheduling, and health into one offline-first app. Today the **Finance** pillar is fully built (accounts, transactions, reminders, analytics, categories, trash, backups), along with a set of general tools (calculator, converter), a profile, search, deep personalization, and app security. **Schedule** and **Health** are still placeholders.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Features and Functionality](#features-and-functionality)
3. [Technologies and Dependencies](#technologies-and-dependencies)
4. [System & Project Architecture](#system--project-architecture)
5. [Database](#database)
6. [Installation and Configuration](#installation-and-configuration)
7. [Application Design and UI](#application-design-and-ui)
8. [Cross-Platform Notes](#cross-platform-notes)
9. [Testing and Quality Assurance](#testing-and-quality-assurance)
10. [Security and Privacy](#security-and-privacy)
11. [Known Limitations and Roadmap](#known-limitations-and-roadmap)
12. [References](#references)

---

## Project Overview

**Name:** Momentum
**Version:** 1.0.0 (build 1)
**Type:** Flutter mobile application (portrait only)
**Purpose:** Replace separate apps for money, time, and health with one organized, offline-capable tracker.

### Goals

- Keep personal tracking simple, accessible, and easy to maintain.
- Work fully offline by storing all data in a local SQLite database.
- Let the user personalize almost everything (colors, fonts, language, currency, time zone).
- Sync across devices through a backend (planned).

### The Three Pillars

| Area | Purpose | Status |
|------|---------|--------|
| Finance | Accounts, income, expenses, transfers, reminders, budgets, analytics | **Implemented** |
| Schedule | Tasks, appointments, deadlines, events | Placeholder screen |
| Health | Habits, fitness, wellness goals | Placeholder screen |

---

## Features and Functionality

### Navigation

- **Bottom navigation bar** (Finance, Schedule, Health) and **swipeable pages** in the same order (no looping). Pages are kept alive while off-screen.
- **Transparent app bar** with a menu button, the app title, and a search button. Pages draw behind it.
- **Navigation drawer** with the sections:
  - **Pages:** Finance, Schedule, Health
  - **Tools:** Calculator, Converter
  - **Preferences:** Settings, Categories, Database
  - **Help & Support:** FAQ, Rate, Feedback, About
  - A **Profile tile** (shows the profile picture, username, and name once both a picture and a username are set) and a **version footer**.
- **Floating + button** on the Finance page. Pressing it fans out four small buttons: **Income, Expense, Transfer, Reminder**. The button hides while scrolling down and returns when scrolling up. Tapping the page or scrolling retracts the small buttons.

### Finance

**Total Balance card (top of the page)**
- Shows the total balance of all active accounts, the account count, and income / expense totals for the date range last chosen in Analytics (this month by default).
- Tap the balance to open **Transaction History**; tap the income / expense figures to open **Analytics**.
- Long press to theme it (color, pattern, picture, corner style).

**My Accounts**
- Accounts are grouped by **account type** (Cash, Bank, Digital Bank, Credit, E-Wallet, Investment, Assets, Debt, Business, plus any the user adds). Within a type, the most recently used account comes first.
- **Card view:** horizontally scrolling cards using the real ID-1 card ratio (85.60 × 53.98 mm). Tap a card to flip it.
  - *Front:* category icon, account name, balance, category tag.
  - *Back:* note title and note body, type icon, and a button that opens a **linked installed app** (tap to open, long press to change or remove).
- **List view:** one row per account.
- **Eye button** hides all amounts behind `****`.
- **View button:** tap toggles card / list view; **long press** enters rearrange mode to drag account types into a new order (saved).
- **Account pop-up** (long press a card or row): the card slides in from the top and the account's history slides up from the bottom. From there the user can:
  - See history grouped by month and day (days can be collapsed), swipe a transaction to move it to the trash, or tap it for its receipt.
  - Tap the net balance to switch to account-level **Analytics**; tap Income / Expense to filter the list or open that kind's charts.
  - Tap the account name to return to history, long press it to edit the account.
  - Change the date range with the date filter.
- **Add / Edit Account:** name, initial balance (new accounts only), type, category, account theme, and a note (30-character title + 120-character body). Editing also offers **Delete Account** (moves it to the trash).
- **Account themes** (accounts, the Finance background, the Total Balance card, and the History and Analytics headers): a custom color, one of six patterns (Dots, Stripes, Grid, Waves, Diamonds, Circles) **or** a picture from camera / gallery, and one of eleven corner styles (Rounded, Soft, Sharp, Square, Pill, Beveled, Squircle, Leaf, Reverse leaf, Top round, Bottom round). Long press the Finance background, the Total Balance card, or the History / Analytics headers to edit their themes.

**Transactions**
- Four pop-ups, opened from the + button: **Income**, **Expense**, **Transfer**, **Reminder**. Each can also be reopened to **edit**.
- Fields: title, amount, date and time (calendar with hour / minute wheels), category, account (grouped by account type in the Finance order), an optional picture (camera / gallery), and an optional note.
- **Transfer:** From / To accounts with a swap button; the account chosen on one side is crossed out on the other.
- **Receipt pop-up:** a ticket-style summary (colored top, scalloped edge, dashed rows, picture, note, total) with an edit button. Reminders show a **Mark as Done** button and an **Overdue** badge when late.
- Money is stored as whole integer cents (see [Database](#database)). Account balances are computed by a SQL view, so they always match the transactions.

**Reminders**
- Type (income or expense), title, amount, due date, optional category and account, **repeat** rule (none, daily, weekly, monthly, yearly), picture, note.
- Shown in a **Reminders** section at the top of History, with overdue ones in a darker tone. Swipe to delete.
- **Mark as Done** turns the reminder into a real transaction (asking for an account if none was set) and schedules the next occurrence for repeating reminders.
- *Push notifications are not delivered yet* (see [Known Limitations](#known-limitations-and-roadmap)).

**Transaction History panel**
- Drops down from the top and stops above the nav bar. Tap the handle or swipe it up to close.
- Date filter with tabs **Day, Week, Month, Year, All, Custom**; arrows step between periods. The last used filter is remembered while the app is open.
- Tap the Income / Expense totals to filter the list; the third total is the net.

**Analytics panel**
- Same drop-down behavior and date filter as History; header totals for Income, Expense, and Net.
- Default view contains:
  - **Account Analytics:** bar chart of income vs. expense per account, grouped by type.
  - **Transaction Count:** a GitHub-style grid of day boxes (calendar layout for Day / Week / Month, week columns for longer ranges), colored by the busiest transaction kind of each day, with a glow and a detail bubble.
  - **Balance Over Time:** income and expense line graph with tappable nodes, pinch zoom (sideways and vertical), drag to pan, zoom buttons, and double-tap to reset. Selecting a day box selects the matching node and vice versa.
  - **Category Analytics:** side-by-side donut charts for income and expense categories.
- Pressing Income, Expense, or Net opens a focused view (income-only, expense-only, or the account overview with per-account rows).
- **Category pop-up:** line graph and transaction list for one category (optionally limited to one account). Expense categories with a budget show the remaining amount.
- All charts are drawn with `CustomPainter`; no chart package is used.

### Categories

A tabbed screen (**Finance**, Schedule, Health — the last two say "coming soon"). The Finance tab has:

- **Accounts:** Types and Categories.
- **Transactions:** Income, Expense, and Transfer (the Transfer category is locked).
- Add with **+**, edit with the pen or by tapping, **swipe left to delete** (with a confirmation pop-up), **drag the handle to reorder** (order is saved).
- Each item has a name and an icon chosen from 29 built-in glyphs or **imported pictures** (multi-select from the gallery; hold an icon for 3 seconds to remove it). Income and expense categories also have a **color**, and expense categories have an optional **budget**.

### Search

A full-screen search over **accounts, categories, transactions, and reminders**. Every typed word must match somewhere in the item (name, type, category, note, amount, date, etc.). Each section shows up to 25 results and links straight to the relevant pop-up, receipt, or editor.

### Profile

- Name, username (3–20 letters, digits, `.` or `_`), bio (120 characters), **profile picture**, and **banner picture**.
- **Identification:** any number of ID cards, each with a front picture, a back picture, a name, and details. Cards flip like account cards; long press a card to edit or delete it. The section can be collapsed.
- Stored as one JSON value in the `settings` table, so it is included in backups.

### Tools

**Calculator**
- Standard and **scientific** mode (parentheses, π, e, sin / cos / tan, ln, log, x², √, xʸ, 1/x, n!, %), DEG / RAD toggle, memory (MC, MR, M+, M−), live result preview, and a 50-entry history.
- A hand-written recursive-descent expression parser (no `eval` package).
- Can be **floated**: a draggable, minimizable window living in the root overlay that stays on top of every page. Only one calculator (full screen or floating) is shown at a time.

**Converter** — 14 categories, each with a built-in keypad:

| Category | Notes |
|----------|-------|
| Currency | 27 currencies, **live rates** from `open.er-api.com` (cached for one hour, with offline fallback to approximate built-in rates) |
| Finance | Loan payment, simple interest, compound interest (yearly to daily), tax / VAT (add or remove) |
| Data | Bit through TiB (decimal and binary prefixes) |
| Date | Difference between two dates; add / subtract years, months, days |
| Discount | Up to two stacked discounts plus tax |
| Volume, Speed, Length, Mass, Area, Time, Temperature | Unit conversion; temperature allows negatives |
| Numeral system | Binary, octal, decimal, hexadecimal (arbitrary size via `BigInt`) |
| BMI | Metric or imperial, category color, healthy weight range, gauge |

### Settings

- **Appearance**
  - **Theme:** follows the system until a choice is made. *General Color* opens a picker for three parts — **Main** (background), **Accent** (nav bar, drawer header, settings groups, pop-ups) and **Glyph** (text, icons, buttons). Accent and Glyph can follow Main automatically. *Specific Color* sets the colors for **Income, Expense, Transfer, Reminder**, and the **Delete** and **Done** actions.
  - **Font:** font style (8 built-in options plus **imported `.ttf` / `.otf` files**), font size (5 steps: 0.8× – 1.3×), and bold text.
  - **Animation:** on / off and speed (5 steps, implemented with Flutter's `timeDilation`).
- **Localization**
  - **Currency:** 27 currencies. Changing it offers to **convert all saved amounts** (accounts, transactions, reminders, budgets) with an editable, live-fetched exchange rate, or to change only the sign.
  - **Location:** 29 places with fixed standard-time UTC offsets. `Utils.now()` uses it for everything the user sees or saves.
  - **Language:** English, Filipino, Spanish, French, Chinese, Hindi, Arabic, Portuguese. Translation is partial (see below).
- **Security:** App Security switch with PIN and biometrics (see [Security and Privacy](#security-and-privacy)).
- **Notifications:** six switches (push, reminder alerts, budget alerts, daily summary, sound, vibration). **These are samples and do nothing yet.**

### Database screen

- Live counts of accounts, transactions, reminders, and categories.
- **Trash bin**, **Export data**, **Import data**, and **Clear all data & reset** (see [Database](#database)).

### Trash

- Lists deleted accounts and transactions grouped by the day they were deleted, with search.
- **Swipe right to restore, swipe left to delete forever**, or use the item menu. **Empty trash** removes everything.
- Anything deleted in an **earlier month** is purged automatically (at app start and whenever Trash opens).
- Restoring a transaction also restores the account(s) it belongs to. Deleting an account forever also deletes its transactions.

### Localization system

- `'Some text'.tr` looks up the English text as a key and returns the translation for the chosen language, falling back to English.
- Two tables exist in `AppStrings`: a per-language map for navigation / settings / security labels, and a list-based table (order: fil, es, fr, zh, hi, ar, pt) for profile, calculator, and converter text.
- Many screens (e.g. Finance, Categories, receipts, and most pop-up text) still use plain English strings.

### Placeholders

Schedule, Health, **FAQ, Rate, Feedback, About** show a centered label only. `services/notification.dart` is an empty file.

### Error model

A sealed `Failure` class with typed subclasses: `DatabaseFailure`, `NetworkFailure`, `AuthFailure`, `SyncFailure`, `ValidationFailure`, `UnknownFailure`. Each has a user-friendly default message. Currently the database layer produces `DatabaseFailure` and `ValidationFailure` (for example "That name already exists" or "Pick two different accounts"); the others are reserved for the planned backend.

---

## Technologies and Dependencies

### Core Stack

| Technology | Role | Status |
|------------|------|--------|
| Flutter / Dart (`^3.13.5`) | UI framework and language | In use |
| Material 3 | Design system (`useMaterial3: true`) | In use |
| SQLite (`sqflite`) | Local database `momentum.db` | **In use** |
| `local_auth` + `crypto` | Biometrics and salted PIN hashing | **In use** |
| `open.er-api.com` | Live exchange rates (plain `dart:io` HTTP) | **In use** |
| PostgreSQL + REST API | Server sync | Planned |
| Git & GitHub | Version control | In use |

### Package Dependencies (`pubspec.yaml`)

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `cupertino_icons` | ^1.0.8 | iOS-style icon font |
| `shared_preferences` | ^2.3.2 | Security settings, legacy settings migration, appearance values included in backups |
| `sqflite` | ^2.4.1 | Local SQLite database |
| `path` | ^1.9.0 | File path handling |
| `path_provider` | ^2.1.4 | App documents directory (pictures, fonts) |
| `file_picker` | ^10.3.0 | Import fonts and backups, save exported backups |
| `image_picker` | ^1.1.2 | Camera / gallery pictures |
| `installed_apps` | ^1.5.2 | List and launch apps linked to an account card (Android) |
| `local_auth` | ^2.3.0 | Fingerprint / Face unlock |
| `crypto` | ^3.0.6 | SHA-256 for the PIN hash |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Widget and unit testing |
| `flutter_lints` | ^6.0.0 | Recommended lint rules |

### Assets

`lib/database/schema.sql` and `lib/database/seed.sql` are bundled as assets.

---

## System & Project Architecture

### Folder Structure

```
momentum/
├── lib/
│   ├── core/
│   │   ├── constants.dart        # app constants, currencies, locations, languages, translations
│   │   ├── failures.dart         # typed errors
│   │   ├── font.dart             # built-in and imported fonts
│   │   ├── themes.dart           # AppTheme, AppAccent
│   │   ├── utils.dart            # formatting and date helpers
│   │   └── screens/
│   │       ├── about.dart        # placeholder
│   │       ├── calculator.dart   # full screen + floating calculator
│   │       ├── categories.dart   # category management
│   │       ├── converter.dart    # 14 converters
│   │       ├── faq.dart          # placeholder
│   │       ├── feedback.dart     # placeholder
│   │       ├── profile.dart      # profile + ID cards
│   │       ├── rate.dart         # placeholder
│   │       ├── search.dart       # global search
│   │       ├── settings.dart     # AppSettings + Settings screen
│   │       └── trash.dart        # Trash + shared confirm dialog
│   ├── database/
│   │   ├── database.dart         # Database screen
│   │   ├── helper.dart           # DatabaseHelper (all SQL)
│   │   ├── schema.sql
│   │   └── seed.sql
│   ├── features/
│   │   ├── finance.dart          # entire Finance feature
│   │   ├── schedule.dart         # placeholder
│   │   └── health.dart           # placeholder (class is named HistoryScreen)
│   ├── services/
│   │   ├── authentication.dart   # PIN, biometrics, lock gate
│   │   ├── exchange.dart         # live exchange rates
│   │   └── notification.dart     # empty
│   └── main.dart
├── pubspec.yaml
├── README.md
└── DOCUMENTATION.md
```

### Key Components

**`main()`** (`main.dart`)
Locks the app to portrait, loads `AppSettings` and `AppProfile`, runs the month-end trash purge, then starts the app.

**`MomentumApp`**
Listens to `AppSettings` and rebuilds the whole app on any change. It picks the theme (system light / dark by default, otherwise a built-in or custom theme), applies the chosen font, and wraps the navigator in a `MediaQuery` that applies the text scale and bold setting. The navigator is wrapped by `AppLockGate`.

**`HomeShell`**
Scaffold with the transparent app bar, drawer, `PageView`, `NavigationBar`, and the animated + button layer. Bottom bar and drawer share one `_select(index)` method.

**`AppSettings`** (`settings.dart`)
Singleton `ChangeNotifier` holding theme, colors, fonts, text size, animation, currency, location, language, and security state. Settings are saved in the database `settings` table (security stays in `SharedPreferences`). `load()` also migrates older `SharedPreferences` values into the database once.

**`AppTheme` / `AppAccent`** (`themes.dart`)
Builds `ThemeData` from the built-in Light / Dark schemes or from a seed color. A `ThemeExtension` (`AppAccent`) carries the **accent background** and the **glyph foreground** so any widget can read them with `AppTheme.accentOf(context)`. Helper functions compute readable text colors and contrast.

**`DatabaseHelper`** (`helper.dart`)
Singleton that opens the database, repairs it when needed, and holds every query (accounts, categories, transactions, reminders, trash, settings, backups). A `changes` `ValueNotifier` is bumped after every write so open screens reload themselves.

**`AppProfile`** (`profile.dart`)
`ChangeNotifier` for the profile data; reloads when the database changes (import / reset).

**`ExchangeRates`** (`exchange.dart`)
In-memory cache of USD-based rates, refreshed when older than one hour. Falls back to the last good rates, then to the approximate values in `AppConstants.currencies`.

**`AppLockGate` / `AppSecurity`** (`authentication.dart`)
Lock screen and PIN / biometric logic (see Security).

### State Management

No state-management package is used. The app relies on `ChangeNotifier`, `ValueNotifier`, and `ListenableBuilder`:

| Notifier | Purpose |
|----------|---------|
| `AppSettings.instance` | Theme, font, language, currency, security |
| `AppProfile.instance` | Profile data |
| `DatabaseHelper.changes` | "Data changed, reload" signal |
| `_accountThemes`, `_accountApps` (in `finance.dart`) | Per-account look and linked app, stored in `settings` |
| `_analyticsRange` | Date range shared between Analytics and the Total Balance card |
| `CalculatorFloat.pos`, `_CalcEngine.shared` | Floating calculator position and shared calculation |

### Constants

`AppConstants` is the single home for shared values: app name and version, database and asset names, money settings, preference keys, security limits, the currency / location / language lists, the spacing scale (4 / 8 / 12 / 16 / 24 / 32), radii (8 / 12 / 20), opacity levels, pop-up paddings, card geometry, and animation / text-size tables. `AppStrings` (translations) lives in the same file.

---

## Database

**Engine:** SQLite via `sqflite`. **File:** `momentum.db`, version `1`. Money is stored as **whole integer cents** (`centavosPerPeso = 100`); the helper converts to and from `double` amounts.

### Tables

| Table | Contents |
|-------|----------|
| `account_types` | Name, icon, color |
| `account_categories` | Name, sort order, icon, color |
| `accounts` | Name, type, category, initial balance, note title / body, created, `deleted_at` |
| `categories` | Name, kind (`income` / `expense` / `transfer`), icon, color, budget |
| `transactions` | Type, amount, account, destination account (transfers), category, title, note, picture path, date, `deleted_at` |
| `reminders` | Type, title, amount, category, account, due date, repeat rule, note, picture path, done flag |
| `settings` | Name / value pairs (theme, colors, fonts, language, profile JSON, per-account themes and linked apps, category order, etc.) |
| `account_balances` (view) | Current balance per account: initial balance + income − expense − transfers out + transfers in (ignores trashed rows) |

### Self-repair

There is no `onCreate`. Every time the database opens, `_ensureReady` adds any missing columns to older files, runs `schema.sql` (all `IF NOT EXISTS`), and checks that the schema and default data are valid. If not, it drops and rebuilds the finance tables from `schema.sql` and `seed.sql` in one transaction. Default icons are filled in for seed items that have none.

### Seed data

9 account types, 11 account categories, a starting **Cash** account with a zero balance, 12 income categories, 13 expense categories, and the locked **Transfer** category.

### Soft delete and trash

Accounts and transactions get a `deleted_at` timestamp instead of being removed. Trash can restore them or delete them permanently (including picture files). Items deleted in an earlier month are purged automatically.

### Backup (Export / Import)

- **Export** writes one JSON file (`momentum_backup_YYYYMMDD_HHMMSS.json`) with every table (trash included), the appearance values from `SharedPreferences`, and **base64 copies** of transaction / reminder pictures, category icons, account theme pictures, profile pictures, and imported fonts.
- **Import** validates the file (`app: "momentum"`, `tables` present, account types and the Transfer category exist), then replaces everything in one transaction; pictures are written back to the app folders. A bad file changes nothing. Settings are reloaded afterwards.
- **Clear all data & reset** rebuilds the database from the seed files, deletes saved pictures, and resets appearance and localization settings.
- Security settings (PIN, biometrics) are intentionally **not** part of backups.

### Currency conversion

Changing the currency can multiply every saved amount (initial balances, transactions, reminders, budgets) by an exchange rate in a single transaction. Amounts never drop below one cent.

---

## Installation and Configuration

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with a Dart SDK compatible with `^3.13.5`
- Android Studio or VS Code with the Flutter and Dart plugins
- Android SDK and an emulator or device (primary target, see [Cross-Platform Notes](#cross-platform-notes))
- For iOS: macOS with Xcode

### Setup

```bash
git clone <repository-url>
cd momentum
flutter pub get
flutter doctor
flutter run
```

### Platform configuration

- **Biometrics (`local_auth`):** Android needs the `USE_BIOMETRIC` permission and `MainActivity` extending `FlutterFragmentActivity`; iOS needs `NSFaceIDUsageDescription` in `Info.plist`.
- **Camera / gallery (`image_picker`):** iOS needs camera and photo-library usage descriptions.
- **Installed apps (`installed_apps`):** Android only. Listing installed apps may require the `QUERY_ALL_PACKAGES` permission (and Play Store justification) on Android 11+.
- **Internet:** Android needs the `INTERNET` permission for live exchange rates.

### Configuration notes

- **Version:** `AppConstants.appVersion` must be kept in sync manually with `version` in `pubspec.yaml`.
- **Default currency:** US dollar (`$`). It can be changed in Settings > Localization > Currency.
- **Default location:** America (Eastern, UTC−5, standard time, no daylight saving).
- **Custom fonts:** to bundle fonts with the app, add a `fonts:` section in `pubspec.yaml` and an entry in `AppFonts.builtIn`.
- **Exchange-rate provider:** change `_url` in `services/exchange.dart` to use a keyed provider.

---

## Application Design and UI

### Design principles

- **Minimalist and consistent:** spacing, radii, and opacity levels come from `AppConstants`.
- **One color language:** every panel uses the **Accent** color as its background and the **Glyph** color for text, icons, and buttons. Pop-ups, bottom sheets, cards, and settings groups all follow it.
- **Personalizable:** colors, fonts, text size, animation speed, card shapes, and pictures.
- **Responsive to text size:** cards, buttons, and icons follow the font setting only partly (`cardFollow`, `textFollow`, `addButtonFollow`) so layouts stay balanced.

### Shared UI patterns

- Rounded **bottom sheets** with a drag handle for forms and pickers (account, transaction, profile, ID, theme, app picker).
- **Chip pickers** (icon + name) for types, categories, accounts, repeat, and camera / gallery choices.
- **Confirmation pop-ups** (`showConfirmDialog`): a colored top with a zigzag edge, an item chip, explanatory points, and Cancel / Confirm buttons. Destructive actions use the red Delete color.
- **Receipt** pop-up with a scalloped edge and dashed separators.
- Top-down **History / Analytics** panels and the two-part **account pop-up** use custom slide transitions.

### Themes

- **Built-in:** Light (white / gray with black accents) and Dark (black / gray). Until the user picks one, the app follows the system light / dark setting.
- **Custom:** any Main, Accent, and Glyph color via the General Color picker (hex field plus Hue / Saturation / Brightness sliders). Readable defaults for Accent and Glyph are derived from Main with contrast checks.

---

## Cross-Platform Notes

The code is a single Flutter codebase, but several dependencies make **Android the primary target**:

- `installed_apps` is Android-only (the linked-app button on card backs).
- The app uses `dart:io` (`File`, `HttpClient`) and `sqflite`, which are not available on Flutter web without changes.
- The orientation is locked to portrait and the layout is phone-oriented.

iOS should work for everything except the linked-app feature once the platform permissions above are configured. Web, desktop, and tablet layouts are not currently supported.

---

## Testing and Quality Assurance

### Current state

- `flutter_test` and `flutter_lints` are in dev dependencies; lint rules are in `analysis_options.yaml`.
- No automated tests have been written yet.

### Commands

```bash
flutter analyze
flutter test
```

### Recommended test plan

| Area | Test type | What to verify |
|------|-----------|----------------|
| `Utils` | Unit | Currency formatting (negatives, thousands), `now()` offset, date / time formatting |
| Calculator parser (`_Parser`) | Unit | Precedence, implicit multiplication, `%`, `!`, DEG vs. RAD, division by zero, invalid input |
| Converters | Unit | Unit factors, temperature, numeral systems, date difference / add, loan and interest formulas |
| `DatabaseHelper` | Integration | Self-repair, balances view, transfers, soft delete / restore / purge, currency conversion, export → import round trip |
| `AppSettings` | Unit | Loading saved values, ignoring invalid values, migration from `SharedPreferences` |
| `AppSecurity` | Unit | PIN hash / verify, lockout after 5 attempts |
| Navigation | Widget | Bottom bar, swipe, and drawer select the same page; no swipe past first / last |
| Finance flows | Widget | Add / edit account, add income / expense / transfer / reminder, mark reminder done |
| Localization | Widget | Language change updates `.tr` text; missing keys fall back to English |

---

## Security and Privacy

### Current state

- **All data stays on the device** in a local SQLite database. The only network call is the exchange-rate request, which sends no personal data.
- **App Security:** an optional lock for the whole app.
  - Turning it on requires creating a **4–6 digit PIN**.
  - Optionally add **Touch ID / Face ID** (only methods the phone actually supports are listed; each must be verified once when enabled).
  - The PIN is stored as a **salted SHA-256 hash** (random 16-byte salt) in `SharedPreferences`, never in plain text and never in backups.
  - The app locks at start and after being in the background for **30 seconds**.
  - **5 wrong PIN attempts** trigger a 30-second wait.
  - **Forgot PIN?** requires the phone's own screen lock (PIN / pattern / biometrics) and then removes the app PIN and turns App Security off, so nobody is locked out permanently.
- Back navigation is blocked while the app is locked.
- Error messages come from `Failure` types and avoid technical detail.

### Planned measures

- Encrypting the local database (e.g. SQLCipher), given the sensitivity of finance and ID pictures.
- Token-based authentication over HTTPS with tokens in secure platform storage (Keychain / Keystore).
- Per-user data isolation, hashed credentials, and regular backups on the server.
- Storing ID card pictures in a protected location.

### Privacy notes

- Profile and ID card pictures are copied into the app's private documents folder and included (base64) in exported backups. Treat backup files as sensitive.
- The PIN hash is deliberately excluded from backups, so restoring a backup never changes the lock.

---

## Known Limitations and Roadmap

### Known limitations

- Schedule, Health, FAQ, Rate, Feedback, and About are placeholders.
- The Notifications settings are non-functional samples, and reminders do not fire push notifications (`services/notification.dart` is empty).
- Translations cover only part of the interface.
- `features/health.dart` defines the class `HistoryScreen` (name left over from an earlier version) even though it is the Health page.
- All of Finance (about 8,000 lines) lives in a single file, `features/finance.dart`.
- `AppConstants` still uses the names `centavosPerPeso` and mentions pesos in some comments, although the app now supports 27 currencies.
- Some appearance keys are read from `SharedPreferences` for backups (`_appearancePrefs`) while the live settings are stored in the database `settings` table; this is a leftover of the migration and should be unified.
- There are no automated tests.

### Roadmap

- **Schedule:** tasks, appointments, deadlines, events, calendar view.
- **Health:** records, habits, fitness tracking, wellness goals.
- **Notifications:** local notifications for reminders, budgets, and a daily summary.
- **Budgets:** surface the existing per-category budgets (alerts when almost used).
- **Content screens:** FAQ, Rate, Feedback, About.
- **Backend:** authentication, PostgreSQL, REST API, two-way synchronization.
- **Localization:** complete the translation tables for all screens.
- **Code structure:** split `finance.dart` into smaller files (models, sheets, charts, pop-ups) and add tests.

---

## References

- [Flutter documentation](https://docs.flutter.dev/)
- [Dart language documentation](https://dart.dev/guides)
- [Material 3 design guidelines](https://m3.material.io/)
- [`sqflite`](https://pub.dev/packages/sqflite)
- [`shared_preferences`](https://pub.dev/packages/shared_preferences)
- [`local_auth`](https://pub.dev/packages/local_auth)
- [`image_picker`](https://pub.dev/packages/image_picker)
- [`file_picker`](https://pub.dev/packages/file_picker)
- [`installed_apps`](https://pub.dev/packages/installed_apps)
- [`crypto`](https://pub.dev/packages/crypto)
- [`flutter_lints`](https://pub.dev/packages/flutter_lints)
- [Open Exchange Rates API (open.er-api.com)](https://www.exchangerate-api.com/docs/free)
- [SQLite documentation](https://www.sqlite.org/docs.html)
- [Flutter testing overview](https://docs.flutter.dev/testing/overview)
- Project README: [`README.md`](README.md)

---

*Last Updated: November 2026*