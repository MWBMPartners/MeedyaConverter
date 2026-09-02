# 🖥️ Render Farm Submission

> Copyright © 2026 MWBM Partners Ltd. All rights reserved.

---

## Status: not usable yet

Everything on this page describes the **design** for issue #346, not a
shipped feature. What exists today in `Settings → Render Farm` is a
configuration screen only:

- You can save transport preferences (chunk size, whether insecure plain
  HTTP is allowed) and add agents **manually** to a list, persisted as
  JSON in `UserDefaults`.
- Bonjour discovery is not active — the agent list's empty state says so
  directly, and there is no `_meedyaconverter-agent._tcp` advertisement
  or browser anywhere in the app.
- There is no **MeedyaConverter Agent** companion app to install on a
  remote Mac. It doesn't exist yet.
- `RenderFarmTransportAdapter` — the piece that would actually speak
  SSH/TLS/HTTP to an agent and move chunks — has no implementation
  outside its own unit tests (a mock adapter only). Nothing in the app
  can submit a job to an agent, because there is no agent to submit to
  and no wire protocol that talks to one.
- There is no "Run on" menu anywhere in the encode flow, and no
  licensing tier gates any of this — the Free/Pro/Studio split described
  in earlier drafts of this page did not correspond to anything in the
  entitlement system and has been removed.

The rest of this page is kept as the design reference for #346, so that
when the transport and agent are built, this document already describes
the target shape. Read everything below as **planned**, not present.

## Planned: Quick start

1. Install the MeedyaConverter Agent app on the remote Mac (not yet built)
2. Start the agent — it will advertise itself via Bonjour as
   `_meedyaconverter-agent._tcp`
3. On the client, open **Settings → Render Farm**
4. The discovered agent appears in the list — click **Enable** to
   register it (today you can add an agent's address manually, but there
   is nothing on the other end to connect to)
5. When submitting a job, pick the agent from a "Run on" menu (does not
   exist yet)

## Planned: Transports

| Transport | When to use | Security |
|-----------|-------------|----------|
| SSH (default) | WAN, across-subnet, anything untrusted | Key-based auth, encrypted tunnel |
| TLS | LAN with pinned self-signed cert | Cert fingerprint pinned on first connect |
| Plain HTTP | Local dev only (requires explicit opt-in) | ⚠️ Unencrypted — avoid |

The settings tab already has an "Allow insecure transports (development
only)" toggle wired to a persisted acknowledgement string, ready for
whichever transport lands first — but no transport is implemented yet, so
toggling it changes no actual network behaviour.

## Planned: Chunk size and resumability

The intent is to split source files into 4 MiB chunks by default, each
carrying its own SHA-256, with the agent rejecting a chunk that fails to
verify and the client retrying just that chunk. `RenderFarmChunk` and the
chunk-size setting exist as data types/preferences today; the upload path
that would actually move and verify chunks does not.

## Planned: Job lifecycle

1. **queued** — job accepted, waiting in the agent's queue
2. **transferring** — chunks are being uploaded and verified
3. **encoding** — FFmpeg is running on the agent
4. **finalising** — output is being written and checksummed
5. **completed** — ready for download from the agent
6. **failed** / **cancelled** — terminal states with error detail

`RenderFarmJobStatus` models these states in the engine already; nothing
drives a real job through them yet.

## Known limitations (once built)

- Agents must be reachable over the network from the client — NAT
  traversal is out of scope
- CSS / AACS-protected disc ripping is not supported over the render
  farm (App Store-only restriction)
- Cloud upload of the finished output is done by the client, not the
  agent — the completed file is pulled back first
