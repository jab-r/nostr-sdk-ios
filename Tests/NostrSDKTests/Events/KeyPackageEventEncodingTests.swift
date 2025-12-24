//
//  KeyPackageEventEncodingTests.swift
//
//
//  Created by Roo on 12/24/25.
//

@testable import NostrSDK
import XCTest

final class KeyPackageEventEncodingTests: XCTestCase {

    func testContentEncodingDefaultsToHexWhenTagAbsent() throws {
        let json = """
        {
          "id": "test-id",
          "pubkey": "test-pubkey",
          "created_at": 0,
          "kind": 443,
          "tags": [],
          "content": "deadbeef",
          "sig": "test-sig"
        }
        """

        let event: KeyPackageEvent = try JSONDecoder().decode(KeyPackageEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.contentEncoding, .hex)
    }

    func testContentEncodingBase64WhenTagPresent() throws {
        let json = """
        {
          "id": "test-id",
          "pubkey": "test-pubkey",
          "created_at": 0,
          "kind": 443,
          "tags": [["encoding", "base64"]],
          "content": "ZGVhZGJlZWY=",
          "sig": "test-sig"
        }
        """

        let event: KeyPackageEvent = try JSONDecoder().decode(KeyPackageEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.contentEncoding, .base64)
    }

    func testBuilderUsesBase64ByDefaultAndSetsEncodingTag() throws {
        let keypair = try XCTUnwrap(Keypair())
        let data = Data([0xde, 0xad, 0xbe, 0xef])

        let event = try KeyPackageEvent.Builder()
            .keyPackage(data)
            .ciphersuite("0x0001")
            .extensions(["0x0001"])
            .build(signedBy: keypair)

        XCTAssertEqual(event.content, data.base64EncodedString())
        XCTAssertEqual(event.firstValueForRawTagName("encoding"), "base64")
        XCTAssertEqual(event.contentEncoding, .base64)
    }

    func testBuilderCanUseHexAndOmitsEncodingTag() throws {
        let keypair = try XCTUnwrap(Keypair())
        let data = Data([0xde, 0xad, 0xbe, 0xef])

        let event = try KeyPackageEvent.Builder()
            .keyPackage(data, encoding: .hex)
            .ciphersuite("0x0001")
            .extensions(["0x0001"])
            .build(signedBy: keypair)

        XCTAssertEqual(event.content, data.hexString)
        XCTAssertNil(event.firstValueForRawTagName("encoding"))
        XCTAssertEqual(event.contentEncoding, .hex)
    }
}
