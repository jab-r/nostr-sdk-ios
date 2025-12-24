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
}

