# CONTRIBUTING | Momentum

Thanks for your interest in contributing to Momentum! Whether you're fixing a bug, building out a feature, improving the design, or cleaning up documentation, every contribution helps. Please take a moment to read this guide before getting started.

By participating, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

> **Heads up:** Momentum is in early development (v1.0.0). The app shell, navigation, theming, and settings are implemented, while the finance, schedule, and health screens, the database layer, and the backend services are still scaffolded. See [`DOCUMENTATION.md`](DOCUMENTATION.md) for the current status of each area before picking something to work on.

---

### Ways to Contribute

- **Report bugs:** Found something broken? Let us know.
- **Suggest features:** Have an idea for finance, schedule, or health tracking?
- **Write code:** Build out scaffolded screens, the SQLite layer, sync, or fix issues.
- **Improve design:** Refine layouts, themes, accessibility, or tablet and web responsiveness.
- **Write tests:** The project has no automated tests yet, so unit and widget tests are very welcome.
- **Improve documentation:** Fix typos, clarify instructions, or fill in missing details.

---

### Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
```bash
   git clone https://github.com/<your-username>/momentum.git
   cd momentum
```
3. **Install dependencies:**
```bash
   flutter pub get
```
4. **Check your environment:**
```bash
   flutter doctor
```
5. **Create a branch** for your work:
```bash
   git checkout -b feature/your-feature-name
```
6. **Run the app:**
```bash
   flutter run
```

You'll need the Flutter SDK with a Dart SDK compatible with `^3.13.5`. See the installation section of [`DOCUMENTATION.md`](DOCUMENTATION.md) for platform-specific prerequisites.

---

### Reporting Bugs

Before opening a new issue, please search existing issues to avoid duplicates. A good bug report includes:

- A clear, descriptive title
- Steps to reproduce the problem
- Expected behavior vs. actual behavior
- Your Flutter version, target platform (Android, iOS, or Web), and device or browser
- Screenshots, screen recordings, or logs if available

**Please do not include real financial, schedule, or health information in bug reports.** Use made-up sample data instead.

---

### Suggesting Features

Open an issue describing:

- The problem or opportunity the feature addresses
- How you imagine it working in the app
- Any alternatives you considered

Momentum is intentionally minimalist, so features that keep things simple and focused are more likely to be accepted.

---

### Development Guidelines

**Project Structure**
- Shared code goes in `lib/core/`, domain code goes in `lib/features/` (split into `models/` and `screens/` per area), database files go in `lib/database/`, and backend-facing services go in `lib/services/`.
- Follow the existing structure when adding new files.

**Dart & Flutter**
- Follow the official [Dart style guide](https://dart.dev/effective-dart/style) and the project's lint rules (`flutter_lints`).
- Format your code before committing:
```bash
  dart format .
```
- Keep widgets small and focused, and comment non-obvious logic.
- Use `AppConstants` for spacing, radii, and app-wide values rather than hard-coded numbers.
- Take colors from the active `ColorScheme` instead of hard-coding them, so every theme keeps working.
- Make sure new screens respect the user's text size setting and include tooltips on icon buttons.

**Errors**
- Use the typed `Failure` classes (`DatabaseFailure`, `NetworkFailure`, `AuthFailure`, `SyncFailure`, `ValidationFailure`, `UnknownFailure`) instead of surfacing raw exceptions.
- Keep user-facing messages friendly and free of technical details.

**Dependencies**
- Open an issue before adding a new package so we can discuss whether it's needed.
- Prefer well-maintained packages with broad platform support, since Momentum targets Android, iOS, and Web.

**Versioning**
- If you change the app version, update both `AppConstants.appVersion` and `version` in `pubspec.yaml`.

**General**
- Test your changes on at least one platform before submitting, and note which one in your pull request.
- Avoid committing unrelated changes, generated files, or large unnecessary assets.
- Never commit secrets, API keys, tokens, or real user data.

---

### Testing

Before submitting, make sure the following pass:

```bash
flutter analyze
flutter test
```

If you add or change functionality, please add tests where practical. Utilities, settings, and navigation behavior are good places to start. See the testing section of [`DOCUMENTATION.md`](DOCUMENTATION.md) for the recommended test plan.

---

### Commit Messages

Write clear, concise commit messages in the present tense:

```
Add transaction model to finance feature
Fix text size not applying to drawer
Update documentation with sync design notes
```

---

### Submitting a Pull Request

1. Make sure your branch is up to date with the main branch.
2. Run `dart format .`, `flutter analyze`, and `flutter test`.
3. Push your branch to your fork.
4. Open a pull request with:
   - A clear title and description of what changed and why
   - Links to any related issues (e.g., `Closes #12`)
   - Screenshots or screen recordings for UI changes
   - The platform(s) you tested on
5. Be ready to respond to feedback. Maintainers may request changes before merging.

---

### Review Process

Maintainers will review pull requests as time allows. We may ask for revisions, suggest alternatives, or decline changes that don't fit the project's direction. Please be patient and respectful throughout the process.

---

### Questions?

If you're unsure about anything, open an issue or reach out to the maintainers. We're happy to help you get started.

---

*Last Updated: October 2026*