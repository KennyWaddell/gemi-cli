# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :---: |
| `0.1.x` / `1.0.x` (`main`) | Yes |

## Reporting a Vulnerability

If you discover a security vulnerability in **Gemi-CLI**, please **do not** open a public GitHub Issue.
Report it privately via **GitHub Private Vulnerability Reporting** in the [**Security**](https://github.com/KennyWaddell/gemi-cli/security) tab of this repository, including reproduction steps and affected file (`src/gemi.nim`, `src/gemi_core.nim`, or install scripts).

## Security Design & Hardening

- **BYOK (Bring Your Own Key):** No API keys are bundled. Each user configures their own Google AI Studio key locally.
- **Hidden key input & atomic permissions:** `gemi --set-key` and first-run setup read the API key without terminal echo (`readPasswordFromStdin`), avoiding shell history leaks (`~/.bash_history`). On POSIX systems, the directory is restricted to `0700` and the temporary file is locked to `0600` *before* writing credentials. Passing `--set-key=<value>` on the command line is explicitly rejected.
- **Header-only authentication & zero redirects:** The key is sent exclusively via the `x-goog-api-key` HTTP header (never in URL query strings) with `maxRedirects = 0` so credentials are never forwarded to another host.
- **Strict TLS verification:** Expired, self-signed, untrusted-root, and mismatched-hostname certificates abort the connection prior to sending headers or payload.
- **Attachment validation & memory bounds:** Binary attachments (`.png`, `.jpg`, `.webp`, `.pdf`) are verified against file magic signatures, with hard size caps (`1 MB` text/stdin, `8 MB` single binary, `16 MB` total) to prevent memory exhaustion on low-RAM machines.
- **Terminal output sanitization:** Control characters and ANSI escape sequences (`ESC`, `DEL`, raw C0 controls) are stripped from API responses and error messages to prevent terminal injection attacks.
- **Zero telemetry:** No analytics, background connections, or third-party endpoints.
