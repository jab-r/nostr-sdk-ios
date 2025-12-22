# NIP-EE Implementation Plan for nostr-sdk-ios

## Overview

This plan outlines the implementation of NIP-EE (MLS over Nostr) support in nostr-sdk-ios, focusing on keypackage management and relay interaction capabilities. The implementation will enable the SDK to work with NIP-EE compliant relays like `wss://messaging.loxation.com`.

## Implementation Phases

### Phase 1: Core Event Types and Infrastructure

#### 1.1 Extend EventKind Enum
Update [`Sources/NostrSDK/EventKind.swift`](../Sources/NostrSDK/EventKind.swift:1) to include NIP-EE event kinds:

```swift
// MLS/NIP-EE event kinds
case mlsKeyPackage = 443
case mlsWelcome = 444  
case mlsGroupMessage = 445
case keyPackageRequest = 447
case rosterPolicy = 450
case keyPackageRelayList = 10051
```

Also update:
- `rawValue` computed property
- `classForKind` computed property
- `allCases` array

#### 1.2 Create KeyPackageEvent Class
Create [`Sources/NostrSDK/Events/KeyPackageEvent.swift`](../Sources/NostrSDK/Events/KeyPackageEvent.swift:1):
- Inherit from `NostrEvent`
- Parse and validate MLS-specific tags
- Provide convenient accessors for MLS parameters

#### 1.3 Create WelcomeEvent Class
Create [`Sources/NostrSDK/Events/WelcomeEvent.swift`](../Sources/NostrSDK/Events/WelcomeEvent.swift:1):
- Implement as per NIP-EE spec
- Handle gift-wrapping requirements
- Support unsealed content access

#### 1.4 Create GroupMessageEvent Class
Create [`Sources/NostrSDK/Events/GroupMessageEvent.swift`](../Sources/NostrSDK/Events/GroupMessageEvent.swift:1):
- Handle ephemeral pubkey requirements
- Support NIP-44 encrypted content

### Phase 2: Query and Subscription Enhancements

#### 2.1 Add Query Support with Timeout
Extend [`Sources/NostrSDK/Relay.swift`](../Sources/NostrSDK/Relay.swift:1) with query functionality:

```swift
protocol NostrTransport {
    func query(filter: Filter, timeout: TimeInterval) async -> [NostrEvent]
}
```

Implementation approach:
- Use async/await pattern
- Implement timeout handling
- Collect events until EOSE or timeout

#### 2.2 Add Specialized KeyPackage Subscription
Add to [`Sources/NostrSDK/Relay.swift`](../Sources/NostrSDK/Relay.swift:1):

```swift
extension NostrTransport {
    @discardableResult
    func subscribeKeyPackages(
        authors: [String],
        since: Int64?,
        onEvent: @escaping @Sendable (String) -> Void
    ) -> String
}
```

### Phase 3: Relay Management Features

#### 3.1 Create Relay Capabilities Structure
Create [`Sources/NostrSDK/RelayCapabilities.swift`](../Sources/NostrSDK/RelayCapabilities.swift:1):
- Track NIP-EE specific capabilities
- Support lifecycle management features
- Handle keypackage limits

#### 3.2 Create KeyPackageRelayListEvent
Create [`Sources/NostrSDK/Events/KeyPackageRelayListEvent.swift`](../Sources/NostrSDK/Events/KeyPackageRelayListEvent.swift:1):
- Kind 10051 support
- Relay list management

### Phase 4: Testing and Documentation

#### 4.1 Unit Tests
Create test files:
- [`Tests/NostrSDKTests/Events/KeyPackageEventTests.swift`](../Tests/NostrSDKTests/Events/KeyPackageEventTests.swift:1)
- [`Tests/NostrSDKTests/Events/WelcomeEventTests.swift`](../Tests/NostrSDKTests/Events/WelcomeEventTests.swift:1)
- [`Tests/NostrSDKTests/Events/GroupMessageEventTests.swift`](../Tests/NostrSDKTests/Events/GroupMessageEventTests.swift:1)
- [`Tests/NostrSDKTests/RelayQueryTests.swift`](../Tests/NostrSDKTests/RelayQueryTests.swift:1)

#### 4.2 Demo Implementation
Create [`demo/NostrSDKDemo/Demo Views/KeyPackageDemoView.swift`](../demo/NostrSDKDemo/Demo Views/KeyPackageDemoView.swift:1):
- Supply monitoring example
- Publishing keypackages example
- Fetching keypackages for group creation

## Technical Considerations

### 1. Event Structure
KeyPackageEvent (kind 443):
```json
{
  "kind": 443,
  "content": "<hex encoded serialized KeyPackageBundle>",
  "tags": [
    ["mls_protocol_version", "1.0"],
    ["ciphersuite", "0x0001"],
    ["extensions", "0x0001,0x0002"],
    ["client", "loxation-ios", "<handler_event_id>", "wss://messaging.loxation.com"],
    ["relays", "wss://messaging.loxation.com"],
    ["-"]
  ]
}
```

### 2. Query Implementation
The query function needs to:
1. Create subscription
2. Collect events
3. Wait for EOSE
4. Return collected events or timeout

### 3. Relay Lifecycle Management
Since `messaging.loxation.com` manages keypackage lifecycle:
- Client monitors supply levels
- Relay handles consumption tracking
- Client publishes new packages when needed

## Priority Implementation Order

### High Priority
1. EventKind enum extension ✅
2. KeyPackageEvent class
3. Query support with filters
4. Basic subscription support

### Medium Priority
1. WelcomeEvent class
2. GroupMessageEvent class
3. Specialized subscription methods
4. Relay capability detection

### Low Priority
1. KeyPackageRelayListEvent (kind 10051)
2. Advanced relay management features

## Success Criteria

1. Can query kind 443 events from relay
2. Can subscribe to keypackage updates
3. Can publish new keypackages
4. Can monitor keypackage supply
5. Can fetch keypackages for group members
6. All tests pass
7. Demo application works correctly

## Risk Mitigation

1. **Backward Compatibility**: All changes are additive, no breaking changes
2. **Performance**: Query timeout prevents hanging
3. **Error Handling**: Proper error propagation for invalid events
4. **Security**: No exposure of MLS cryptographic material beyond what's in events

## Timeline Estimate

- Phase 1: Core infrastructure setup
- Phase 2: Query and subscription implementation
- Phase 3: Relay management features
- Phase 4: Testing and documentation

## Next Steps

1. Review this plan with the team
2. Set up development branch
3. Begin implementation with Phase 1
4. Regular testing against `wss://messaging.loxation.com`