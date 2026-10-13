# SECURITY POLICY | Momentum

Momentum is designed to hold personal finance, schedule, and health information, so protecting user data is a core priority. This policy explains how to report vulnerabilities and what you can expect from us in response.

> **Status:** Momentum is in early development (v1.0.0). Currently the app only stores two non-sensitive UI preferences (theme and text size) locally. The database, authentication, and sync features are planned, and this policy covers them as they are introduced.

---

### Supported Versions

Security updates are provided for the latest released version of the app and the current main branch.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

---

### Scope

Security concerns relevant to this project include, but are not limited to:

- Exposure or leakage of personal finance, schedule, or health data
- Weaknesses in the local SQLite database or how its data is stored on the device
- Authentication and session issues, such as insecure token handling or storage
- Vulnerabilities in the REST API or the synchronization service, including unauthorized access to another user's data
- Insecure network communication (for example, missing or misconfigured TLS)
- Server-side issues in the PostgreSQL backend, such as injection or broken access control
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
- Affected version(s), platform (Android, iOS, or Web), and environment
- Proof-of-concept code, screenshots, or logs, if available
- Any suggested fix or mitigation

Please use test data only. Do not include real personal information in your report.

---

### What to Expect

1. **Acknowledgment:** We will acknowledge your report within **72 hours**.
2. **Assessment:** We will investigate and confirm the severity and scope of the issue.
3. **Resolution:** We will work on a fix and keep you updated on progress.
4. **Disclosure:** Once a fix is released, we will coordinate public disclosure with you and credit you for the discovery if you wish.

---

### Security Practices

The project's planned security measures, described in [`DOCUMENTATION.md`](DOCUMENTATION.md), include:

- **Local data:** Finance, schedule, and health records stored on-device, with database encryption under consideration.
- **Authentication:** Token-based sign-in over HTTPS, with tokens kept in secure platform storage (Keychain on iOS, Keystore on Android) rather than in `shared_preferences`.
- **Transport security:** All REST API traffic over TLS.
- **Server storage:** Per-user data isolation, hashed credentials, and regular backups.
- **Data minimization:** Collecting only what is needed for tracking and sync, with no data shared with third parties.
- **Error handling:** User-facing messages that avoid exposing technical details.

---

### Responsible Disclosure

We ask that you:

- Give us reasonable time to fix the issue before disclosing it publicly
- Avoid accessing, modifying, or deleting data that does not belong to you
- Avoid actions that degrade the experience of other users or disrupt services
- Act in good faith and avoid privacy violations

We will not pursue action against researchers who follow this policy and report in good faith.

---

*Last Updated: October 2026*