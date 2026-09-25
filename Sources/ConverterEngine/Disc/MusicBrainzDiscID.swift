// ============================================================================
// MeedyaConverter — MusicBrainzDiscID (Issues #502 / #503)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// FILE OVERVIEW
// -------------
// Computes the canonical **MusicBrainz Disc ID** for an Audio CD.
//
// Why this exists: `DiscTableOfContents` has carried a `musicBrainzDiscId` field
// all along and nothing has ever computed a value for it, while
// `MusicBrainzDiscLookupService` only produced the *lookup* TOC string
// (`1+2+250150+150+20150`). The lookup string is a query parameter; the Disc ID is
// the disc's stable, near-unique **identity** — and it is what MeedyaDB stores (its
// `tblDiscs.MusicBrainzDiscId` is a UNIQUE column). Without this, an identified
// music disc had no ID to submit.
//
// NOTE: this type computes the ID on demand; it does NOT write it back onto the
// TOC. `DiscTableOfContents.musicBrainzDiscId` therefore remains unset unless a
// caller assigns it, so `AudioDiscFidelity.buildCDTOCArguments` still embeds no
// `MUSICBRAINZ_DISCID` tag. Wiring that up is tracked separately.
//
// TWO IDs, deliberately (owner decision, 2026-09-20 — see #504):
//
//   • `compute(for:)` — the **music portion only**, measured to the end of the music
//     session. This is what MusicBrainz recognises, so it is what lookups use and
//     what MeedyaDB matches on.
//   • `computeWholeDisc(for:)` — the **whole physical disc**, including any data
//     session. MusicBrainz never produces this, but it is the finer physical key:
//     two pressings of the same album with different bonus content share a
//     music-only ID yet differ here. Contributed alongside, so a disc can be both
//     matched against the wider world and told apart from its siblings.
//
// On an ordinary single-session audio CD — the overwhelming majority — the two are
// identical, so nothing changes for most discs. They are DESIGNED to differ only on
// an Enhanced / CD-Extra disc (music in session 1, a data track in session 2) — but
// see the note below: today they never actually do, because nothing yet reads that
// second session in from a drive.
//
// How the end of the music session is found, best first:
//   1. the disc reported its sessions → use session 1's own lead-out (exact);
//   2. otherwise infer it from where the data track starts, less the standard
//      session gap of 11,400 sectors (6750 lead-out + 4500 lead-in + 150 pregap);
//   3. no data track at all → it is a plain audio CD, so the disc's lead-out is the
//      music lead-out.
// Only step 2 is an estimate, and it is the one thing still wanting confirmation
// against a real Enhanced CD on the hardware matrix (#504). Step 2 is also refused
// if it would place the lead-out before the last music track.
//
// IN PRACTICE, WHEN READING FROM A DRIVE, IT IS ALWAYS STEP 3 TODAY: the drive
// reader passes no `--session` to cdrdao, so only the first (music) session is
// ever read. A `DiscTableOfContents` built from a real disc therefore never
// reports more than one session and never carries a data track from a later
// session, so steps 1 and 2 above cannot fire — the whole-disc ID a real
// Enhanced/CD-Extra disc would need has nowhere to come from yet. This happens to
// be harmless for the music ID specifically: session 1's own lead-out (step 3's
// `toc.leadOutSector`, since that is all the TOC we have) is the same value
// step 1 would have used had the session table been read, so the MUSIC Disc ID
// this computes is still what MusicBrainz measures. It is not hardware-verified;
// it follows from how cdrdao and libdiscid both define a session's lead-out.
// A saved `.toc` file built by a fuller reader (or by hand) that DOES carry a
// real second session will still be read correctly by steps 1/2 above — this
// limitation is about what the drive reader currently supplies, not about this
// type's own logic.
//
// `MusicBrainzDiscLookupService.musicBrainzTOCString` uses the SAME music-session
// lead-out and must always move in step with this, or the ID and the lookup would
// describe different discs.
//
// The algorithm is MusicBrainz's published one:
//   1. Build an ASCII string of UPPERCASE hex:
//        first track (2 digits) + last track (2 digits)
//        + 100 × 8 digits of sector offsets, where slot 0 is the LEAD-OUT and
//          slots 1…99 hold the offset of the track with that number (0 if absent).
//      All offsets already include the 150-frame (2 second) pregap.
//   2. SHA-1 that ASCII string.
//   3. Base64-encode the 20-byte digest, then substitute "+"→".", "/"→"_", "="→"-".
//   Result: a 28-character string such as `gxp6QVA8pvq._RJLsqjz8ptjZXk-`.
//
// This is PURE: no disc, drive, network, or subprocess. Data tracks (Enhanced CDs)
// are excluded exactly as `MusicBrainzDiscLookupService.musicBrainzTOCString` does,
// so the Disc ID and the lookup string always describe the same set of tracks.
//
// Verification note: the expected values in the unit tests were cross-checked
// against an independent implementation of the same published algorithm, and the
// intermediate hash-input string is asserted directly (it is fully derivable from
// the spec). Behaviour against real pressed discs belongs on the manual hardware
// matrix, as with the rest of the disc stack.
// ============================================================================

import CryptoKit
import Foundation

// MARK: - MusicBrainzDiscID

/// Pure computation of a MusicBrainz Disc ID.
public enum MusicBrainzDiscID {

    /// The standard gap between two sessions on a CD, in sectors: the first
    /// session's lead-out (6750) + the second session's lead-in (4500) + the
    /// 150-frame pregap. Used only to *derive* where the music session ended on a
    /// multi-session disc that does not report its sessions.
    public static let sessionGapSectors = 6750 + 4500 + 150   // 11,400

    /// How the end of the music session was established.
    public enum LeadOutSource: Sendable, Equatable {
        /// An ordinary single-session audio CD — the disc's lead-out *is* the music
        /// lead-out, so this is exact. Also what a genuine Enhanced/CD-Extra disc
        /// gets today when read from a drive — see the file header — so this case
        /// no longer means "definitely a single-session disc", only "this run saw
        /// one session".
        case singleSession
        /// The disc reported its session layout and we used session 1's own
        /// lead-out. Exact WHEN IT FIRES — no assumptions are involved in the
        /// arithmetic. But needing no assumptions is not the same as being
        /// hardware-confirmed: the drive reader never supplies session data today
        /// (see the file header), so this path is currently just as untested
        /// against a real Enhanced CD as `derivedFromDataTrack` below — it simply
        /// never runs at all, rather than running and estimating.
        case reportedSession
        /// A multi-session disc that did not report sessions: inferred from where
        /// the data track starts, minus `sessionGapSectors`. **This is the only
        /// path that ESTIMATES rather than measures** — see #504; it wants
        /// confirming against a real Enhanced CD on the hardware matrix. (Today it
        /// additionally never fires from a drive read at all, for the same reason
        /// `reportedSession` doesn't — see the file header — so there is currently
        /// nothing to confirm it against outside a hand-built `.toc`.)
        case derivedFromDataTrack
    }

    /// Where the **music** session ends, plus how we know. `nil` when the disc has
    /// no audio tracks at all.
    ///
    /// For an ordinary audio CD this is simply the disc's lead-out. For an Enhanced
    /// CD (music in session 1, a data track in session 2) the physical lead-out sits
    /// beyond the data track, which is not what MusicBrainz measures — hence this.
    public static func musicSessionLeadOutSector(
        for toc: DiscTableOfContents
    ) -> (sector: Int, source: LeadOutSource)? {
        let audioTracks = toc.tracks.filter { !$0.isData }
        guard let lastAudioStart = audioTracks.map({ $0.startSector }).max() else { return nil }

        // 1. Best case: the disc told us where session 1 ends.
        if toc.sessions.count > 1,
           let firstSession = toc.sessions.first(where: { $0.number == 1 }),
           firstSession.leadOutSector > lastAudioStart {
            return (firstSession.leadOutSector, .reportedSession)
        }

        // 2. Otherwise infer it from the first data track that follows the music.
        let dataAfterMusic = toc.tracks
            .filter { $0.isData && $0.startSector > lastAudioStart }
            .map { $0.startSector }
            .min()
        if let dataStart = dataAfterMusic {
            let derived = dataStart - sessionGapSectors
            // Only trust the estimate if it still lands after the last music track.
            if derived > lastAudioStart {
                return (derived, .derivedFromDataTrack)
            }
        }

        // 3. A plain single-session audio CD.
        return (toc.leadOutSector, .singleSession)
    }

    /// The **MusicBrainz-compatible** Disc ID: the music portion of the disc only.
    /// This is the one MusicBrainz recognises, so it is what lookups and MeedyaDB's
    /// matching key should use. `nil` when the disc carries no audio tracks.
    ///
    /// Data tracks are excluded and the 150-frame pregap applied, matching
    /// `MusicBrainzDiscLookupService.musicBrainzTOCString(for:)` — the two MUST stay
    /// in step or the ID and the lookup would describe different discs.
    public static func compute(for toc: DiscTableOfContents) -> String? {
        guard let leadOut = musicSessionLeadOutSector(for: toc) else { return nil }
        return compute(for: toc, leadOutSector: leadOut.sector)
    }

    /// The **whole physical disc**, including any data session — what a drive sees
    /// end to end. MusicBrainz does not use this, but it is the finer physical key:
    /// two pressings of the same album with different bonus content share a
    /// music-only ID yet differ here. Recorded alongside the music-only ID so a disc
    /// can be both matched *and* told apart.
    ///
    /// On an ordinary single-session audio CD this equals `compute(for:)`. Today it
    /// ALSO equals `compute(for:)` on a real Enhanced/CD-Extra disc read from a
    /// drive, because the drive reader only reads the first (music) session — see
    /// the file header. `toc.leadOutSector` is then session 1's lead-out, the same
    /// value `compute(for:)` uses, so the two IDs cannot yet actually differ for a
    /// disc read this way. A `.toc` that genuinely carries the whole disc (a second
    /// session, or a data track past the music) will still produce a distinct value
    /// here, exactly as designed.
    public static func computeWholeDisc(for toc: DiscTableOfContents) -> String? {
        compute(for: toc, leadOutSector: toc.leadOutSector)
    }

    /// Shared body: the audio tracks of `toc` measured to an explicit lead-out.
    private static func compute(for toc: DiscTableOfContents, leadOutSector: Int) -> String? {
        let audioTracks = toc.tracks
            .filter { !$0.isData }
            .sorted { $0.number < $1.number }
        guard let first = audioTracks.first, let last = audioTracks.last else { return nil }
        return compute(
            firstTrack: first.number,
            lastTrack: last.number,
            leadOutOffset: leadOutSector + 150,
            trackOffsets: audioTracks.map { $0.startSector + 150 }
        )
    }

    /// The Disc ID from raw TOC parts. `trackOffsets` must hold one offset per
    /// track from `firstTrack` through `lastTrack` inclusive, already including
    /// the pregap. Returns `nil` when the parts are not a valid CD TOC.
    public static func compute(
        firstTrack: Int,
        lastTrack: Int,
        leadOutOffset: Int,
        trackOffsets: [Int]
    ) -> String? {
        guard let input = hashInput(
            firstTrack: firstTrack,
            lastTrack: lastTrack,
            leadOutOffset: leadOutOffset,
            trackOffsets: trackOffsets
        ) else { return nil }

        // SHA-1 is not a security choice here: the MusicBrainz Disc ID format
        // specifies it, so any other hash would produce IDs nobody else recognises.
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }

    /// The exact ASCII string that gets hashed (804 characters). Exposed because
    /// it is fully determined by the published spec, so a test can pin it without
    /// depending on any particular hash value.
    public static func hashInput(
        firstTrack: Int,
        lastTrack: Int,
        leadOutOffset: Int,
        trackOffsets: [Int]
    ) -> String? {
        guard firstTrack >= 1, lastTrack >= firstTrack, lastTrack <= 99 else { return nil }
        guard trackOffsets.count == lastTrack - firstTrack + 1 else { return nil }
        guard leadOutOffset >= 0, trackOffsets.allSatisfy({ $0 >= 0 }) else { return nil }
        // The lead-out is by definition past the last track; a TOC that says
        // otherwise is malformed (e.g. a default-constructed one with leadOut 0),
        // and would otherwise yield a confident-looking but meaningless ID.
        guard leadOutOffset > (trackOffsets.max() ?? 0) else { return nil }

        // Slot 0 is the lead-out; slots 1…99 are indexed by TRACK NUMBER.
        var slots = [Int](repeating: 0, count: 100)
        slots[0] = leadOutOffset
        for (index, offset) in trackOffsets.enumerated() {
            slots[firstTrack + index] = offset
        }

        var output = ""
        output.reserveCapacity(804)
        output += hex(firstTrack, width: 2)
        output += hex(lastTrack, width: 2)
        for slot in slots {
            output += hex(slot, width: 8)
        }
        return output
    }

    // MARK: Helpers

    /// Zero-padded UPPERCASE hex, without `String(format:)` (which would take a
    /// C-variadic and silently narrow a 64-bit value).
    private static func hex(_ value: Int, width: Int) -> String {
        let digits = String(UInt32(truncatingIfNeeded: value), radix: 16, uppercase: true)
        if digits.count >= width { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}
