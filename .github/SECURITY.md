# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

Only the latest release within a supported major version receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in MeedyaConverter, we ask that you practice **responsible disclosure**. Please do **not** open a public issue.

Instead, report vulnerabilities by emailing **<MeedyaConverter.Security@MWBMpartners.LTD>** with the following information:

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue
- Any relevant logs, screenshots, or proof-of-concept code
- Your name and contact information (optional, for follow-up)

## Response Timeline

| Stage | Timeframe |
| ----- | --------- |
| Acknowledgement of report | Within 48 hours |
| Initial assessment | Within 5 business days |
| Status update to reporter | Within 10 business days |
| Patch release (if confirmed) | Best effort, typically within 30 days |

We will keep reporters informed of progress and may request additional details during the investigation.

## Scope

The following are considered security issues within scope:

- Unauthorized access to user data or files
- Arbitrary code execution through crafted media files or inputs
- Path traversal or file system access outside intended directories
- Privilege escalation within the application
- Vulnerabilities in bundled or embedded third-party tools (FFmpeg, dovi_tool, etc.) as they relate to MeedyaConverter's usage

The following are **out of scope**:

- Vulnerabilities in upstream third-party tools that do not affect MeedyaConverter's usage
- Issues requiring physical access to the device
- Social engineering attacks
- Denial-of-service attacks that require unreasonable resource consumption

## Disclosure Policy

We request a minimum of 90 days from the initial report before any public disclosure, to allow adequate time for investigation, patching, and release.

---

Copyright 2026 MWBM Partners Ltd. All rights reserved.
