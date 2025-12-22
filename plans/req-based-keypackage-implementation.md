# REQ-Based KeyPackage Implementation Plan for NostrSDK

## Overview

This plan outlines the minimal changes needed in NostrSDK to support the REQ-based KeyPackage consumption model. Based on review of loxation-sw, NostrSDK is used primarily as a transport layer - KeyPackage management is handled by SwiftMLS.

## Key Principles

1. **Exposure = Consumption**: Once a KeyPackage is returned in a query, it's considered consumed by the relay
2. **Relay-Managed**: The relay handles consumption tracking automatically
3. **Kind 447 Deprecated**: Mark kind 447 as deprecated in favor of REQ-based signaling
4. **Minimal Changes**: NostrSDK doesn't need to manage KeyPackages, just provide transport

## Implementation Tasks

### 1. Update EventKind Documentation ✅

**File**: `Sources/NostrSDK/EventKind.swift`
- Add deprecation notice to `keyPackageRequest` (kind 447)
- Update documentation to reference REQ-based approach

### 2. Optional: Add Query Detection Helper

**File**: `Sources/NostrSDK/Relay.swift`
- Add a simple way to detect when relay queries for user's own KeyPackages
- This is optional - apps can detect this themselves by monitoring subscriptions

### 3. Update Documentation

**Files**:
- `nostrsdk-nip-ee-guide.md` - Update with new REQ-based approach
- Remove references to kind 447 workflows
- Add example showing how to detect relay replenishment requests

## API Design

### Monitoring KeyPackage Queries

```swift
// Subscribe to monitor KeyPackage queries for own pubkey
relay.monitorKeyPackageQueries(for: pubkey) { queryInfo in
    // queryInfo contains:
    // - requesterPubkey (if authenticated)
    // - timestamp
    // - isRelayInitiated (true if from relay itself)
    
    if queryInfo.isRelayInitiated {
        // Relay is requesting replenishment
        // Publish 5-10 new KeyPackages
    }
}
```

### Automatic Replenishment

```swift
// Setup automatic KeyPackage management
let manager = KeyPackageManager(
    identity: keypair,
    relays: [relay1, relay2],
    minThreshold: 3,
    replenishCount: 10
)

// Start monitoring
manager.startMonitoring()

// Manager will automatically:
// 1. Monitor queries for your KeyPackages
// 2. Detect relay replenishment requests
// 3. Generate and publish new KeyPackages as needed
```

### Manual KeyPackage Publishing

```swift
// Publish KeyPackages manually
func publishKeyPackages(count: Int = 5) async throws {
    for _ in 0..<count {
        let keyPackageData = generateMLSKeyPackage() // User provides
        
        let event = try KeyPackageEvent.Builder()
            .keyPackage(keyPackageData)
            .mlsProtocolVersion("1.0")
            .ciphersuite("0x0001")
            .extensions(["0x0001", "0x0002"])
            .relayURLs(keyPackageRelays)
            .build(signedBy: keypair)
        
        try relay.publish(event)
    }
}
```

## Migration Path

### Phase 1: Core Implementation (Week 1)
1. Create KeyPackage monitoring infrastructure
2. Implement replenishment detection
3. Basic KeyPackageManager

### Phase 2: Integration (Week 2)
1. Update all documentation
2. Create comprehensive examples
3. Deprecation warnings for kind 447

### Phase 3: Testing & Refinement (Week 3)
1. Integration tests with relay
2. Performance optimization
3. Edge case handling

## Testing Strategy

### Unit Tests
1. Query monitoring detection
2. Replenishment trigger logic
3. Rate limiting awareness

### Integration Tests
1. Full flow with MLS relay
2. Multiple relay coordination
3. Concurrent query handling

### Example Test

```swift
func testKeyPackageReplenishment() async throws {
    let manager = KeyPackageManager(...)
    let expectation = XCTestExpectation()
    
    manager.onReplenishmentNeeded = { count in
        XCTAssertEqual(count, 10) // Relay requested 10
        expectation.fulfill()
    }
    
    // Simulate relay query
    relay.simulateKeyPackageQuery(from: "relay", for: ourPubkey)
    
    await fulfillment(of: [expectation], timeout: 5.0)
}
```

## Success Metrics

1. **Seamless Migration**: Existing apps continue working
2. **Automatic Management**: 90%+ of replenishment handled automatically
3. **Performance**: <100ms to detect replenishment need
4. **Reliability**: Zero KeyPackage exhaustion events

## Notes

- Relay compatibility is key - test with wss://messaging.loxation.com
- Consider backward compatibility for clients still using kind 447
- Monitor adoption metrics to phase out old approach