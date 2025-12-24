# NostrSDK NIP-EE-RELAY Implementation Guide

This guide covers the NIP-EE-RELAY (MLS over Nostr) implementation in NostrSDK, specifically focusing on KeyPackage functionality with the new REQ-based consumption model.

## Overview

NIP-EE-RELAY enables Message Layer Security (MLS) protocol to work over Nostr, allowing for end-to-end encrypted group messaging. This implementation provides the foundational components for managing MLS KeyPackages.

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

The following NIP-EE-RELAY event kinds have been added to NostrSDK:

- `443` - MLS KeyPackage
- `444` - MLS Welcome (gift-wrapped)
- `445` - MLS Group Message
- `447` - KeyPackage Request (DEPRECATED - use REQ-based replenishment)
- `10051` - KeyPackage Relay List

## Using KeyPackageEvent

### Creating a KeyPackageEvent

```swift
import NostrSDK

// Create a new KeyPackageEvent using the builder pattern
// New implementations SHOULD publish KeyPackages as base64 and include ["encoding","base64"].
let builder = KeyPackageEvent.Builder()
    .keyPackage(keyPackageData, encoding: .base64)
    .mlsProtocolVersion("1.0")
    .ciphersuite("0x0001")
    .extensions(["0x0001", "0x0002"]) // Extension ID values
    .relayURLs([URL(string: "wss://relay1.example.com")!, URL(string: "wss://relay2.example.com")!])
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
) { keyPackageContent, encoding in
    // The callback receives the raw content plus the detected encoding.
    // If the event includes ["encoding","base64"], `encoding` will be `.base64`.
    // If the tag is absent, `encoding` will be `.hex` (legacy default).
    print("Received keypackage (\(encoding)): \(keyPackageContent)")
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

4. **Rate Limits**: MLS-aware relays enforce rate limits:
   - **Per requester-author pair**: Maximum 10 queries per hour
   - **KeyPackages per query**: Default 1 per user (configurable up to 2)
   - **Last resort protection**: The last remaining KeyPackage is never consumed

5. **Relay Selection**: Use MLS-aware relays like `wss://messaging.loxation.com` that implement automatic consumption tracking.

6. **Error Handling**: Always handle errors when building events or querying relays, as network conditions and relay availability can vary.

## Querying KeyPackages

### Single User Query

Query KeyPackages from a single user:

```swift
// Query for a single user's KeyPackage
let filter = Filter(
    kinds: [EventKind.mlsKeyPackage.rawValue],
    authors: ["alice_hex_pubkey"]
)

let keyPackages = try await relay.query(
    filter: filter,
    timeoutInSeconds: 5
)
// Returns up to 1 KeyPackage by default
```

### Batch Query for Multiple Users

Query KeyPackages from multiple users in a single request (recommended):

```swift
// Query for multiple users at once - more efficient
let filter = Filter(
    kinds: [EventKind.mlsKeyPackage.rawValue],
    authors: ["alice_hex_pubkey", "bob_hex_pubkey", "charlie_hex_pubkey"]
)

let keyPackages = try await relay.query(
    filter: filter,
    timeoutInSeconds: 5
)
// Returns 1 KeyPackage per user by default (3 total in this example)
```

### Handling Partial Results

Not all requested users may have KeyPackages available:

```swift
func fetchKeyPackagesWithPartialHandling(for pubkeys: [String]) async throws -> [String: [KeyPackageEvent]] {
    let filter = Filter(
        kinds: [EventKind.mlsKeyPackage.rawValue],
        authors: pubkeys
    )
    
    let events = try await relay.query(
        filter: filter,
        timeoutInSeconds: 10
    )
    
    // Group KeyPackages by author
    var userKeyPackages: [String: [KeyPackageEvent]] = [:]
    for event in events {
        if let keyPackageEvent = event as? KeyPackageEvent {
            let author = keyPackageEvent.pubkey
            if userKeyPackages[author] == nil {
                userKeyPackages[author] = []
            }
            userKeyPackages[author]?.append(keyPackageEvent)
        }
    }
    
    // Check which users didn't return KeyPackages
    for pubkey in pubkeys {
        if userKeyPackages[pubkey] == nil || userKeyPackages[pubkey]?.isEmpty == true {
            print("No KeyPackages available for \(pubkey)")
            // Consider alternative actions or retry later
        }
    }
    
    return userKeyPackages
}
```

### Rate Limit Tracking

Implement client-side rate limit tracking to avoid hitting server limits:

```swift
class KeyPackageQueryTracker {
    private var queryTimestamps: [String: [Date]] = [:]
    private let rateLimitWindow: TimeInterval = 3600 // 1 hour
    private let maxQueriesPerHour = 10
    
    func canQuery(for pubkey: String) -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-rateLimitWindow)
        
        // Remove old timestamps
        if let timestamps = queryTimestamps[pubkey] {
            queryTimestamps[pubkey] = timestamps.filter { $0 > windowStart }
        }
        
        // Check if under limit
        let currentCount = queryTimestamps[pubkey]?.count ?? 0
        return currentCount < maxQueriesPerHour
    }
    
    func recordQuery(for pubkey: String) {
        if queryTimestamps[pubkey] == nil {
            queryTimestamps[pubkey] = []
        }
        queryTimestamps[pubkey]?.append(Date())
    }
    
    func filterAllowedQueries(pubkeys: [String]) -> [String] {
        return pubkeys.filter { canQuery(for: $0) }
    }
}
```

## Required MLS Extensions

When creating groups or KeyPackages, ensure compatibility with these required MLS extensions:

- `required_capabilities` - Ensures all members support necessary features
- `ratchet_tree` - Provides group state synchronization
- `nostr_group_data` - Stores Nostr-specific group metadata
- `last_resort` (highly recommended) - Allows KeyPackage reuse to prevent race conditions

### The Nostr Group Data Extension

The `nostr_group_data` extension is a required MLS extension that stores Nostr-specific metadata within the MLS group state:

- **nostr_group_id**: A 32-byte ID for the group (different from MLS group ID, can be changed over time)
- **name**: The name of the group
- **description**: A short description of the group
- **admin_pubkeys**: Array of hex-encoded public keys of group admins
- **relays**: Array of Nostr relay URLs for publishing and receiving messages

Important: Only group admins can modify this extension data through MLS Proposal and Commit messages.

## Detecting Relay Replenishment Requests

MLS-aware relays signal the need for new KeyPackages by querying for your own. NostrSDK now supports detecting these queries through the enhanced RelayDelegate protocol:

```swift
// Monitor subscriptions for relay-initiated queries
class KeyPackageReplenishmentMonitor: RelayDelegate {
    private let keypair: Keypair
    private var lastReplenishTime: Date?
    
    init(keypair: Keypair) {
        self.keypair = keypair
    }
    
    // New delegate method for detecting subscription requests
    func relay(_ relay: Relay, didReceiveSubscriptionRequest subscriptionId: String, filter: Filter) {
        // Check if this is a query for our own KeyPackages
        if let authors = filter.authors,
           authors.contains(keypair.publicKey.hex),
           let kinds = filter.kinds,
           kinds.contains(EventKind.mlsKeyPackage.rawValue) {
            
            // Avoid rapid replenishment
            if let lastTime = lastReplenishTime,
               Date().timeIntervalSince(lastTime) < 300 { // 5 minutes
                return
            }
            
            print("Relay requesting KeyPackage replenishment")
            
            Task {
                await replenishKeyPackages()
                lastReplenishTime = Date()
            }
        }
    }
    
    // Required delegate methods
    func relayStateDidChange(_ relay: Relay, state: Relay.State) {
        // Handle connection state changes if needed
    }
    
    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        // Handle other responses if needed
    }
    
    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        // Handle received events if needed
    }
}

// Usage
let monitor = KeyPackageReplenishmentMonitor(keypair: keypair)
relay.delegate = monitor
```

This approach allows you to:
- Detect when MLS-aware relays query for your KeyPackages
- Automatically replenish when the relay signals low availability
- Prevent rapid replenishment with time-based throttling
- Maintain full compatibility with the NIP-EE-RELAY specification

## Complete KeyPackage Client Implementation

Here's a comprehensive Swift implementation that handles KeyPackage queries with rate limiting, partial results, and batch operations:

```swift
import NostrSDK
import SwiftMLS  // Or your MLS implementation

class KeyPackageClient: RelayDelegate {
    let relay: Relay
    let keypair: Keypair
    let mlsService: MLSService
    private let queryTracker = KeyPackageQueryTracker()
    private var lastReplenishTime: Date?
    
    init(relayURL: URL, keypair: Keypair, mlsService: MLSService) {
        self.relay = Relay(url: relayURL)
        self.keypair = keypair
        self.mlsService = mlsService
        
        // Set up monitoring for replenishment requests
        setupReplenishmentMonitoring()
    }
    
    // MARK: - Replenishment
    
    private func setupReplenishmentMonitoring() {
        // Set up delegate to monitor for relay-initiated queries
        relay.delegate = self
    }
    
    // MARK: - RelayDelegate
    
    func relayStateDidChange(_ relay: Relay, state: Relay.State) {
        // Handle connection state changes if needed
        switch state {
        case .connected:
            print("Relay connected")
        case .notConnected:
            print("Relay disconnected")
        case .connecting:
            print("Relay connecting...")
        case .error(let error):
            print("Relay error: \(error)")
        }
    }
    
    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        // Handle other relay responses if needed
    }
    
    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        // Handle received events if needed
    }
    
    func relay(_ relay: Relay, didReceiveSubscriptionRequest subscriptionId: String, filter: Filter) {
        // Check if this is a query for our own KeyPackages
        if let authors = filter.authors,
           authors.contains(keypair.publicKey.hex),
           let kinds = filter.kinds,
           kinds.contains(EventKind.mlsKeyPackage.rawValue) {
            
            // Avoid rapid replenishment
            if let lastTime = lastReplenishTime,
               Date().timeIntervalSince(lastTime) < 300 { // 5 minutes
                return
            }
            
            print("Relay requesting KeyPackage replenishment")
            
            Task {
                await replenishKeyPackages()
                lastReplenishTime = Date()
            }
        }
    }
    
    func replenishKeyPackages(count: Int = 10) async {
        do {
            let keyPackages = try await mlsService.generateKeyPackages(count: count)
            
            for keyPackageData in keyPackages {
                let event = try KeyPackageEvent.Builder()
                    .mlsKeyPackageData(keyPackageData.hexEncodedString())
                    .mlsProtocolVersion("1.0")
                    .ciphersuite("0x0001")
                    .extensions(["0x0001", "0x0002", "0xF000"]) // last_resort extension
                    .relayURLs([relay.url.absoluteString])
                    .build(signedBy: keypair)
                
                try relay.publish(event)
            }
            
            print("Published \(count) new KeyPackages")
        } catch {
            print("Failed to replenish KeyPackages: \(error)")
        }
    }
    
    // MARK: - Querying
    
    /// Query KeyPackages with rate limit checking and partial result handling
    func queryKeyPackagesWithRateLimit(
        for pubkeys: [String]
    ) async throws -> KeyPackageQueryResult {
        // Filter out rate-limited pubkeys
        let allowedPubkeys = queryTracker.filterAllowedQueries(pubkeys)
        let rateLimitedPubkeys = Set(pubkeys).subtracting(allowedPubkeys)
        
        if allowedPubkeys.isEmpty {
            return KeyPackageQueryResult(
                keyPackages: [:],
                missingUsers: [],
                rateLimitedUsers: Array(rateLimitedPubkeys)
            )
        }
        
        // Record queries
        allowedPubkeys.forEach { queryTracker.recordQuery(for: $0) }
        
        // Query allowed users
        let filter = Filter(
            kinds: [EventKind.mlsKeyPackage.rawValue],
            authors: allowedPubkeys
        )
        
        let events = try await relay.query(
            filter: filter,
            timeoutInSeconds: 5
        )
        
        // Process results
        var keyPackagesByUser: [String: [KeyPackageEvent]] = [:]
        for event in events {
            if let keyPackageEvent = event as? KeyPackageEvent {
                let author = keyPackageEvent.pubkey
                if keyPackagesByUser[author] == nil {
                    keyPackagesByUser[author] = []
                }
                keyPackagesByUser[author]?.append(keyPackageEvent)
            }
        }
        
        // Identify users with no KeyPackages
        let missingUsers = allowedPubkeys.filter { pubkey in
            keyPackagesByUser[pubkey] == nil || keyPackagesByUser[pubkey]!.isEmpty
        }
        
        return KeyPackageQueryResult(
            keyPackages: keyPackagesByUser,
            missingUsers: missingUsers,
            rateLimitedUsers: Array(rateLimitedPubkeys)
        )
    }
    
    /// Retry failed user additions with exponential backoff
    func retryFailedAdditions(
        pubkeys: [String],
        maxRetries: Int = 3
    ) async throws -> KeyPackageQueryResult {
        var lastResult: KeyPackageQueryResult?
        
        for attempt in 0..<maxRetries {
            do {
                let result = try await queryKeyPackagesWithRateLimit(for: pubkeys)
                
                // If we got all KeyPackages, return
                if result.missingUsers.isEmpty && result.rateLimitedUsers.isEmpty {
                    return result
                }
                
                lastResult = result
                
                // If all users are rate limited, no point retrying
                if result.rateLimitedUsers.count == pubkeys.count {
                    break
                }
                
                // Exponential backoff for missing users
                if !result.missingUsers.isEmpty && attempt < maxRetries - 1 {
                    let backoff = pow(2.0, Double(attempt)) * 1.0
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
                
            } catch {
                if attempt == maxRetries - 1 {
                    throw error
                }
            }
        }
        
        return lastResult ?? KeyPackageQueryResult(
            keyPackages: [:],
            missingUsers: pubkeys,
            rateLimitedUsers: []
        )
    }
}

// MARK: - Supporting Types

struct KeyPackageQueryResult {
    let keyPackages: [String: [KeyPackageEvent]]
    let missingUsers: [String]
    let rateLimitedUsers: [String]
    
    var successfulUsers: [String] {
        Array(keyPackages.keys)
    }
    
    var totalKeyPackagesReceived: Int {
        keyPackages.values.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Rate Limit Tracking

class KeyPackageQueryTracker {
    private var queryTimestamps: [String: [Date]] = [:]
    private let queue = DispatchQueue(label: "keypackage.query.tracker")
    private let rateLimitWindow: TimeInterval = 3600 // 1 hour
    private let maxQueriesPerHour = 10
    
    func canQuery(for pubkey: String) -> Bool {
        queue.sync {
            let now = Date()
            let windowStart = now.addingTimeInterval(-rateLimitWindow)
            
            // Clean old timestamps
            if let timestamps = queryTimestamps[pubkey] {
                queryTimestamps[pubkey] = timestamps.filter { $0 > windowStart }
            }
            
            let currentCount = queryTimestamps[pubkey]?.count ?? 0
            return currentCount < maxQueriesPerHour
        }
    }
    
    func recordQuery(for pubkey: String) {
        queue.sync {
            if queryTimestamps[pubkey] == nil {
                queryTimestamps[pubkey] = []
            }
            queryTimestamps[pubkey]?.append(Date())
        }
    }
    
    func filterAllowedQueries(_ pubkeys: [String]) -> [String] {
        pubkeys.filter { canQuery(for: $0) }
    }
    
    func timeUntilNextQuery(for pubkey: String) -> TimeInterval? {
        queue.sync {
            guard let timestamps = queryTimestamps[pubkey],
                  !timestamps.isEmpty else {
                return nil
            }
            
            let windowStart = timestamps[0].addingTimeInterval(rateLimitWindow)
            let now = Date()
            
            if windowStart > now {
                return windowStart.timeIntervalSince(now)
            }
            
            return nil
        }
    }
}

// MARK: - Usage Examples

extension KeyPackageClient {
    /// Create a new MLS group with multiple members
    func createGroupExample(memberPubkeys: [String]) async throws {
        let result = try await queryKeyPackagesWithRateLimit(for: memberPubkeys)
        
        if !result.missingUsers.isEmpty {
            print("Warning: Could not add users: \(result.missingUsers)")
        }
        
        if !result.rateLimitedUsers.isEmpty {
            print("Rate limited users: \(result.rateLimitedUsers)")
        }
        
        // Create group with available KeyPackages
        for (pubkey, keyPackages) in result.keyPackages {
            guard let firstKeyPackage = keyPackages.first else { continue }
            
            // Use the KeyPackage to add member to group
            try await mlsService.addMember(
                keyPackageData: firstKeyPackage.mlsKeyPackageData,
                toGroup: "group_id"
            )
        }
    }
    
    /// Add new members to existing group
    func addMembersToGroup(newMembers: [String], groupId: String) async throws {
        // Try with retry logic
        let result = try await retryFailedAdditions(pubkeys: newMembers)
        
        // Process successful additions
        for (pubkey, keyPackages) in result.keyPackages {
            guard let keyPackage = keyPackages.first else { continue }
            
            let welcome = try await mlsService.addMember(
                keyPackageData: keyPackage.mlsKeyPackageData,
                toGroup: groupId
            )
            
            // Send welcome message (implement according to NIP-EE-RELAY)
            await sendWelcomeMessage(welcome, to: pubkey, keyPackageId: keyPackage.id)
        }
        
        // Report failures
        if !result.missingUsers.isEmpty || !result.rateLimitedUsers.isEmpty {
            throw KeyPackageError.partialSuccess(
                added: result.successfulUsers,
                missing: result.missingUsers,
                rateLimited: result.rateLimitedUsers
            )
        }
    }
}

enum KeyPackageError: Error {
    case partialSuccess(added: [String], missing: [String], rateLimited: [String])
    case allUsersRateLimited
    case noKeyPackagesAvailable
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
            keyPackage: keyPackage.mlsKeyPackageData,
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

## KeyPackage Event Structure

According to the NIP-EE-RELAY specification, a KeyPackage Event has the following structure:

```json
{
    "id": "<event_id>",
    "kind": 443,
    "created_at": <unix_timestamp>,
    "pubkey": "<main_identity_pubkey>",
    "content": "<hex_encoded_keypackage_bundle>",
    "tags": [
        ["mls_protocol_version", "1.0"],
        ["ciphersuite", "0x0001"],
        ["extensions", "0x0001, 0x0002"],
        ["client", "MyNostrClient", "handler-event-id", "wss://relay.example.com"],
        ["relays", "wss://relay1.example.com", "wss://relay2.example.com"],
        ["-"]
    ],
    "sig": "<signature>"
}
```

## Welcome Events (kind 444)

Welcome Events are sent when a new user is added to a group. They are gift-wrapped using NIP-59 for privacy:

```json
{
    "id": "<event_id>",
    "kind": 444,
    "created_at": <unix_timestamp>,
    "pubkey": "<sender_nostr_identity_pubkey>",
    "content": "<serialized_mls_welcome_object>",
    "tags": [
        ["e", "<keypackage_event_id>"],
        ["relays", "wss://relay1.com", "wss://relay2.com"]
    ],
    "sig": "<NOT_SIGNED>"
}
```

**Important**: Welcome Events must NOT be signed. They are sealed and gift-wrapped according to NIP-59.

## Group Events (kind 445)

Group Events contain all MLS group messages (Proposals, Commits, and Application messages):

```json
{
    "id": "<event_id>",
    "kind": 445,
    "created_at": <unix_timestamp>,
    "pubkey": "<ephemeral_sender_pubkey>",
    "content": "<nip44_encrypted_mls_message>",
    "tags": [
        ["h", "<nostr_group_id>"]
    ],
    "sig": "<signed_with_ephemeral_key>"
}
```

Key points:
- Use a new ephemeral keypair for each Group Event
- Content is NIP-44 encrypted using keys derived from MLS `exporter_secret`
- The `h` tag contains the Nostr group ID from the `nostr_group_data` extension

## Security Considerations

- Never reuse ephemeral keypairs for Group Events
- Welcome Events must never be signed to prevent publishability if leaked
- Application messages inside Group Events should be unsigned Nostr events (e.g., kind 9 for chat)
- Always verify that the identity in Application messages matches the MLS sender

## Future Considerations

While this implementation focuses on KeyPackage functionality, full NIP-EE-RELAY support would include:

- Complete Welcome message handling with NIP-59 gift-wrapping
- Group message encryption/decryption using MLS exporter secrets
- Application message parsing and validation
- KeyPackage relay list (kind 10051) management
- Commit message ordering and fork recovery

These features can be built on top of the current foundation as needed.

## Resources

- [NIP-EE-RELAY Specification](https://github.com/jab-r/nostr-sdk-ios/blob/main/NIP-EE-RELAY.md)
- [MLS Protocol RFC](https://datatracker.ietf.org/doc/rfc9420/)
- [NostrSDK Documentation](https://github.com/jab-r/nostr-sdk-ios)
- [Reference Relay Implementation](wss://messaging.loxation.com) - MLS-aware relay with automatic consumption
