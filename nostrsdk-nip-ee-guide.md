# NostrSDK NIP-EE Implementation Guide

This guide covers the NIP-EE (MLS over Nostr) implementation in NostrSDK, specifically focusing on KeyPackage functionality with the new REQ-based consumption model.

## Overview

NIP-EE enables Message Layer Security (MLS) protocol to work over Nostr, allowing for end-to-end encrypted group messaging. This implementation provides the foundational components for managing MLS KeyPackages.

## ⚠️ Important: REQ-Based KeyPackage Consumption

As of the latest NIP-EE-RELAY specification, KeyPackage management has changed:

1. **Automatic Consumption**: When KeyPackages (kind 443) are queried via REQ, MLS-aware relays automatically mark them as consumed
2. **No Kind 447**: The KeyPackage Request event (kind 447) is deprecated
3. **Relay-Initiated Replenishment**: Relays signal the need for new KeyPackages by sending REQ queries for your own KeyPackages

## Features Implemented

1. **KeyPackageEvent** - A specialized event type for publishing MLS KeyPackages (kind 443)
2. **Query with Timeout** - Async method to fetch events with a time limit
3. **KeyPackage Subscription** - Specialized method to subscribe to keypackage events

## Event Kinds

The following NIP-EE event kinds have been added to NostrSDK:

- `443` - MLS KeyPackage
- `444` - MLS Welcome (gift-wrapped)
- `445` - MLS Group Message
- `447` - KeyPackage Request (DEPRECATED - use REQ-based replenishment)
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

## Best Practices for REQ-Based KeyPackage Management

1. **Monitor Your Own KeyPackages**: Watch for REQ queries for your own KeyPackages (kind 443). When the relay queries for them, it's signaling you need to publish more.

2. **Automatic Replenishment**: Publish 5-10 new KeyPackages when:
   - You receive REQ queries for your own KeyPackages (relay-initiated replenishment)
   - On startup if your supply is low
   - After being added to groups

3. **Understand Consumption**: Remember that querying for KeyPackages consumes them on MLS-aware relays. Only query when you actually need to use them.

4. **Relay Selection**: Use MLS-aware relays like `wss://messaging.loxation.com` that implement automatic consumption tracking.

5. **Error Handling**: Always handle errors when building events or querying relays, as network conditions and relay availability can vary.

## Detecting Relay Replenishment Requests

MLS-aware relays signal the need for new KeyPackages by querying for your own:

```swift
// Monitor subscriptions for relay-initiated queries
relay.delegate = self

// In your RelayDelegate implementation
func relay(_ relay: Relay, didReceive filter: Filter) {
    // Check if this is a query for our own KeyPackages
    if let authors = filter.authors,
       authors.contains(myPublicKey),
       let kinds = filter.kinds,
       kinds.contains(EventKind.mlsKeyPackage.rawValue) {
        // Relay is requesting KeyPackage replenishment
        print("Relay requesting KeyPackage replenishment")
        
        // Publish new KeyPackages via your MLS implementation
        // (e.g., using SwiftMLS)
    }
}
```

## Example: Complete KeyPackage Flow with REQ-Based Management

```swift
import NostrSDK
import SwiftMLS  // Or your MLS implementation

class KeyPackageManager {
    let relay: Relay
    let keypair: Keypair
    let mlsService: MLSService  // Your MLS implementation
    
    init(relayURL: URL, keypair: Keypair, mlsService: MLSService) {
        self.relay = Relay(url: relayURL)
        self.keypair = keypair
        self.mlsService = mlsService
        
        // Set up monitoring for replenishment requests
        setupReplenishmentMonitoring()
    }
    
    // Set up monitoring for relay-initiated replenishment
    private func setupReplenishmentMonitoring() {
        // Subscribe to KeyPackage queries for ourselves
        let filter = Filter(
            kinds: [EventKind.mlsKeyPackage.rawValue],
            authors: [keypair.publicKey.hex]
        )
        
        relay.subscribe(filter: filter) { [weak self] _ in
            // When relay queries for our KeyPackages, it needs replenishment
            Task {
                await self?.replenishKeyPackages()
            }
        }
    }
    
    // Publish new KeyPackages when requested by relay
    func replenishKeyPackages(count: Int = 5) async {
        do {
            // Generate KeyPackages via your MLS implementation
            let keyPackages = try await mlsService.generateKeyPackages(count: count)
            
            for keyPackageData in keyPackages {
                let event = try KeyPackageEvent.Builder()
                    .keyPackage(keyPackageData)
                    .mlsProtocolVersion("1.0")
                    .ciphersuite("0x0001")
                    .extensions(["0x0001", "0x0002"])
                    .relayURLs([relay.url])
                    .build(signedBy: keypair)
                
                try relay.publish(event)
            }
            
            print("Published \(count) new KeyPackages")
        } catch {
            print("Failed to replenish KeyPackages: \(error)")
        }
    }
    
    // Query for KeyPackages from specific users
    // NOTE: These will be automatically consumed by MLS-aware relays
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
}

// Example usage with SwiftMLS integration
class MLSGroupManager {
    let keyPackageManager: KeyPackageManager
    let mlsService: MLSService
    
    // Add member to group
    func addMemberToGroup(memberPubkey: String, groupId: String) async throws {
        // Fetch KeyPackage (will be consumed by relay)
        let keyPackages = try await keyPackageManager.fetchKeyPackages(for: [memberPubkey])
        
        guard let keyPackage = keyPackages.first else {
            throw MLSError.noKeyPackageAvailable
        }
        
        // Use the KeyPackage with your MLS implementation
        let welcome = try await mlsService.addMember(
            keyPackage: keyPackage.content,
            toGroup: groupId
        )
        
        // Send welcome message to new member...
    }
}
```

## Minimal Integration Example

If you just need to detect when to publish new KeyPackages:

```swift
// Monitor for relay replenishment requests
relay.subscribe(filter: Filter(kinds: [443], authors: [myPublicKey])) { _ in
    print("Relay is querying for my KeyPackages - time to publish more!")
    
    // Trigger your MLS library to generate and publish KeyPackages
    // This depends on your specific MLS integration
}
```

## Migration from Kind 447 to REQ-Based Approach

If you have existing code using kind 447 KeyPackage requests:

1. **Remove kind 447 publishing code** - No longer needed
2. **Replace with subscription monitoring** - Watch for REQ queries for your own KeyPackages
3. **Let relays manage consumption** - Don't track which KeyPackages have been used
4. **Use MLS-aware relays** - Ensure your relays support automatic consumption

## Future Considerations

While this implementation focuses on KeyPackage functionality, full NIP-EE support would include:

- Welcome message handling (kind 444)
- Group message handling (kind 445)
- ~~KeyPackage request/response flow (kind 447)~~ - DEPRECATED, use REQ-based approach
- Roster policy management (kind 450)
- KeyPackage relay list (kind 10051)

These features can be built on top of the current foundation as needed.

## Resources

- [NIP-EE-RELAY Specification](https://github.com/jab-r/nostr-sdk-ios/blob/main/NIP-EE-RELAY.md)
- [MLS Protocol RFC](https://datatracker.ietf.org/doc/rfc9420/)
- [NostrSDK Documentation](https://github.com/jab-r/nostr-sdk-ios)
- [Reference Relay Implementation](wss://messaging.loxation.com) - MLS-aware relay with automatic consumption