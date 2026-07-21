# 🖥️ Render Farm Submission

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Overview

MeedyaConverter can submit encoding jobs to remote macOS or server agents
so long-running renders do not block the local machine. Jobs are
transferred as chunked uploads with per-chunk SHA-256 verification, and
progress streams back in real time over the same channel.

Introduced in **issue #346**. Available in the Free tier for single-agent
submission; Pro and Studio tiers add multi-agent parallel submission.

## Quick start

1. Install the **MeedyaConverter Agent** app on the remote Mac
   (separate download from the main app)
2. Start the agent — it will advertise itself via Bonjour as
   `_meedyaconverter-agent._tcp`
3. On the client, open **Settings → Render Farm**
4. The discovered agent appears in the list — click **Enable** to
   register it
5. When submitting a job, pick the agent from the "Run on" menu

## Transports

| Transport | When to use | Security |
|-----------|-------------|----------|
| SSH (default) | WAN, across-subnet, anything untrusted | Key-based auth, encrypted tunnel |
| TLS | LAN with pinned self-signed cert | Cert fingerprint pinned on first connect |
| Plain HTTP | Local dev only (requires explicit opt-in) | ⚠️ Unencrypted — avoid |

Plain HTTP is refused unless the client is configured with
`Settings → Render Farm → Allow insecure transports (development only)`.

## Chunk size and resumability

Source files are split into 4 MiB chunks by default. Each chunk carries
its own SHA-256; the agent rejects the upload if any chunk fails to
verify, and the client automatically retries just the failed chunk
rather than restarting the whole transfer.

## Job lifecycle

1. **queued** — job accepted, waiting in the agent's queue
2. **transferring** — chunks are being uploaded and verified
3. **encoding** — FFmpeg is running on the agent
4. **finalising** — output is being written and checksummed
5. **completed** — ready for download from the agent
6. **failed** / **cancelled** — terminal states with error detail

The UI polls the agent for status every 2 seconds during an active job.

## Known limitations

- Agents must be reachable over the network from the client — NAT
  traversal is out of scope
- CSS / AACS-protected disc ripping is not supported over the render
  farm (App Store-only restriction)
- Cloud upload of the finished output is done by the client, not the
  agent — the completed file is pulled back first
