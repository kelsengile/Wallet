# SECURITY POLICY | Wallet

Wallet is designed to hold personal finance information, including accounts, transactions, and optional ID card pictures, so protecting user data is a core priority. This policy explains how to report vulnerabilities and what you can expect from us in response.

---

### Scope

Security concerns relevant to this project include, but are not limited to:

- Exposure or leakage of personal finance data or ID pictures
- Weaknesses in the local SQLite database or how its data is stored on the device
- Weaknesses in the app lock (PIN hashing, biometric handling, lockout behavior)
- Exposure of sensitive data through backup files (export and import)
- Authentication and session issues, such as insecure token handling or storage (once a backend exists)
- Vulnerabilities in a future REST API or synchronization service, including unauthorized access to another user's data
- Insecure network communication (for example, missing or misconfigured TLS)
- Vulnerabilities in third-party dependencies or build tooling
- Sensitive information written to logs, error messages, or crash reports

Non-security bugs (such as layout glitches or typos) should be reported through regular GitHub issues instead.

---

### Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, report them privately using one of the following methods:

- Use GitHub's **private vulnerability reporting** under the repository's *Security* tab, if enabled
- Email the maintainers at **[kelsengile.dev@gmail.com]**

Please include as much of the following as possible:

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue
- Affected version(s), platform (Android or iOS), and environment
- Proof-of-concept code, screenshots, or logs, if available
- Any suggested fix or mitigation

Please use test data only. Do not include real personal or financial information in your report.

---

### What to Expect

1. **Acknowledgment:** We will acknowledge your report within **72 hours**.
2. **Assessment:** We will investigate and confirm the severity and scope of the issue.
3. **Resolution:** We will work on a fix and keep you updated on progress.
4. **Disclosure:** Once a fix is released, we will coordinate public disclosure with you and credit you for the discovery if you wish.

---

### Security Practices

**Currently in place** (see [`DOCUMENTATION.md`](DOCUMENTATION.md)):

- **Local data:** All finance records stay on the device in a local SQLite database. The only network request is for exchange rates and it sends no personal data.
- **App lock:** Optional PIN (4–6 digits) stored as a salted SHA-256 hash, with optional fingerprint or face unlock, a 30-second background timeout, and a lockout after repeated wrong attempts.
- **Backups:** The PIN and security settings are never included in exported backups.
- **Error handling:** User-facing messages that avoid exposing technical details.

**Planned:**

- **Database encryption:** Encrypting the local database (for example with SQLCipher).
- **Authentication:** Token-based sign-in over HTTPS, with tokens kept in secure platform storage (Keychain on iOS, Keystore on Android) rather than in `shared_preferences`.
- **Transport security:** All REST API traffic over TLS.
- **Server storage:** Per-user data isolation, hashed credentials, and regular backups.
- **Data minimization:** Collecting only what is needed for tracking and sync, with no data shared with third parties.

---

### Responsible Disclosure

We ask that you:

- Give us reasonable time to fix the issue before disclosing it publicly
- Avoid accessing, modifying, or deleting data that does not belong to you
- Avoid actions that degrade the experience of other users or disrupt services
- Act in good faith and avoid privacy violations

We will not pursue action against researchers who follow this policy and report in good faith.

---

*Last Updated: November 2026*