// ============================================================================
// MeedyaConverter — AWSV4SignerTests (Issue #459, Bundle 1b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// AWSV4Signer is security-sensitive cryptographic signing code. "Looks
// right" is not a review standard for that — this file instead reproduces
// AWS's own PUBLISHED test vectors byte-for-byte, so a correct
// implementation is independently verifiable without a local build (this
// repo builds macOS-only; this Swift file has never been compiled by the
// author — CI's `Build & Test (macOS)` job is the actual compile+run gate).
//
// ### Vector source
//
// Four cases from the AWS "Signature Version 4 Test Suite" — the fixed
// worked examples AWS itself published to let implementers validate a
// SigV4 signer (access key `AKIDEXAMPLE`, secret
// `wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY`, request date
// `Fri, 30 Aug 2015 12:36:00 GMT` / `20150830T123600Z`, region
// `us-east-1`, service `service`, host `example.amazonaws.com`):
//
//   - `get-vanilla` — the baseline case: canonical request, its SHA-256
//     hash, string-to-sign, and final signature for a bare `GET /`.
//   - `get-vanilla-query-order-key-case` — same request with two query
//     parameters supplied out of order (`Param2` before `Param1`),
//     verifying `canonicalQueryString(queryItems:)` sorts by name.
//   - `get-unreserved` — a path built entirely from the RFC 3986
//     "unreserved" character set (`-._~0-9A-Za-z`), verifying
//     `canonicalURI(path:)` passes those through WITHOUT percent-encoding
//     them (a common signer bug: over-encoding unreserved characters
//     produces a signature AWS rejects).
//   - `get-utf8` — a path containing a non-ASCII character (U+1234
//     "ሴ"), verifying multi-byte UTF-8 percent-encoding is done one raw
//     byte at a time (`"ሴ"` → `"%E1%88%B4"`), not one Unicode scalar at
//     a time.
//
// This exact test suite (canonical request / string-to-sign / signing-key
// / authorization-header fixtures per named case) is long-standing and
// widely mirrored/re-used by independent SigV4 implementations across the
// ecosystem (e.g. it is vendored into MongoDB's `libmongocrypt` under
// `kms-message/aws-sig-v4-test-suite/`, and is the same suite referenced
// by `aws/aws-sdk-js` issue #853 and multiple other SDKs' own test
// suites) — it is the standard cross-implementation correctness
// reference for SigV4, not a one-off blog post.
//
// ### Independent double-check
//
// Every one of the four fixtures below was ALSO independently
// recomputed from first principles using Python's standard-library
// `hashlib`/`hmac` (not Swift, not this signer, not a copy-paste of the
// published page) before being written into this file — i.e. each
// published (canonical-request-hash, string-to-sign, signature) triple
// was confirmed to be internally self-consistent: hashing the exact
// canonical-request text really does yield the published hash, and
// chaining `HMAC-SHA256` through date→region→service→"aws4_request"
// really does derive a key that reproduces the published signature.
// That rules out a transcription error in the fixtures themselves,
// independently of whether `AWSV4Signer`'s Swift implementation matches
// them.
//
// Two additional low-level sanity checks pin the underlying CommonCrypto
// glue in isolation, independent of the SigV4 algorithm on top of it:
//   - `sha256Hex` against the well-known NIST SHA-256 vectors for `""`
//     and `"abc"`.
//   - `hmacSHA256Hex` against RFC 4231 Test Case 1.
//
// Per this repo's test policy (see the header comment in
// `ConverterEngineTests.swift`), only the PUBLIC API is exercised —
// `import ConverterEngine`, no `@testable import`.
// ---------------------------------------------------------------------------

import XCTest
import ConverterEngine

final class AWSV4SignerTests: XCTestCase {

    // MARK: - Shared fixture constants (AWS Signature Version 4 Test Suite)

    private let testAccessKeyID = "AKIDEXAMPLE"
    private let testSecretAccessKey = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    private let testRegion = "us-east-1"
    private let testService = "service"
    private let testHost = "example.amazonaws.com"

    /// `2015-08-30T12:36:00Z`, i.e. `20150830T123600Z` / date stamp
    /// `20150830` — the fixed timestamp every AWS Signature Version 4
    /// Test Suite case uses. Constructed from a raw Unix timestamp
    /// (independently computed with Python's `datetime`, NOT via
    /// `AWSV4Signer.amzDate`/`dateStamp` — using the code under test to
    /// build its own input would make the date-formatting assertions
    /// below circular).
    private let testDate = Date(timeIntervalSince1970: 1_440_938_160)

    private var testCredentials: AWSV4Signer.Credentials {
        AWSV4Signer.Credentials(accessKeyID: testAccessKeyID, secretAccessKey: testSecretAccessKey)
    }

    // MARK: - Date formatting (inputs to every vector below)

    func test_amzDate_formatsFixedTimestampAsAWSExpects() {
        XCTAssertEqual(AWSV4Signer.amzDate(from: testDate), "20150830T123600Z")
    }

    func test_dateStamp_formatsFixedTimestampAsAWSExpects() {
        XCTAssertEqual(AWSV4Signer.dateStamp(from: testDate), "20150830")
    }

    // MARK: - Low-level crypto sanity (independent of the SigV4 algorithm)

    /// NIST's published SHA-256 test vectors.
    func test_sha256Hex_matchesKnownVectors() {
        XCTAssertEqual(
            AWSV4Signer.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            AWSV4Signer.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    /// RFC 4231 Test Case 1 (key = 20 bytes of `0x0b`, data = "Hi There").
    /// Pins the `CCHmac` glue itself, independent of SigV4's own
    /// chained-HMAC construction on top of it.
    func test_hmacSHA256Hex_matchesRFC4231TestCase1() {
        let key = Data(repeating: 0x0b, count: 20)
        let data = Data("Hi There".utf8)
        XCTAssertEqual(
            AWSV4Signer.hmacSHA256Hex(key: key, message: data),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        )
    }

    // MARK: - AWS Signature Version 4 Test Suite: get-vanilla

    /// The baseline vector: `GET /` with only `Host` and `X-Amz-Date`
    /// signed, no query string, empty body.
    ///
    /// Source: AWS Signature Version 4 Test Suite, case `get-vanilla`.
    /// Published fixtures for this case:
    ///   - canonical request hash:
    ///     `bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63`
    ///   - string to sign ends with the same hash, scope
    ///     `20150830/us-east-1/service/aws4_request`
    ///   - signature:
    ///     `5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31`
    ///   - Authorization header:
    ///     `AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request,
    ///     SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31`
    func test_getVanilla_matchesAWSPublishedVectors() {
        let expectedCanonicalRequest = [
            "GET",
            "/",
            "",
            "host:\(testHost)",
            "x-amz-date:20150830T123600Z",
            "",
            "host;x-amz-date",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ].joined(separator: "\n")

        let expectedHash = "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63"
        let expectedScope = "20150830/us-east-1/service/aws4_request"
        let expectedStringToSign = [
            "AWS4-HMAC-SHA256",
            "20150830T123600Z",
            expectedScope,
            expectedHash,
        ].joined(separator: "\n")
        let expectedSignature = "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"
        let expectedAuthHeader =
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, "
            + "SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"

        let result = AWSV4Signer.sign(
            method: "GET",
            path: "/",
            queryItems: [],
            headers: ["host": testHost, "x-amz-date": "20150830T123600Z"],
            payloadHash: AWSV4Signer.sha256Hex(""),
            date: testDate,
            region: testRegion,
            service: testService,
            credentials: testCredentials
        )

        // Every intermediate step, not just the final signature.
        XCTAssertEqual(result.canonicalRequest, expectedCanonicalRequest, "canonical request text must match byte-for-byte")
        XCTAssertEqual(result.hashedCanonicalRequest, expectedHash, "hash of the canonical request must match AWS's published value")
        XCTAssertEqual(result.credentialScope, expectedScope)
        XCTAssertEqual(result.stringToSign, expectedStringToSign)
        XCTAssertEqual(result.signedHeaders, "host;x-amz-date")
        XCTAssertEqual(result.signature, expectedSignature, "final signature hex must match AWS's published value exactly")
        XCTAssertEqual(result.authorizationHeader, expectedAuthHeader)

        // Cross-check: hashing the exact canonical-request STRING this
        // implementation built (independent of whatever internal
        // machinery produced it) reproduces the published hash — proves
        // `canonicalRequest` and `hashedCanonicalRequest` are mutually
        // consistent, not just each individually equal to the fixture.
        XCTAssertEqual(AWSV4Signer.sha256Hex(result.canonicalRequest), expectedHash)
    }

    // MARK: - AWS Signature Version 4 Test Suite: get-vanilla-query-order-key-case

    /// Query parameters supplied out of sorted order
    /// (`?Param2=value2&Param1=value1`) must be canonicalized in sorted
    /// order (`Param1=value1&Param2=value2`) before signing.
    ///
    /// Source: AWS Signature Version 4 Test Suite, case
    /// `get-vanilla-query-order-key-case`. Published canonical-request
    /// hash: `816cd5b414d056048ba4f7c5386d6e0533120fb1fcfa93762cf0fc39e2cf19e0`.
    /// Published signature:
    /// `b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500`.
    func test_getVanillaQueryOrderKeyCase_sortsQueryParametersByName() {
        let queryItems = [
            URLQueryItem(name: "Param2", value: "value2"),
            URLQueryItem(name: "Param1", value: "value1"),
        ]
        XCTAssertEqual(
            AWSV4Signer.canonicalQueryString(queryItems: queryItems),
            "Param1=value1&Param2=value2",
            "query parameters must be sorted by name, not left in request order"
        )

        let result = AWSV4Signer.sign(
            method: "GET",
            path: "/",
            queryItems: queryItems,
            headers: ["host": testHost, "x-amz-date": "20150830T123600Z"],
            payloadHash: AWSV4Signer.sha256Hex(""),
            date: testDate,
            region: testRegion,
            service: testService,
            credentials: testCredentials
        )

        XCTAssertEqual(
            result.hashedCanonicalRequest,
            "816cd5b414d056048ba4f7c5386d6e0533120fb1fcfa93762cf0fc39e2cf19e0"
        )
        XCTAssertEqual(
            result.signature,
            "b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500"
        )
    }

    // MARK: - AWS Signature Version 4 Test Suite: get-unreserved

    /// A path built entirely from RFC 3986 unreserved characters must
    /// pass through `canonicalURI` completely unchanged — none of
    /// `-._~0-9A-Za-z` may be percent-encoded.
    ///
    /// Source: AWS Signature Version 4 Test Suite, case
    /// `get-unreserved`. Published signature:
    /// `07ef7494c76fa4850883e2b006601f940f8a34d404d0cfa977f52a65bbf5f24f`.
    func test_getUnreserved_passesUnreservedCharactersThroughUnencoded() {
        let path = "/-._~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        XCTAssertEqual(
            AWSV4Signer.canonicalURI(path: path), path,
            "unreserved characters must never be percent-encoded"
        )

        let result = AWSV4Signer.sign(
            method: "GET",
            path: path,
            queryItems: [],
            headers: ["host": testHost, "x-amz-date": "20150830T123600Z"],
            payloadHash: AWSV4Signer.sha256Hex(""),
            date: testDate,
            region: testRegion,
            service: testService,
            credentials: testCredentials
        )

        XCTAssertEqual(
            result.signature,
            "07ef7494c76fa4850883e2b006601f940f8a34d404d0cfa977f52a65bbf5f24f"
        )
    }

    // MARK: - AWS Signature Version 4 Test Suite: get-utf8

    /// A path containing a multi-byte UTF-8 character must be
    /// percent-encoded one raw UTF-8 BYTE at a time:
    /// `"ሴ"` (U+1234) is the three bytes `E1 88 B4`, so its canonical
    /// URI is `"%E1%88%B4"`.
    ///
    /// Source: AWS Signature Version 4 Test Suite, case `get-utf8`.
    /// Published signature:
    /// `8318018e0b0f223aa2bbf98705b62bb787dc9c0e678f255a891fd03141be5d85`.
    func test_getUtf8_percentEncodesMultiByteUTF8PathPerByte() {
        XCTAssertEqual(AWSV4Signer.canonicalURI(path: "/ሴ"), "/%E1%88%B4")

        let result = AWSV4Signer.sign(
            method: "GET",
            path: "/ሴ",
            queryItems: [],
            headers: ["host": testHost, "x-amz-date": "20150830T123600Z"],
            payloadHash: AWSV4Signer.sha256Hex(""),
            date: testDate,
            region: testRegion,
            service: testService,
            credentials: testCredentials
        )

        XCTAssertEqual(
            result.signature,
            "8318018e0b0f223aa2bbf98705b62bb787dc9c0e678f255a891fd03141be5d85"
        )
    }

    // MARK: - Determinism

    /// Signing the same request with the same fixed `date` twice must
    /// yield byte-identical output. `sign(...)` never calls `Date()`
    /// itself (see `AWSV4Signer`'s file-overview doc comment) — this is
    /// the regression test for that invariant staying true.
    func test_sign_isDeterministicForAFixedDate() {
        let make = {
            AWSV4Signer.sign(
                method: "GET",
                path: "/",
                queryItems: [],
                headers: ["host": self.testHost, "x-amz-date": "20150830T123600Z"],
                payloadHash: AWSV4Signer.sha256Hex(""),
                date: self.testDate,
                region: self.testRegion,
                service: self.testService,
                credentials: self.testCredentials
            )
        }
        let first = make()
        let second = make()
        XCTAssertEqual(first.signature, second.signature)
        XCTAssertEqual(first.canonicalRequest, second.canonicalRequest)
        XCTAssertEqual(first.authorizationHeader, second.authorizationHeader)
    }

    // MARK: - Header canonicalization details

    func test_canonicalHeaders_lowercasesSortsAndCollapsesWhitespace() {
        let (block, signed) = AWSV4Signer.canonicalHeaders([
            "X-Amz-Date": "20150830T123600Z",
            "Host": "example.amazonaws.com",
            "X-Custom":  "  a   b  ", // leading/trailing + collapsed internal whitespace
        ])
        XCTAssertEqual(signed, "host;x-amz-date;x-custom", "signed headers must be lower-cased and sorted")
        XCTAssertTrue(block.contains("host:example.amazonaws.com\n"))
        XCTAssertTrue(block.contains("x-amz-date:20150830T123600Z\n"))
        XCTAssertTrue(block.contains("x-custom:a b\n"), "internal whitespace runs must collapse to a single space, and leading/trailing whitespace must be trimmed")
    }
}

// ---------------------------------------------------------------------------
// MARK: - S3Uploader signing integration
// ---------------------------------------------------------------------------
//
// These tests exercise `S3Uploader.buildSignedUploadRequest` — the
// production call site that hands `AWSV4Signer` a real bucket/key/host —
// structurally: the request's method, host, headers, and
// `Authorization` SHAPE. They deliberately do not assert a specific
// signature hex the way the `AWSV4SignerTests` vectors above do (there
// is no AWS-published fixture for an arbitrary bucket/region/date
// combination); the signature's numeric correctness is already pinned
// by the four vector tests above, since `buildSignedUploadRequest`
// calls the exact same `AWSV4Signer.sign(...)` entry point.
// ---------------------------------------------------------------------------

final class S3UploaderSigningTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_440_938_160) // 2015-08-30T12:36:00Z

    private func sampleCredential(endpoint: String? = nil) -> CloudCredential {
        CloudCredential(
            provider: .awsS3,
            apiKey: "AKIDEXAMPLE",
            secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            endpoint: endpoint,
            region: "eu-west-1",
            bucket: "my-bucket"
        )
    }

    func test_buildSignedUploadRequest_hostMethodAndHeaders() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildSignedUploadRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                contentType: "video/mp4",
                contentLength: 12_345,
                metadata: ["title": "Test Video"],
                date: fixedDate
            )
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.host, "my-bucket.s3.eu-west-1.amazonaws.com")
        XCTAssertEqual(request.url?.path, "/videos/output.mp4")
        XCTAssertEqual(request.url?.scheme, "https")

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-date"), "20150830T123600Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), "UNSIGNED-PAYLOAD")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "12345")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-meta-title"), "Test Video")

        let authHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authHeader.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/eu-west-1/s3/aws4_request, "))
        XCTAssertTrue(authHeader.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))

        // The signature is a 64-character lowercase hex string (32-byte
        // HMAC-SHA256 digest) — its exact value is already pinned by
        // `AWSV4SignerTests`, since this call path uses the same
        // `AWSV4Signer.sign(...)` those vectors verify.
        let signaturePrefix = "Signature="
        guard let range = authHeader.range(of: signaturePrefix) else {
            return XCTFail("Authorization header missing Signature=")
        }
        let signature = String(authHeader[range.upperBound...])
        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func test_buildSignedUploadRequest_isDeterministicForAFixedDate() throws {
        let first = try XCTUnwrap(
            S3Uploader.buildSignedUploadRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                contentType: "video/mp4",
                contentLength: 12_345,
                date: fixedDate
            )
        )
        let second = try XCTUnwrap(
            S3Uploader.buildSignedUploadRequest(
                credential: sampleCredential(),
                objectKey: "videos/output.mp4",
                contentType: "video/mp4",
                contentLength: 12_345,
                date: fixedDate
            )
        )
        XCTAssertEqual(
            first.value(forHTTPHeaderField: "Authorization"),
            second.value(forHTTPHeaderField: "Authorization")
        )
    }

    func test_buildSignedUploadRequest_customEndpoint_usesVirtualHostedStyleOnThatHost() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildSignedUploadRequest(
                credential: sampleCredential(endpoint: "https://s3.us-west-002.backblazeb2.com"),
                objectKey: "output.mkv",
                contentType: "video/x-matroska",
                contentLength: 999,
                date: fixedDate
            )
        )
        XCTAssertEqual(request.url?.host, "my-bucket.s3.us-west-002.backblazeb2.com")
    }

    func test_buildSignedUploadRequest_encodesSpacesAndSpecialCharactersInObjectKey() throws {
        let request = try XCTUnwrap(
            S3Uploader.buildSignedUploadRequest(
                credential: sampleCredential(),
                objectKey: "my videos/a movie (2026).mp4",
                contentType: "video/mp4",
                contentLength: 1,
                date: fixedDate
            )
        )
        // `/` stays a path separator; the space and parentheses within
        // each segment are percent-encoded in the literal request URL.
        let absoluteString = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(
            absoluteString.contains("/my%20videos/a%20movie%20%282026%29.mp4"),
            "expected percent-encoded object key path in \(absoluteString)"
        )
        // `Foundation.URL.path` decodes percent-escapes back out; sanity
        // check it round-trips to the original (unencoded) object key.
        XCTAssertEqual(request.url?.path, "/my videos/a movie (2026).mp4")
    }

    func test_buildSignedUploadRequest_returnsNilForIncompleteCredential() {
        let missingSecret = CloudCredential(provider: .awsS3, apiKey: "AKID", bucket: "bucket")
        XCTAssertNil(
            S3Uploader.buildSignedUploadRequest(
                credential: missingSecret,
                objectKey: "key.mp4",
                contentType: "video/mp4",
                contentLength: 1,
                date: fixedDate
            )
        )

        let missingBucket = CloudCredential(provider: .awsS3, apiKey: "AKID", secret: "secret")
        XCTAssertNil(
            S3Uploader.buildSignedUploadRequest(
                credential: missingBucket,
                objectKey: "key.mp4",
                contentType: "video/mp4",
                contentLength: 1,
                date: fixedDate
            )
        )

        let emptyObjectKey = CloudCredential(provider: .awsS3, apiKey: "AKID", secret: "secret", bucket: "bucket")
        XCTAssertNil(
            S3Uploader.buildSignedUploadRequest(
                credential: emptyObjectKey,
                objectKey: "",
                contentType: "video/mp4",
                contentLength: 1,
                date: fixedDate
            )
        )
    }

    // MARK: - loadCredential (Keychain wiring)

    /// An empty `APIKeyManager` (no key ever stored) must yield `nil` —
    /// never a credential with empty/placeholder secrets. This does not
    /// touch the Keychain at all (`APIKeyManager.key(for:)` on an
    /// unpopulated in-memory store returns `nil` before any Keychain
    /// read), so it is safe to run on any CI runner without the
    /// Keychain-availability skip-probe
    /// `APIKeyManagerKeychainTests.probeKeychainPersistence()` uses for
    /// its Keychain-*write* tests.
    func test_loadCredential_returnsNilWhenNoKeyIsStored() {
        let isolatedManager = APIKeyManager(
            storageDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("s3uploader-tests-empty-\(UUID().uuidString)"),
            keychainService: "Ltd.MWBMpartners.MeedyaConverter.Tests.S3.\(UUID().uuidString)"
        )
        XCTAssertNil(
            S3Uploader.loadCredential(apiKeyManager: isolatedManager, bucket: "my-bucket")
        )
    }

    /// `storeKey` updates `APIKeyManager`'s in-memory `keys` array
    /// immediately (Keychain persistence is a best-effort side effect
    /// attempted afterwards — see `APIKeyManager.storeKey`'s
    /// implementation), so reading it back via the SAME manager
    /// instance (no reopen) exercises `loadCredential`'s field mapping
    /// deterministically without depending on Keychain write success on
    /// this host. Full Keychain round-trip persistence for `.awsS3`
    /// secrets specifically is already covered by
    /// `APIKeyManagerKeychainTests.test_apiKeyManager_roundTripsAllSecretsThroughKeychain`.
    func test_loadCredential_mapsStoredAWSKeyIntoCloudCredential() {
        let manager = APIKeyManager(
            storageDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("s3uploader-tests-\(UUID().uuidString)"),
            keychainService: "Ltd.MWBMpartners.MeedyaConverter.Tests.S3.\(UUID().uuidString)"
        )
        manager.storeKey(StoredAPIKey(
            provider: .awsS3,
            apiKey: "AKIA-FROM-KEYCHAIN",
            secretKey: "secret-from-keychain"
        ))

        let credential = S3Uploader.loadCredential(
            apiKeyManager: manager,
            bucket: "my-bucket",
            region: "eu-west-1"
        )

        XCTAssertEqual(credential?.apiKey, "AKIA-FROM-KEYCHAIN")
        XCTAssertEqual(credential?.secret, "secret-from-keychain")
        XCTAssertEqual(credential?.bucket, "my-bucket")
        XCTAssertEqual(credential?.region, "eu-west-1")
    }
}
