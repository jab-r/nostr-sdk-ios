//
//  KeyPackageEvent.swift
//  
//
//  Copyright (c) 2025 Jonathan Borden
//

import Foundation

/// An event that contains an MLS KeyPackage that allows users to be added to groups asynchronously.
///
/// See [NIP-EE](https://github.com/nostr-protocol/nips/blob/master/ee.md).
public final class KeyPackageEvent: NostrEvent {

    /// Encoding used for the KeyPackage `content` field.
    ///
    /// Per `NIP-EE-RELAY.md`, new implementations may include the tag `['encoding','base64']`
    /// to indicate that the `content` is base64. If the tag is absent, the content is treated
    /// as hex for backwards compatibility.
    public enum ContentEncoding: String, Codable, Sendable {
        case hex
        case base64
    }

    /// The encoding used for the `content` field.
    ///
    /// Defaults to `.hex` when the `encoding` tag is absent.
    public var contentEncoding: ContentEncoding {
        let encoding = firstValueForRawTagName("encoding")?.lowercased()
        if encoding == ContentEncoding.base64.rawValue {
            return .base64
        }
        return .hex
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    
    @available(*, unavailable, message: "This initializer is unavailable for this class.")
    required init(kind: EventKind, content: String, tags: [Tag] = [], createdAt: Int64 = Int64(Date.now.timeIntervalSince1970), signedBy keypair: Keypair) throws {
        try super.init(kind: kind, content: content, tags: tags, createdAt: createdAt, signedBy: keypair)
    }
    
    @available(*, unavailable, message: "This initializer is unavailable for this class.")
    required init(kind: EventKind, content: String, tags: [Tag] = [], createdAt: Int64 = Int64(Date.now.timeIntervalSince1970), pubkey: String) {
        super.init(kind: kind, content: content, tags: tags, createdAt: createdAt, pubkey: pubkey)
    }
    
    @available(*, unavailable, message: "This initializer is unavailable for this class.")
    override init(id: String, pubkey: String, createdAt: Int64, kind: EventKind, tags: [Tag], content: String, signature: String?) {
        super.init(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, signature: signature)
    }
    
    /// The MLS protocol version this KeyPackage supports.
    public var mlsProtocolVersion: String? {
        firstValueForRawTagName("mls_protocol_version")
    }
    
    /// The MLS ciphersuite ID this KeyPackage supports.
    public var ciphersuite: String? {
        firstValueForRawTagName("ciphersuite")
    }
    
    /// The MLS extension IDs this KeyPackage supports.
    public var extensions: [String]? {
        guard let extensionsString = firstValueForRawTagName("extensions") else {
            return nil
        }
        return extensionsString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    /// The client information for this KeyPackage.
    /// Returns a tuple of (clientName, handlerEventId, relayURL) if present.
    public var clientInfo: (name: String, handlerEventId: String?, relayURL: URL?)? {
        guard let clientTag = tags.first(where: { $0.name == "client" }),
              clientTag.otherParameters.count >= 1 else {
            return nil
        }
        
        let name = clientTag.value
        let handlerEventId = clientTag.otherParameters.count > 0 ? clientTag.otherParameters[0] : nil
        let relayURLString = clientTag.otherParameters.count > 1 ? clientTag.otherParameters[1] : nil
        let relayURL = relayURLString.flatMap { try? validateRelayURLString($0) }
        
        return (name: name, handlerEventId: handlerEventId, relayURL: relayURL)
    }
    
    /// The relay URLs where this KeyPackage event will be published.
    public var relayURLs: [URL] {
        guard let relaysTagValue = firstValueForRawTagName("relays") else {
            return []
        }
        
        // Handle both comma-separated and array formats
        let relayStrings = relaysTagValue.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        return relayStrings.compactMap { try? validateRelayURLString($0) }
    }
    
    /// Whether this KeyPackage event requires NIP-70 authentication.
    public var requiresAuthentication: Bool {
        tags.contains { $0.name == "-" }
    }
}

public extension KeyPackageEvent {
    /// Builder for a ``KeyPackageEvent``.
    final class Builder: NostrEvent.Builder<KeyPackageEvent> {
        public init() {
            super.init(kind: .mlsKeyPackage)
        }
        
        /// Sets the serialized KeyPackage content.
        ///
        /// Per `NIP-EE-RELAY.md`, new implementations SHOULD publish KeyPackages with base64 encoding
        /// and include `['encoding','base64']`.
        ///
        /// - Parameters:
        ///   - keyPackageData: The serialized MLS KeyPackage bytes.
        ///   - encoding: Encoding to use for the `content` field. Defaults to `.base64`.
        ///
        /// When `encoding == .base64`, this will also add the `encoding` tag (if absent).
        /// When `encoding == .hex`, this will *not* add an encoding tag (legacy behavior).
        @discardableResult
        public final func keyPackage(_ keyPackageData: Data, encoding: ContentEncoding = .base64) -> Self {
            switch encoding {
            case .hex:
                return content(keyPackageData.hexString)
            case .base64:
                if !tags.contains(where: { $0.name == "encoding" }) {
                    _ = appendTags(Tag(name: "encoding", value: ContentEncoding.base64.rawValue))
                }
                return content(keyPackageData.base64EncodedString())
            }
        }
        
        /// Sets the MLS protocol version.
        @discardableResult
        public final func mlsProtocolVersion(_ version: String) -> Self {
            appendTags(Tag(name: "mls_protocol_version", value: version))
        }
        
        /// Sets the MLS ciphersuite ID.
        @discardableResult
        public final func ciphersuite(_ ciphersuite: String) -> Self {
            appendTags(Tag(name: "ciphersuite", value: ciphersuite))
        }
        
        /// Sets the MLS extension IDs.
        @discardableResult
        public final func extensions(_ extensions: [String]) -> Self {
            appendTags(Tag(name: "extensions", value: extensions.joined(separator: ",")))
        }
        
        /// Sets the client information.
        @discardableResult
        public final func clientInfo(name: String, handlerEventId: String? = nil, relayURL: URL? = nil) throws -> Self {
            var parameters = [String]()
            
            if let handlerEventId = handlerEventId {
                parameters.append(handlerEventId)
                
                if let relayURL = relayURL {
                    let validatedURL = try RelayURLValidator.shared.validateRelayURL(relayURL)
                    parameters.append(validatedURL.absoluteString)
                }
            }
            
            return appendTags(Tag(name: "client", value: name, otherParameters: parameters))
        }
        
        /// Sets the relay URLs where this KeyPackage will be published.
        @discardableResult
        public final func relayURLs(_ relayURLs: [URL]) throws -> Self {
            let validatedURLs = try relayURLs.map { try RelayURLValidator.shared.validateRelayURL($0) }
            let relayStrings = validatedURLs.map { $0.absoluteString }
            return appendTags(Tag(name: "relays", value: relayStrings.joined(separator: ",")))
        }
        
        /// Requires NIP-70 authentication for this event.
        @discardableResult
        public final func requireAuthentication() -> Self {
            appendTags(Tag(name: "-", value: ""))
        }
    }
}

public extension EventCreating {
    /// Creates a ``KeyPackageEvent`` (kind 443) for MLS group messaging.
    /// - Parameters:
    ///   - keyPackageData: The serialized MLS KeyPackage data.
    ///   - mlsProtocolVersion: The MLS protocol version (e.g., "1.0").
    ///   - ciphersuite: The MLS ciphersuite ID (e.g., "0x0001").
    ///   - extensions: Array of MLS extension IDs (e.g., ["0x0001", "0x0002"]).
    ///   - clientName: The name of the client creating this KeyPackage.
    ///   - handlerEventId: Optional handler event ID for the client.
    ///   - relayURL: Optional relay URL for the client.
    ///   - publishRelayURLs: The relay URLs where this KeyPackage will be published.
    ///   - requireAuth: Whether to require NIP-70 authentication.
    ///   - keypair: The Keypair to sign with.
    /// - Returns: The signed ``KeyPackageEvent``.
    func keyPackageEvent(
        keyPackageData: Data,
        mlsProtocolVersion: String = "1.0",
        ciphersuite: String,
        extensions: [String],
        clientName: String,
        handlerEventId: String? = nil,
        relayURL: URL? = nil,
        publishRelayURLs: [URL],
        encoding: KeyPackageEvent.ContentEncoding = .base64,
        requireAuth: Bool = false,
        signedBy keypair: Keypair
    ) throws -> KeyPackageEvent {
        let builder = KeyPackageEvent.Builder()
            .keyPackage(keyPackageData, encoding: encoding)
            .mlsProtocolVersion(mlsProtocolVersion)
            .ciphersuite(ciphersuite)
            .extensions(extensions)
        
        try builder.clientInfo(name: clientName, handlerEventId: handlerEventId, relayURL: relayURL)
        try builder.relayURLs(publishRelayURLs)
        
        if requireAuth {
            builder.requireAuthentication()
        }
        
        return try builder.build(signedBy: keypair)
    }
}
