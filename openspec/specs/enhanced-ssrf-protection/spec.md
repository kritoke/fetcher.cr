# Enhanced SSRF Protection Specification

## ADDED Requirements

### Requirement: Comprehensive IPv6 link-local detection
The URL validator SHALL properly detect and block IPv6 link-local addresses.

#### Scenario: Block IPv6 link-local addresses (fe80::/10)
- **WHEN** validating a URL with an IPv6 link-local address (e.g., http://[fe80::1]/path)
- **THEN** the validator SHALL return false
- **AND** it SHALL detect addresses in the range fe80:: through febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff

#### Scenario: Block IPv6 link-local with zone ID
- **WHEN** validating a URL with an IPv6 link-local address and zone ID (e.g., http://[fe80::1%eth0]/path)
- **THEN** the validator SHALL return false
- **AND** it SHALL properly parse and validate the address despite the zone ID

#### Scenario: Allow IPv6 global addresses
- **WHEN** validating a URL with a global IPv6 address (e.g., http://[2001:db8::1]/path)
- **THEN** the validator SHALL return true
- **AND** it SHALL NOT block non-link-local, non-private IPv6 addresses

### Requirement: Block IPv6 unique local addresses
The URL validator SHALL block IPv6 unique local addresses (fc00::/7) to prevent SSRF attacks on internal networks.

#### Scenario: Block IPv6 unique local addresses (fc00::/7)
- **WHEN** validating a URL with an IPv6 unique local address (e.g., http://[fc00::1]/path or http://[fd00::1]/path)
- **THEN** the validator SHALL return false
- **AND** it SHALL detect addresses in the range fc00:: through fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff

#### Scenario: Allow IPv6 global unicast addresses
- **WHEN** validating a URL with a global IPv6 unicast address (e.g., http://[2607:f8b0::1]/path)
- **THEN** the validator SHALL return true
- **AND** it SHALL NOT block legitimate global IPv6 addresses

### Requirement: Proper IPv6 address parsing
The URL validator SHALL use proper IPv6 address parsing instead of string prefix matching.

#### Scenario: Parse IPv6 addresses with Socket::IPAddress
- **WHEN** validating a URL with an IPv6 address
- **THEN** the validator SHALL use Socket::IPAddress to parse the address
- **AND** it SHALL NOT rely on string prefix matching alone
- **AND** it SHALL handle all valid IPv6 address formats

#### Scenario: Handle IPv6 addresses with brackets
- **WHEN** validating a URL with bracketed IPv6 address (e.g., http://[::1]/path)
- **THEN** the validator SHALL properly extract the address from brackets
- **AND** it SHALL validate the address correctly

### Requirement: Block deprecated IPv6 site-local addresses
The URL validator SHALL block deprecated IPv6 site-local addresses (fec0::/10) for comprehensive protection.

#### Scenario: Block IPv6 site-local addresses (fec0::/10)
- **WHEN** validating a URL with a deprecated IPv6 site-local address (e.g., http://[fec0::1]/path)
- **THEN** the validator SHALL return false
- **AND** it SHALL detect addresses in the range fec0:: through feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff

### Requirement: Configurable SSRF protection
The system SHALL provide configuration options to customize or disable SSRF protection for trusted environments.

#### Scenario: Default SSRF protection enabled
- **WHEN** no SSRF configuration is provided
- **THEN** the system SHALL block all private IP addresses (IPv4 and IPv6)
- **AND** it SHALL block link-local addresses
- **AND** it SHALL block localhost and similar addresses

#### Scenario: Disable SSRF protection for trusted environments
- **WHEN** ssl_verify is set to false OR a new ssrf_protection_enabled flag is set to false
- **THEN** the URL validator SHALL allow private IP addresses
- **AND** it SHALL log a security warning about disabled SSRF protection
- **AND** it SHALL still validate URL format and scheme

#### Scenario: Custom IP whitelist
- **WHEN** a custom IP whitelist is configured
- **THEN** the URL validator SHALL allow whitelisted IP addresses
- **AND** it SHALL block all other private IP addresses not in the whitelist

### Requirement: Enhanced error messages for blocked IPs
The URL validator SHALL provide clear error messages when URLs are blocked due to SSRF protection.

#### Scenario: Log blocked IPv4 private IP
- **WHEN** a URL with a private IPv4 address is blocked
- **THEN** the system SHALL log "Blocked private IP: <address>"
- **AND** it SHALL include the type of private range (e.g., "RFC 1918 private network")

#### Scenario: Log blocked IPv6 link-local
- **WHEN** a URL with an IPv6 link-local address is blocked
- **THEN** the system SHALL log "Blocked IPv6 link-local address: <address>"
- **AND** it SHALL help users understand why the URL was blocked

### Requirement: Comprehensive IPv4 private range blocking
The URL validator SHALL block all IPv4 private ranges as currently implemented.

#### Scenario: Block RFC 1918 private networks
- **WHEN** validating a URL with an IPv4 address in 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16
- **THEN** the validator SHALL return false
- **AND** it SHALL continue to block these ranges as before

#### Scenario: Block IPv4 loopback
- **WHEN** validating a URL with 127.0.0.0/8 or 0.0.0.0
- **THEN** the validator SHALL return false
- **AND** it SHALL continue to block loopback addresses

#### Scenario: Block IPv4 link-local
- **WHEN** validating a URL with 169.254.0.0/16
- **THEN** the validator SHALL return false
- **AND** it SHALL continue to block IPv4 link-local addresses
