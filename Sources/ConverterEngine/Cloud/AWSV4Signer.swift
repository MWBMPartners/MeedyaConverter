// ============================================================================
// MeedyaConverter — AWSV4Signer (Issue #459, Bundle 1b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A from-the-spec implementation of AWS Signature Version 4 (SigV4) request
// signing — https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
//
// Every function here is a PURE function of its arguments:
//   - No singleton state, no `@unchecked Sendable`, no mutable class
//     instances (the closest thing to shared state, `Calendar`/`Date`
//     formatting, is done with value-type `Calendar` built fresh per
//     call — never a cached `DateFormatter`, which is not guaranteed
//     thread-safe for concurrent formatting).
//   - `sign(...)` NEVER calls `Date()` itself — the caller always
//     supplies `date`. Production callers (`S3Uploader`) pass `Date()`
//     at their own call site; `AWSV4SignerTests` passes AWS's fixed
//     documented timestamps so every output is byte-for-byte
//     reproducible against AWS's own published vectors.
//
// Correctness verification (this file's whole reason for existing is
// security-sensitive cryptographic signing, so "trust me" is not
// enough): `AWSV4SignerTests` reproduces four independent, cross-checked
// cases from AWS's own "Signature Version 4 Test Suite" — see that
// file's doc comment for exactly which ones, why those four, and the
// citation for where they came from. Every one of those vectors was
// ALSO independently recomputed with Python's stdlib `hashlib`/`hmac`
// (not this Swift code) before being written into the test file, so
// the fixtures are not merely "copied from a web page" — they are
// numerically self-consistent (SHA-256 of the canonical request really
// does equal the published hash; the chained-HMAC signing key really
// does produce the published signature).
//
// Every intermediate step of the algorithm — canonical request, its
// hash, the string-to-sign, the derived signing key, and the final
// signature — is exposed as its own `public static` function so tests
// (and callers debugging a signature mismatch against a real AWS
// error response) can inspect each stage independently, not just the
// final `Authorization` header.
// ---------------------------------------------------------------------------

// MARK: - AWSV4Signer

public enum AWSV4Signer {

    // MARK: - Credentials

    /// The access key ID / secret access key (and optional STS session
    /// token) used to sign a request.
    ///
    /// Never logged, never written to argv, never hardcoded — see
    /// `S3Uploader.loadCredential(apiKeyManager:bucket:region:endpoint:)`
    /// for the one production path that constructs this type, which
    /// reads the secret exclusively from the system Keychain via
    /// `APIKeyManager`.
    public struct Credentials: Sendable {
        public let accessKeyID: String
        public let secretAccessKey: String

        /// Optional STS session token for temporary credentials. When
        /// present, the caller is responsible for ALSO adding an
        /// `x-amz-security-token` header (with this same value) to the
        /// `headers` dictionary passed to `sign(...)` and including it
        /// in `signedHeaders` — this type does not do that
        /// automatically, since which headers get signed is entirely
        /// the caller's decision (`headers` is signed exactly as
        /// given, nothing added or removed).
        public let sessionToken: String?

        public init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
            self.accessKeyID = accessKeyID
            self.secretAccessKey = secretAccessKey
            self.sessionToken = sessionToken
        }
    }

    // MARK: - SigningResult

    /// Every step of the SigV4 algorithm for one request, in the order
    /// AWS's documentation presents them. Exposed as a flat struct
    /// (rather than only returning the final header) precisely so
    /// tests can assert on each stage against AWS's own published
    /// intermediate values, not just trust that a correct final
    /// signature implies every step along the way was correct.
    public struct SigningResult: Sendable {
        /// Task 1 output: `HTTPMethod\nCanonicalURI\nCanonicalQueryString\n
        /// CanonicalHeaders\n\nSignedHeaders\nHashedPayload`.
        public let canonicalRequest: String

        /// Hex SHA-256 of `canonicalRequest`.
        public let hashedCanonicalRequest: String

        /// `<dateStamp>/<region>/<service>/aws4_request`.
        public let credentialScope: String

        /// Task 2 output: `AWS4-HMAC-SHA256\n<amzDate>\n<credentialScope>\n
        /// <hashedCanonicalRequest>`.
        public let stringToSign: String

        /// Task 3's derived signing key
        /// (`HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service),
        /// "aws4_request")`), hex-encoded so tests can compare it
        /// against AWS's published signing-key fixtures without
        /// exposing raw key bytes through the normal call path.
        public let signingKeyHex: String

        /// Task 4 output: hex HMAC-SHA256 of `stringToSign` under the
        /// derived signing key. This is the value AWS calls "the
        /// signature".
        public let signature: String

        /// Semicolon-joined, lower-cased, sorted header names that were
        /// included in the signature — must equal exactly the
        /// `SignedHeaders=` value a verifier will check against.
        public let signedHeaders: String

        /// The complete `Authorization` header value:
        /// `AWS4-HMAC-SHA256 Credential=<accessKeyID>/<credentialScope>,
        /// SignedHeaders=<signedHeaders>, Signature=<signature>`.
        public let authorizationHeader: String
    }

    /// Sentinel payload-hash value AWS accepts in place of a real
    /// SHA-256 for S3 requests whose body is streamed rather than
    /// buffered up front (e.g. a large file `PUT`). See
    /// `S3Uploader.buildSignedUploadRequest` for why the file upload
    /// path uses this instead of hashing the file.
    public static let unsignedPayload = "UNSIGNED-PAYLOAD"

    // MARK: - Public entry point

    /// Computes the full SigV4 signature for one request.
    ///
    /// - Parameters:
    ///   - method: HTTP method, e.g. `"GET"` or `"PUT"`, used verbatim
    ///     (AWS's algorithm does not case-normalize it, and neither
    ///     does this function — callers must already pass the
    ///     uppercase form AWS expects).
    ///   - path: The request's absolute path (e.g. `"/my-object.mp4"`),
    ///     already logically un-escaped — this function performs its
    ///     own SigV4 percent-encoding per path segment (see
    ///     `canonicalURI(path:)`); do not pre-percent-encode it
    ///     yourself, or it will be double-encoded.
    ///   - queryItems: The request's query parameters, unencoded. Taken
    ///     as an explicit `[URLQueryItem]` rather than parsed back out
    ///     of a `URL` because `Foundation.URL`'s `.query` accessor has
    ///     historically inconsistent percent-decoding behaviour across
    ///     OS versions — passing the already-decoded name/value pairs
    ///     directly removes that ambiguity from a security-sensitive
    ///     code path.
    ///   - headers: Every header to include in the signature. Header
    ///     *names* are case-insensitive per RFC 7230 and are
    ///     lower-cased/sorted by this function; header *values* are
    ///     trimmed and have internal whitespace runs collapsed to a
    ///     single space, per the SigV4 canonicalization rule. Must
    ///     include at minimum a `Host` entry — this function does not
    ///     inject one for you, so the exact header set that gets
    ///     signed is the exact header set the caller must also
    ///     actually send.
    ///   - payloadHash: The hex SHA-256 of the request body (see
    ///     `sha256Hex(data:)`), or `AWSV4Signer.unsignedPayload` for a
    ///     streamed body AWS lets you skip hashing. Whatever value is
    ///     passed here MUST equal the `x-amz-content-sha256` header
    ///     value the caller actually sends — S3 rejects a mismatch.
    ///   - date: The request timestamp. See this type's file-overview
    ///     doc comment for why this is never defaulted to `Date()`
    ///     internally.
    ///   - region: AWS region, e.g. `"us-east-1"`.
    ///   - service: AWS service signing name, e.g. `"s3"`.
    ///   - credentials: The access key / secret key to sign with.
    /// - Returns: Every intermediate value plus the final
    ///   `Authorization` header.
    public static func sign(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String],
        payloadHash: String,
        date: Date,
        region: String,
        service: String,
        credentials: Credentials
    ) -> SigningResult {
        let stamp = dateStamp(from: date)
        let amzDateString = amzDate(from: date)

        let uri = canonicalURI(path: path)
        let query = canonicalQueryString(queryItems: queryItems)
        let (headersBlock, signed) = canonicalHeaders(headers)

        let creq = canonicalRequest(
            method: method,
            canonicalURI: uri,
            canonicalQueryString: query,
            canonicalHeadersBlock: headersBlock,
            signedHeaders: signed,
            hashedPayload: payloadHash
        )
        let hashedCreq = sha256Hex(creq)

        let scope = credentialScope(dateStamp: stamp, region: region, service: service)
        let sts = stringToSign(amzDate: amzDateString, credentialScope: scope, hashedCanonicalRequest: hashedCreq)

        let key = signingKey(secretAccessKey: credentials.secretAccessKey, dateStamp: stamp, region: region, service: service)
        let signatureBytes = hmacSHA256(key: key, message: Data(sts.utf8))
        let signatureHex = hex(signatureBytes)

        let authHeader = authorizationHeader(
            accessKeyID: credentials.accessKeyID,
            credentialScope: scope,
            signedHeaders: signed,
            signature: signatureHex
        )

        return SigningResult(
            canonicalRequest: creq,
            hashedCanonicalRequest: hashedCreq,
            credentialScope: scope,
            stringToSign: sts,
            signingKeyHex: hex(key),
            signature: signatureHex,
            signedHeaders: signed,
            authorizationHeader: authHeader
        )
    }

    // MARK: - Task 1: Canonical request

    /// SigV4-encodes a URI path: every path SEGMENT is percent-encoded
    /// per `uriEncode(_:)` (unreserved characters `A-Za-z0-9-_.~` pass
    /// through, everything else becomes uppercase `%XX` of its UTF-8
    /// bytes), but the `/` segment separators themselves are left
    /// alone — encoding them would turn `/a/b` into `%2Fa%2Fb`, which
    /// is not what the canonical-URI step means by "URI-encode".
    ///
    /// Deliberately does NOT normalize `.`/`..` path segments the way
    /// generic HTTP clients do. AWS's canonicalization spec calls that
    /// out as a service-specific exception for S3: object keys containing
    /// literal `.`/`..` segments must be signed and sent exactly as
    /// given, never collapsed — S3 treats them as opaque key
    /// characters, not path-navigation tokens.
    ///
    /// - Parameter path: The absolute path, NOT pre-percent-encoded
    ///   (e.g. `"/videos/a b.mp4"`, not `"/videos/a%20b.mp4"`).
    /// - Returns: The canonical URI, e.g. `"/videos/a%20b.mp4"`.
    public static func canonicalURI(path: String) -> String {
        let effectivePath = path.isEmpty ? "/" : path
        let segments = effectivePath.split(separator: "/", omittingEmptySubsequences: false)
        return segments.map { uriEncode(String($0)) }.joined(separator: "/")
    }

    /// Builds the canonical query string: URI-encode every parameter
    /// name and value, then sort the encoded pairs by name and (for
    /// ties) by value, per AWS's canonicalization spec.
    ///
    /// - Parameter queryItems: The unencoded query parameters.
    /// - Returns: `""` for no parameters, otherwise
    ///   `"name1=value1&name2=value2"` in sorted order.
    public static func canonicalQueryString(queryItems: [URLQueryItem]) -> String {
        let encodedPairs = queryItems.map { item in
            (name: uriEncode(item.name), value: uriEncode(item.value ?? ""))
        }
        let sortedPairs = encodedPairs.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
        return sortedPairs.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Builds the canonical headers block and the `SignedHeaders` list.
    ///
    /// Header names are lower-cased; values are trimmed and have
    /// internal whitespace runs collapsed to a single space (SigV4's
    /// canonicalization rule, mirroring RFC 7230 §3.2.4 header-value
    /// folding). Headers are sorted by (lower-cased) name. If the
    /// caller's dictionary happens to contain two distinct keys that
    /// differ only by case (e.g. both `"Host"` and `"host"` — unusual,
    /// since `S3Uploader` always builds this dictionary with unique
    /// canonical-cased keys), their values are combined with `,` in
    /// whatever order `Dictionary` iterates them, matching AWS's
    /// documented duplicate-header handling; do not rely on that
    /// ordering being stable if you exercise this edge case directly.
    ///
    /// - Parameter headers: The headers to sign, keyed by header name.
    /// - Returns: The canonical headers block (each line
    ///   `"name:value\n"`, including the trailing newline AWS's spec
    ///   requires after the last header) and the `;`-joined
    ///   `SignedHeaders` value.
    public static func canonicalHeaders(_ headers: [String: String]) -> (block: String, signedHeaders: String) {
        var merged: [String: [String]] = [:]
        for (key, value) in headers {
            merged[key.lowercased(), default: []].append(collapseWhitespace(value))
        }
        let sortedKeys = merged.keys.sorted()
        let block = sortedKeys.map { key -> String in
            "\(key):\(merged[key]!.joined(separator: ","))\n"
        }.joined()
        let signedHeaders = sortedKeys.joined(separator: ";")
        return (block, signedHeaders)
    }

    /// Assembles Task 1's canonical request:
    /// `HTTPMethod\nCanonicalURI\nCanonicalQueryString\nCanonicalHeaders\n
    /// \nSignedHeaders\nHashedPayload`.
    ///
    /// `canonicalHeadersBlock` already carries its own trailing
    /// newline (see `canonicalHeaders(_:)`), so joining with `"\n"`
    /// here naturally produces the blank line AWS's spec requires
    /// between the headers block and `SignedHeaders`.
    public static func canonicalRequest(
        method: String,
        canonicalURI: String,
        canonicalQueryString: String,
        canonicalHeadersBlock: String,
        signedHeaders: String,
        hashedPayload: String
    ) -> String {
        [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeadersBlock,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")
    }

    // MARK: - Task 2: String to sign

    /// `<dateStamp>/<region>/<service>/aws4_request`.
    public static func credentialScope(dateStamp: String, region: String, service: String) -> String {
        "\(dateStamp)/\(region)/\(service)/aws4_request"
    }

    /// Task 2's string to sign:
    /// `AWS4-HMAC-SHA256\n<amzDate>\n<credentialScope>\n
    /// <hex SHA-256 of the canonical request>`.
    public static func stringToSign(
        amzDate: String,
        credentialScope: String,
        hashedCanonicalRequest: String
    ) -> String {
        [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            hashedCanonicalRequest,
        ].joined(separator: "\n")
    }

    // MARK: - Task 3: Signing key

    /// Derives the request-scoped signing key via the chained-HMAC
    /// construction AWS's spec requires:
    /// `HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service),
    /// "aws4_request")`. Each step re-uses the previous step's raw
    /// digest bytes as the NEXT HMAC's key — none of the intermediate
    /// values are hex-encoded along the way (only the final signature,
    /// in `sign(...)`, is hex-encoded for transmission).
    ///
    /// - Parameters:
    ///   - secretAccessKey: The raw AWS secret access key (never
    ///     `"AWS4"`-prefixed by the caller — this function adds that
    ///     prefix itself, per spec).
    ///   - dateStamp: `yyyyMMdd`, e.g. `"20150830"` — see `dateStamp(from:)`.
    ///   - region: AWS region, e.g. `"us-east-1"`.
    ///   - service: AWS service signing name, e.g. `"s3"`.
    /// - Returns: The raw 32-byte signing key.
    public static func signingKey(
        secretAccessKey: String,
        dateStamp: String,
        region: String,
        service: String
    ) -> Data {
        let kSecret = Data("AWS4\(secretAccessKey)".utf8)
        let kDate = hmacSHA256(key: kSecret, message: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, message: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, message: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, message: Data("aws4_request".utf8))
        return kSigning
    }

    // MARK: - Task 4: Authorization header

    /// `AWS4-HMAC-SHA256 Credential=<accessKeyID>/<credentialScope>,
    /// SignedHeaders=<signedHeaders>, Signature=<signature>`.
    public static func authorizationHeader(
        accessKeyID: String,
        credentialScope: String,
        signedHeaders: String,
        signature: String
    ) -> String {
        "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    // MARK: - Date formatting

    /// `yyyyMMdd'T'HHmmss'Z'` in UTC, e.g. `"20150830T123600Z"`.
    ///
    /// Built from a fresh, UTC-configured `Calendar` value on every
    /// call — deliberately NOT a cached `DateFormatter`, which is a
    /// mutable class Apple does not document as safe for concurrent
    /// use from multiple threads. `Calendar`/`DateComponents` are
    /// value types, so there is no shared mutable state here at all.
    public static func amzDate(from date: Date) -> String {
        let c = utcComponents(from: date, [.year, .month, .day, .hour, .minute, .second])
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    /// `yyyyMMdd` in UTC, e.g. `"20150830"`.
    public static func dateStamp(from date: Date) -> String {
        let c = utcComponents(from: date, [.year, .month, .day])
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }

    private static func utcComponents(from date: Date, _ components: Set<Calendar.Component>) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        // Force-unwrap is safe: "UTC" is one of the fixed IANA zone
        // identifiers `TimeZone(identifier:)` always resolves.
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.dateComponents(components, from: date)
    }

    // MARK: - Hashing (CommonCrypto)

    /// Hex-encoded SHA-256 of a UTF-8 string — used internally for the
    /// canonical-request hash and exposed publicly for callers who
    /// need to hash a string payload themselves.
    public static func sha256Hex(_ string: String) -> String {
        hex(sha256(Data(string.utf8)))
    }

    /// Hex-encoded SHA-256 of raw bytes — for the `x-amz-content-sha256`
    /// header when a request's body genuinely is hashed up front
    /// (small in-memory bodies). `S3Uploader`'s file `PUT` does NOT use
    /// this — see its doc comment for why it uses `unsignedPayload`
    /// instead.
    public static func sha256Hex(data: Data) -> String {
        hex(sha256(data))
    }

    /// Hex-encoded HMAC-SHA256 — exposed publicly so tests can pin the
    /// underlying CommonCrypto glue against a well-known vector (RFC
    /// 4231 Test Case 1) independently of the full SigV4 algorithm, in
    /// addition to the end-to-end AWS SigV4 vectors.
    public static func hmacSHA256Hex(key: Data, message: Data) -> String {
        hex(hmacSHA256(key: key, message: message))
    }

    private static func sha256(_ data: Data) -> Data {
        #if canImport(CommonCrypto)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
        #else
        preconditionFailure("AWSV4Signer requires CommonCrypto, available only on Apple platforms.")
        #endif
    }

    private static func hmacSHA256(key: Data, message: Data) -> Data {
        #if canImport(CommonCrypto)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            message.withUnsafeBytes { messageBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress, key.count,
                    messageBuffer.baseAddress, message.count,
                    &digest
                )
            }
        }
        return Data(digest)
        #else
        preconditionFailure("AWSV4Signer requires CommonCrypto, available only on Apple platforms.")
        #endif
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - URI encoding

    /// RFC 3986 unreserved-character percent-encoding, as SigV4's spec
    /// requires: `A-Z a-z 0-9 - _ . ~` pass through unchanged; every
    /// other byte of the string's UTF-8 representation becomes an
    /// uppercase `%XX`. Multi-byte (non-ASCII) characters are encoded
    /// one UTF-8 byte at a time, each as its own `%XX` — e.g. `"ሴ"`
    /// (U+1234) becomes `"%E1%88%B4"`, its three UTF-8 bytes.
    private static func uriEncode(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            if isUnreservedByte(byte) {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func isUnreservedByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }

    /// Trims leading/trailing whitespace and collapses any internal run
    /// of spaces/tabs to a single space, per SigV4's header-value
    /// canonicalization rule.
    private static func collapseWhitespace(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        var result = ""
        result.reserveCapacity(trimmed.count)
        var lastWasSpace = false
        for ch in trimmed {
            if ch == " " || ch == "\t" {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(ch)
                lastWasSpace = false
            }
        }
        return result
    }
}
