# DOCUMENTATION | Momentum

Momentum is a minimalist personal tracking application designed to help users organize and manage important aspects of their daily lives in one centralized platform. The application combines finance, scheduling, and health tracking into a simple and intuitive system, allowing users to monitor their progress, manage daily responsibilities, and maintain better personal habits. This documentation provides an overview of Momentum, including its purpose, features, system structure, functionality, and other important information needed to understand and use the application.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Features and Functionality](#features-and-functionality)
3. [Technologies and Dependencies](#technologies-and-dependencies)
4. [System & Project Architecture](#system--project-architecture)
5. [Installation and Configuration](#installation-and-configuration)
6. [Application Design and UI](#application-design-and-ui)
7. [Cross-Platform Development](#cross-platform-development)
8. [Testing and Quality Assurance](#testing-and-quality-assurance)
9. [Security and Privacy](#security-and-privacy)
10. [References](#references)

---

## Project Overview

**Name:** Momentum
**Version:** 1.0.0 
**Type:** Cross-platform mobile/web application
**Purpose:** Replace separate apps for money, time, and health with one organized, offline-capable tracker.

### Goals

- Keep personal tracking simple, accessible, and easy to maintain.
- Work offline first by storing data locally on the device.
- Sync data across devices and platforms through a backend (planned).
- Offer a clean interface that users can personalize with themes and text sizes.

### The Three Pillars

| Area | Purpose | Status |
|------|---------|--------|
| Finance | Income, expenses, savings, budgets, spending habits | Scaffolded (placeholder screen) |
| Schedule | Tasks, appointments, deadlines, events, daily activities | Scaffolded (placeholder screen) |
| Health | Habits, fitness activities, wellness goals, progress | Scaffolded (placeholder screen) |

---

## Features and Functionality

### Implemented

**Navigation**
- **Bottom navigation bar** with three destinations: Accounts, Schedule, and Health.
- **Swipeable pages:** users can swipe between the three main pages in the same order as the bottom bar. Swiping does not loop; the first and last pages are clamped.
- **Page state preservation:** each page stays alive while off-screen so its state is not lost when switching.
- **Navigation drawer** opened from the menu button in the app bar, containing:
  - A gray header showing the app name
  - **Profile** (pinned at the top)
  - **Pages:** Accounts, Schedule, Health (highlights the current page)
  - **Preferences:** Settings, Categories
  - **Help & Support:** FAQ, Rate, Feedback
  - A footer showing the app name and version (e.g. `Momentum V: 1.0.0`)
- **Search** button in the app bar that opens a dedicated search screen with an auto-focused text field.

**Settings (Appearance)**
- **Theme picker** with 10 options: Light, Dark, Red, Yellow, Orange, Brown, Blue, Green, Violet, Pink.
  - Until the user picks a theme, the app follows the system light/dark setting.
  - Once a theme is chosen it is applied everywhere and remembered between launches.
- **Text size control** with a slider and five steps: Smallest (0.8×), Small (0.9×), Default (1.0×), Big (1.15×), Biggest (1.3×). The multiplier is applied on top of the system text scale and affects every page, drawer, and dialog.
- **Persistence:** theme and text size are saved with `shared_preferences` and restored before the first frame.

**Shared utilities**
- Currency formatting in Philippine peso (e.g. `1234.5` → `₱1,234.50`), with negative-number support.
- Date formatting (`Oct 11, 2026`), time formatting (`14:05`), same-day comparison, and string capitalization.

**Error model**
- A sealed `Failure` class with typed subclasses: `DatabaseFailure`, `NetworkFailure`, `AuthFailure`, `SyncFailure`, `ValidationFailure`, and `UnknownFailure`. Each carries a user-friendly default message.

### Scaffolded (placeholder screens)

These screens exist and are reachable, but currently display only a centered label:

- Accounts, Schedule, Health (main pages)
- Profile, Categories, FAQ, Rate, Feedback
- Search (has the search field, no search logic yet)
- Settings sections **Localization**, **Security**, and **Storage** (headers only)

### Planned

- **Finance:** transactions, accounts, income/expense tracking, budgets, savings, and history.
- **Schedule:** tasks, appointments, deadlines, events, and a calendar view.
- **Health:** records, habit and fitness tracking, wellness goals, and history.
- **Trash:** recovery area for deleted items.
- **Authentication:** sign-in and account management.
- **Notifications:** reminders for schedule and health items.
- **Synchronization:** two-way sync between the local database and the server.
- **Localization, Security, and Storage settings.**
- **Categories management** shared across features.

---

## Technologies and Dependencies

### Core Stack

| Technology | Role | Status |
|------------|------|--------|
| Flutter | Cross-platform UI framework (Android, iOS, Web) | In use |
| Dart | Application language (SDK `^3.13.5`) | In use |
| Material 3 | Design system (`useMaterial3: true`) | In use |
| SQLite | Local on-device database (`momentum.db`, schema version 1) | Planned |
| PostgreSQL | Server-side database for synced data | Planned |
| REST API | Auth, sync, and data management between app and backend | Planned |
| Git & GitHub | Version control | In use |

### Package Dependencies (`pubspec.yaml`)

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `shared_preferences` | ^2.3.2 | Persist theme and text size |
| `cupertino_icons` | ^1.0.8 | iOS-style icon font |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Widget and unit testing |
| `flutter_lints` | ^6.0.0 | Recommended lint rules |

> SQLite, HTTP, and state-management packages have not been added yet. They will be introduced as the database and sync layers are built.

---

## System & Project Architecture

### Folder Structure

```
momentum/
├── lib/          
│   ├── core/
│   ├── database/
│   ├── features/
│   ├── services/
│   └── main.dart   
├── pubspec.yaml
├── README.md
└── DOCUMENTATION.md
```

### Architecture Overview

The project is organized by **layer** for shared code and by **feature** for domain code:

- **`core/`**: code used across the whole app (constants, themes, utilities, error types, and general-purpose screens).
- **`features/`**: one folder per tracking area (`finance`, `health`, `schedule`), each split into `models/` and `screens/`.
- **`database/`**: SQL schema and seed data for the local SQLite database.
- **`services/`**: backend-facing and platform services (authentication, notifications, synchronization).

### Key Components

**`MomentumApp`** (`main.dart`)
Root widget. Listens to `AppSettings` and rebuilds the whole app on any setting change. It selects the theme (system light/dark if no choice yet, otherwise the chosen theme) and wraps the navigator in a `MediaQuery` that applies the user's text scale.

**`HomeShell`** (`main.dart`)
Main scaffold holding the app bar, drawer, `PageView`, and `NavigationBar`. The bottom bar and drawer share a single `_select(index)` method that animates the `PageView` to the chosen page (250 ms, ease-in-out). A flag prevents the swipe callback from fighting the animation.

**`AppSettings`** (`core/screens/settings.dart`)
Singleton `ChangeNotifier` that stores the selected theme and text size and persists them through `SharedPreferences`. `load()` is called in `main()` before `runApp`.

**`AppTheme` / `AppThemeOption`** (`core/themes.dart`)
Defines the ten selectable themes and builds a `ThemeData` for each from a hand-tuned `ColorScheme`. A shared `_build` method applies consistent styling to the app bar, navigation bar, drawer, list tiles, dividers, and cards.

**`AppConstants`** (`core/constants.dart`)
Central place for the app name, version, database name/version, a spacing scale (4 / 8 / 16 / 24 / 32), and corner radii (8 / 12 / 20).

### Data Flow (Target Design)

1. The UI reads and writes to the **local SQLite database**, so the app works offline.
2. The **synchronization service** pushes and pulls changes through the **REST API**.
3. The backend stores the canonical copy in **PostgreSQL** for cross-device access.
4. Errors from the database, network, authentication, and sync layers are surfaced as typed `Failure` objects.

---

## Installation and Configuration

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with a Dart SDK compatible with `^3.13.5`
- An IDE such as Android Studio or VS Code with the Flutter and Dart plugins
- For Android: Android SDK and an emulator or device
- For iOS: macOS with Xcode
- For Web: a Chromium-based browser

### Setup

```bash
# 1. Clone the repository
git clone <repository-url>
cd momentum

# 2. Install dependencies
flutter pub get

# 3. Check your environment
flutter doctor

# 4. Run the app
flutter run
```

To target a specific platform:

```bash
flutter run -d chrome      # Web
flutter run -d <device-id> # Android or iOS device/emulator
```

### Configuration Notes

- **Version:** `AppConstants.appVersion` must be kept in sync manually with `version` in `pubspec.yaml`.
- **Currency:** the default symbol is `₱` (set in `Utils.formatCurrency`) and can be overridden per call.
- **Saved settings:** theme and text size are stored under the keys `settings.theme` and `settings.textSizeIndex`.
- **Database:** name `momentum.db`, version `1` (defined in `AppConstants`). The schema and seed files are not yet populated.

---

## Application Design and UI

### Design Principles

- **Minimalist:** simple layouts, outlined icons, and little visual noise.
- **Consistent:** spacing and radii come from `AppConstants`; colors come from the active `ColorScheme`.
- **Personalizable:** ten themes and five text sizes, applied instantly app-wide.
- **Accessible:** text scaling builds on the system text scale, and controls carry tooltips.

### Layout

- **App bar:** menu button (left), "Momentum" title, search button (right).
- **Body:** three swipeable pages.
- **Bottom navigation:** compact 56 px bar with Accounts, Schedule, and Health.
- **Drawer:** header, profile shortcut, page links, preference links, help links, and a version footer.

### Themes

| Theme | Brightness | Description |
|-------|------------|-------------|
| Light | Light | Light gray surface with black accents |
| Dark | Dark | Black surface with gray accents |
| Red | Dark | Faded brick red, cream text |
| Yellow | Light | Mustard, dark brown text |
| Orange | Dark | Rust orange, cream text |
| Brown | Dark | Coffee brown, cream text |
| Blue | Dark | Dusty denim blue, cream text |
| Green | Dark | Sage/olive green, cream text |
| Violet | Dark | Dusty plum, cream text |
| Pink | Dark | Dusty rose, cream text |

The color themes follow a vintage, muted palette. When a color theme is chosen, it is applied to both the light and dark slots of `MaterialApp`, so it always takes effect regardless of the system setting.

### Settings Screen

Settings are grouped under section headers (Appearance, Localization, Security, Storage). Each group is shown as a single rounded card with thin dividers between items. Light and Dark use fixed neutral fills; color themes use a darker shade of their own palette.

---

## Cross-Platform Development

Momentum uses a **single Flutter codebase** targeting:

- **Android**
- **iOS**
- **Web**

### Considerations

- **Shared UI:** all screens are built with Material 3 widgets, so layouts behave consistently across platforms.
- **Persistence:** `shared_preferences` works on all three targets. The planned SQLite layer will need a web-compatible approach (for example a WebAssembly-based SQLite package), since native SQLite is not available in the browser by default.
- **Safe areas and insets:** the drawer header accounts for the top safe-area padding on devices with notches or status bars.
- **Responsive layout:** the current layout is phone-oriented. Tablet and wide web layouts have not yet been designed.

---

## Testing and Quality Assurance

### Current State

- `flutter_test` and `flutter_lints` are included in dev dependencies.
- Lint rules are controlled by `analysis_options.yaml` (the Flutter recommended set).
- No automated tests have been written yet.

### Commands

```bash
flutter analyze    # Static analysis and lint checks
flutter test       # Run unit and widget tests
```

### Recommended Test Plan

| Area | Test Type | What to Verify |
|------|-----------|----------------|
| `Utils` | Unit | Currency formatting (negatives, thousands, decimals), date/time formatting, `isSameDay`, `capitalize` |
| `AppSettings` | Unit | Loading saved values, ignoring invalid saved values, persistence on change, no notification when unchanged |
| Theme selection | Widget | System theme followed by default; chosen theme persists across restart |
| Text scaling | Widget | Each size applies the expected multiplier on top of the system scale |
| Navigation | Widget | Bottom bar, swipe, and drawer all select the same page; no swipe past first/last page |
| Drawer | Widget | Each item opens the correct screen and closes the drawer |
| Database (future) | Integration | Schema creation, migrations, CRUD for each feature |
| Sync (future) | Integration | Offline edits, conflict handling, retry after `SyncFailure` |

---

## Security and Privacy

### Current State

- All data currently stored is limited to two non-sensitive UI preferences (theme and text size), saved locally on the device.
- No user accounts, network calls, or personal records exist yet.

### Planned Measures

- **Local data:** finance, schedule, and health records stored in the on-device SQLite database. Consider encrypting the database (for example SQLCipher) given the sensitivity of finance and health data.
- **Authentication:** token-based sign-in over HTTPS, with tokens kept in secure platform storage (Keychain on iOS, Keystore on Android) rather than in `shared_preferences`.
- **Transport security:** all REST API traffic over TLS.
- **Server storage:** PostgreSQL with per-user data isolation, hashed credentials, and regular backups.
- **Privacy controls:** a Security section in Settings (planned), plus a Storage section for managing and clearing local data and a Trash area for recoverable deletions.
- **Data minimization:** collect only what is needed for tracking and sync; no data is shared with third parties.
- **Error handling:** user-facing messages from `Failure` types avoid exposing technical details.

---

## References

- [Flutter documentation](https://docs.flutter.dev/)
- [Dart language documentation](https://dart.dev/guides)
- [Material 3 design guidelines](https://m3.material.io/)
- [`shared_preferences` package](https://pub.dev/packages/shared_preferences)
- [`flutter_lints` package](https://pub.dev/packages/flutter_lints)
- [SQLite documentation](https://www.sqlite.org/docs.html)
- [PostgreSQL documentation](https://www.postgresql.org/docs/)
- [Flutter testing overview](https://docs.flutter.dev/testing/overview)
- Project README: [`README.md`](README.md)

---

*Last Updated: October 2026*