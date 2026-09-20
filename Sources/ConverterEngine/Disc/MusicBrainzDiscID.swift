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
// LIMITATION — multi-session (Enhanced / CD-Extra) discs: MusicBrainz uses the
// **first session's** lead-out, whereas this uses the disc's physical lead-out
// (`toc.leadOutSector`). For a CD-Extra — audio in session 1, a data track in
// session 2 — those differ, so the ID computed here will not match MusicBrainz's.
// Plain Red Book audio CDs (the overwhelming majority, and the only case the disc
// stack targets today) are unaffected. This mirrors the same assumption already
// baked into `MusicBrainzDiscLookupService.musicBrainzTOCString`, so the two always
// agree with each other; correcting both in lockstep (and verifying libdiscid's
// session-gap constant) is tracked as a follow-up.
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

    /// The Disc ID for a table of contents, or `nil` when the disc carries no
    /// audio tracks (a pure data disc) or the TOC is malformed.
    ///
    /// Data tracks are excluded and the 150-frame pregap is applied, matching
    /// `MusicBrainzDiscLookupService.musicBrainzTOCString(for:)`.
    public static func compute(for toc: DiscTableOfContents) -> String? {
        let audioTracks = toc.tracks
            .filter { !$0.isData }
            .sorted { $0.number < $1.number }
        guard let first = audioTracks.first, let last = audioTracks.last else { return nil }
        return compute(
            firstTrack: first.number,
            lastTrack: last.number,
            leadOutOffset: toc.leadOutSector + 150,
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
