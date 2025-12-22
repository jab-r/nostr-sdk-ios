# NostrSDK NIP-EE Implementation Guide

This guide covers the NIP-EE (MLS over Nostr) implementation in NostrSDK, specifically focusing on KeyPackage functionality.

## Overview

NIP-EE enables Message Layer Security (MLS) protocol to work over Nostr, allowing for end-to-end encrypted group messaging. This implementation provides the foundational components for managing MLS KeyPackages.

## Features Implemented

1. **KeyPackageEvent** - A specialized event type for publishing MLS KeyPackages (kind 443)
2. **Query with Timeout** - Async method to fetch events with a time limit
3. **KeyPackage Subscription** - Specialized method to subscribe to keypackage events

## Event Kinds

The following NIP-EE event kinds have been added to NostrSDK:

- `443` - MLS KeyPackage
- `444` - MLS Welcome (gift-wrapped)
- `445` - MLS Group Message
- `447` - KeyPackage Request
- `450` - Roster Policy
- `10051` - KeyPackage Relay List

## Using KeyPackageEvent

### Creating a KeyPackageEvent

```swift
import NostrSDK

// Create a new KeyPackageEvent using the builder pattern
let builder = KeyPackageEvent.Builder()
    .mlsKeyPackageData("base64-encoded-keypackage-data")
    .mlsProtocolVersion("mls/1.0")
    .ciphersuite("0x0001")
    .extensions(["application_id", "ratchet_tree"])
    .clientName("MyNostrClient")
    .clientHandlerEventId("event-id-of-handler")
    .clientRelayURL(URL(string: "wss://relay.example.com")!)
    .createdAt(Int64(Date.now.timeIntervalSince1970))

// Sign and build the event
let keyPackageEvent = try builder.build(signedBy: keypair)
```

### Parsing a KeyPackageEvent

```swift
// When receiving a KeyPackageEvent
if let keyPackageEvent = event as? KeyPackageEvent {
    // Access the MLS KeyPackage data
    let keyPackageData = keyPackageEvent.mlsKeyPackageData
    
    // Access MLS parameters
    let version = keyPackageEvent.mlsProtocolVersion
    let ciphersuite = keyPackageEvent.ciphersuite
    let extensions = keyPackageEvent.extensions
    
    // Access client information
    if let clientInfo = keyPackageEvent.clientInfo {
        print("Client: \(clientInfo.name)")
        print("Handler Event: \(clientInfo.handlerEventId ?? "none")")
        print("Relay: \(clientInfo.relayURL?.absoluteString ?? "none")")
    }
}
```

## Query with Timeout

The query functionality allows you to fetch events with a timeout, preventing indefinite waiting:

```swift
let relay = Relay(url: URL(string: "wss://relay.example.com")!)

// Query for keypackages with a 5-second timeout
do {
    let events = try await relay.query(
        filter: Filter(
            kinds: [EventKind.mlsKeyPackage.rawValue],
            authors: ["pubkey1", "pubkey2"]
        ),
        timeoutInSeconds: 5
    )
    
    // Process the received events
    for event in events {
        if let keyPackageEvent = event as? KeyPackageEvent {
            // Handle the keypackage event
        }
    }
} catch {
    print("Query failed or timed out: \(error)")
}
```

## KeyPackage Subscription

Subscribe to keypackage events from specific authors:

```swift
let relay = Relay(url: URL(string: "wss://relay.example.com")!)

// Subscribe to keypackages from specific authors
let subscriptionId = relay.subscribeKeyPackages(
    authors: ["pubkey1", "pubkey2"],
    since: Int64(Date.now.timeIntervalSince1970) - 86400 // Last 24 hours
) { keyPackageContent in
    // The callback receives the raw content (base64-encoded keypackage data)
    print("Received keypackage: \(keyPackageContent)")
}

// Later, unsubscribe
try? relay.closeSubscription(with: subscriptionId)
```

## Best Practices

1. **KeyPackage Lifecycle**: Regularly update your KeyPackages to ensure forward secrecy. Old KeyPackages should be replaced periodically.

2. **Relay Selection**: Publish KeyPackages to multiple relays to ensure availability. Consider using dedicated relays that support keypackage lifecycle management.

3. **Client Information**: Always include client information when creating KeyPackages to help other clients identify compatible implementations.

4. **Error Handling**: Always handle errors when building events or querying relays, as network conditions and relay availability can vary.

## Example: Complete KeyPackage Flow

```swift
import NostrSDK

class KeyPackageManager {
    let relay: Relay
    let keypair: Keypair
    
    init(relayURL: URL, keypair: Keypair) {
        self.relay = Relay(url: relayURL)
        self.keypair = keypair
    }
    
    // Publish a new KeyPackage
    func publishKeyPackage(keyPackageData: String) async throws {
        let event = try KeyPackageEvent.Builder()
            .mlsKeyPackageData(keyPackageData)
            .mlsProtocolVersion("mls/1.0")
            .ciphersuite("0x0001")
            .clientName("MyApp")
            .build(signedBy: keypair)
        
        try relay.publish(event)
    }
    
    // Query for KeyPackages from specific users
    func fetchKeyPackages(for pubkeys: [String]) async throws -> [KeyPackageEvent] {
        let events = try await relay.query(
            filter: Filter(
                kinds: [EventKind.mlsKeyPackage.rawValue],
                authors: pubkeys
            ),
            timeoutInSeconds: 10
        )
        
        return events.compactMap { $0 as? KeyPackageEvent }
    }
    
    // Monitor for new KeyPackages
    func monitorKeyPackages(from authors: [String]) {
        relay.subscribeKeyPackages(
            authors: authors,
            since: Int64(Date.now.timeIntervalSince1970)
        ) { keyPackageContent in
            // Process new keypackage
            self.handleNewKeyPackage(keyPackageContent)
        }
    }
    
    private func handleNewKeyPackage(_ content: String) {
        // Your MLS library would process this KeyPackage data
        print("New KeyPackage received: \(content)")
    }
}
```

## Future Considerations

While this implementation focuses on KeyPackage functionality, full NIP-EE support would include:

- Welcome message handling (kind 444)
- Group message handling (kind 445)
- KeyPackage request/response flow (kind 447)
- Roster policy management (kind 450)
- KeyPackage relay list (kind 10051)

These features can be built on top of the current foundation as needed.

## Resources

- [NIP-EE-RELAY Specification](https://github.com/jab-r/nostr-sdk-ios/NIP-EE-RELAY.md)
- [MLS Protocol RFC](https://datatracker.ietf.org/doc/rfc9420/)
- [NostrSDK Documentation](https://github.com/jab-r/nostr-sdk-ios)