//
//  TagNameOnlyTests.swift
//
//  A tag may be only a name: NIP-70's protected marker is the one-element `["-"]`, and relays
//  recognize it only in that shape. Decoding used to require a value, so any event carrying it —
//  a KeyPackage (kind 443) signed elsewhere, or one received from a relay — failed to decode.
//

@testable import NostrSDK
import XCTest

final class TagNameOnlyTests: XCTestCase, EventVerifying {

    func testNameOnlyTagDecodesAndEncodesBackExactly() throws {
        let json = #"[["-"],["p","abc"],["encoding","base64"]]"#
        let tags = try JSONDecoder().decode([Tag].self, from: Data(json.utf8))

        XCTAssertEqual(tags[0].name, "-")
        XCTAssertFalse(tags[0].hasValue)
        XCTAssertEqual(tags[0].value, "")
        XCTAssertTrue(tags[1].hasValue)

        let encoded = String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
        XCTAssertEqual(encoded, json, "a name-only tag is written back as [name], never [name, \"\"]")
        XCTAssertNotEqual(Tag(name: "-"), Tag(name: "-", value: ""), "[\"-\"] and [\"-\", \"\"] are different tags")
    }

    func testSignedEventWithTheProtectedMarkerStillVerifiesAfterDecoding() throws {
        let keypair = try XCTUnwrap(Keypair())
        let event = try KeyPackageEvent.Builder()
            .keyPackage(Data([0xde, 0xad, 0xbe, 0xef]))
            .ciphersuite("0x0001")
            .extensions(["0x0001"])
            .requireAuthentication()
            .build(signedBy: keypair)

        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        XCTAssertTrue(json.contains(#"["-"]"#), "the builder writes the NIP-70 marker as [\"-\"]: \(json)")
        XCTAssertFalse(json.contains(#"["-",""]"#))

        // The id is the hash of the serialized tags: it only matches if the marker re-encodes exactly.
        let decoded = try JSONDecoder().decode(NostrEvent.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.calculatedId, decoded.id)
        XCTAssertNoThrow(try verifyEvent(decoded))
    }

    func testRelayEventMessageWithANameOnlyTagDecodes() throws {
        let keypair = try XCTUnwrap(Keypair())
        let event = try KeyPackageEvent.Builder()
            .keyPackage(Data([0x01, 0x02]))
            .ciphersuite("0x0001")
            .extensions(["0x0001"])
            .requireAuthentication()
            .build(signedBy: keypair)
        let eventJSON = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        let message = #"["EVENT","sub-1","# + eventJSON + "]"

        let response = try XCTUnwrap(RelayResponse.decode(data: Data(message.utf8)))
        guard case .event(let subscriptionId, let received) = response else {
            return XCTFail("expected an EVENT message")
        }
        XCTAssertEqual(subscriptionId, "sub-1")
        XCTAssertEqual(received.id, event.id)
        XCTAssertTrue(received.tags.contains { $0.name == "-" && !$0.hasValue })
    }
}
