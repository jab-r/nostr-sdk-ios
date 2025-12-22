# NostrSDK Modifications for Filter Detection

## Problem
The current RelayDelegate protocol doesn't expose incoming REQ filter information, which is needed to detect relay-initiated KeyPackage replenishment requests as specified in NIP-EE-RELAY.

## Proposed Solution

### 1. Update RelayDelegate Protocol

Add a new method to detect incoming subscription requests:

```swift
/// An optional interface for receiving state updates and responses from relays.
public protocol RelayDelegate: AnyObject {
    func relayStateDidChange(_ relay: Relay, state: Relay.State)
    func relay(_ relay: Relay, didReceive response: RelayResponse)
    func relay(_ relay: Relay, didReceive event: RelayEvent)
    
    /// Called when the relay receives a subscription request (REQ)
    /// - Parameters:
    ///   - relay: The relay that received the request
    ///   - subscriptionId: The subscription ID from the REQ message
    ///   - filter: The filter object from the REQ message
    func relay(_ relay: Relay, didReceiveSubscriptionRequest subscriptionId: String, filter: Filter)
}
```

### 2. Update RelayResponse Enum

Add a new case to handle REQ messages:

```swift
public enum RelayResponse {
    case event(String, NostrEvent)
    case ok(String, Bool, String?)
    case endOfStoredEvents(String)
    case notice(String)
    case auth(String)
    case count(String, Int)
    
    /// New case for subscription requests
    case subscription(String, Filter)
}
```

### 3. Update RelayResponse Decoding

Modify the decode method to handle REQ messages:

```swift
extension RelayResponse {
    static func decode(data: Data) -> RelayResponse? {
        // Existing decoding logic...
        
        // Add handling for REQ messages
        if messageType == "REQ",
           array.count >= 3,
           let subscriptionId = array[1] as? String,
           let filterData = array[2] as? [String: Any] {
            if let filter = Filter.decode(from: filterData) {
                return .subscription(subscriptionId, filter)
            }
        }
        
        // Rest of the existing logic...
    }
}
```

### 4. Update Relay.receive Method

Modify the receive method to call the delegate when REQ is detected:

```swift
private func receive(_ message: URLSessionWebSocketTask.Message) {
    func handle(messageData: Data) {
        guard let response = RelayResponse.decode(data: messageData) else {
            return
        }

        delegate?.relay(self, didReceive: response)

        switch response {
        case .event(let subscriptionId, let event):
            let relayEvent = RelayEvent(event: event, subscriptionId: subscriptionId)
            events.send(relayEvent)
            delegate?.relay(self, didReceive: relayEvent)
            
        case .subscription(let subscriptionId, let filter):
            // Call the new delegate method
            delegate?.relay(self, didReceiveSubscriptionRequest: subscriptionId, filter: filter)
            
        default:
            break
        }
    }
    
    // Rest of the method remains the same...
}
```

## Implementation Notes

1. **Backward Compatibility**: Make the new delegate method optional with a default implementation:

```swift
extension RelayDelegate {
    func relay(_ relay: Relay, didReceiveSubscriptionRequest subscriptionId: String, filter: Filter) {
        // Default empty implementation for backward compatibility
    }
}
```

2. **Security Consideration**: Only expose REQ messages that target the current user's KeyPackages to avoid leaking information about other users' queries.

3. **Performance**: The filter decoding should be efficient to avoid impacting relay performance.

## Usage Example

With these modifications, detecting relay-initiated replenishment becomes straightforward:

```swift
class KeyPackageReplenishmentMonitor: RelayDelegate {
    private let myPublicKey: String
    
    func relay(_ relay: Relay, didReceiveSubscriptionRequest subscriptionId: String, filter: Filter) {
        // Check if this is a query for our own KeyPackages
        if let authors = filter.authors,
           authors.contains(myPublicKey),
           let kinds = filter.kinds,
           kinds.contains(EventKind.mlsKeyPackage.rawValue) {
            
            print("Relay is requesting KeyPackage replenishment")
            
            Task {
                await replenishKeyPackages()
            }
        }
    }
    
    // Other delegate methods...
}
```

This approach provides a clean and efficient way to detect relay-initiated KeyPackage queries while maintaining backward compatibility.