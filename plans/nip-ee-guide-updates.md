# NIP-EE-RELAY Guide Updates Plan

## Key Discrepancies Found

### 1. KeyPackage Event Content Encoding
- **NIP-EE-RELAY.md**: content is "hex encoded serialized KeyPackageBundle"
- **Current Guide**: Shows "base64-encoded-keypackage-data"
- **Fix**: Change all references from base64 to hex encoding

### 2. MLS Protocol Version Format
- **NIP-EE-RELAY.md**: "1.0"
- **Current Guide**: "mls/1.0"
- **Fix**: Update to use "1.0" format

### 3. Tag Structure
The specification defines specific tag formats:
```json
["mls_protocol_version", "1.0"],
["ciphersuite", "<MLS CipherSuite ID value e.g. '0x0001'>"],
["extensions", "<An array of MLS Extension ID values e.g. '0x0001, 0x0002'>"],
["client", "<client name>", "<handler event id>", "<optional relay url>"],
["relays", "<array of relay urls>"],
["-"]
```

### 4. Rate Limiting Information
- **NIP-EE-RELAY.md**: Specifies rate limits (10 queries/hour, max 2 per query)
- **Current Guide**: No rate limiting information
- **Fix**: Add rate limiting section

### 5. Event Kind 450 (Roster Policy)
- **NIP-EE-RELAY.md**: Not mentioned
- **Current Guide**: Lists kind 450
- **Fix**: Remove kind 450 reference

### 6. MLS Extensions
The spec requires:
- `required_capabilities`
- `ratchet_tree`
- `nostr_group_data`
- `last_resort` (highly recommended)

### 7. Additional Content to Add
- Information about the `nostr_group_data` extension
- Details about Welcome Event structure
- Group Event structure and encryption details
- Security considerations