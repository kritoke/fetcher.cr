# URL Validation Improvements Specification

## MODIFIED Requirements

### Requirement: Reduced cyclomatic complexity
The URL validator SHALL have methods with cyclomatic complexity within acceptable limits (≤ 12).

#### Scenario: Refactor validate_uri method
- **WHEN** the validate_uri method is refactored
- **THEN** its cyclomatic complexity SHALL be ≤ 12
- **AND** it SHALL maintain the same validation behavior
- **AND** it SHALL extract IP validation into separate helper methods

#### Scenario: Extract IP address validation
- **WHEN** validating IP addresses
- **THEN** the code SHALL use dedicated methods for IPv4 and IPv6 validation
- **AND** each method SHALL have complexity ≤ 12
- **AND** the methods SHALL be reusable and testable independently

### Requirement: Comprehensive IPv6 support
The URL validator SHALL properly handle all IPv6 address formats and ranges.

#### Scenario: Handle IPv6 with zone IDs
- **WHEN** validating URLs with IPv6 zone IDs (e.g., http://[fe80::1%eth0]/path)
- **THEN** the validator SHALL parse the address correctly
- **AND** it SHALL remove the zone ID for validation
- **AND** it SHALL validate the base IPv6 address

#### Scenario: Handle IPv6 mapped IPv4 addresses
- **WHEN** validating URLs with IPv6 mapped IPv4 addresses (e.g., http://[::ffff:192.168.1.1]/path)
- **THEN** the validator SHALL detect the embedded IPv4 address
- **AND** it SHALL apply IPv4 private range rules to the embedded address
- **AND** it SHALL block private IPv4 addresses in mapped format

### Requirement: Clean and maintainable code
The URL validator SHALL be free of code quality issues identified by static analysis.

#### Scenario: Remove redundant nil returns
- **WHEN** methods in URL validator return nil explicitly
- **THEN** such returns SHALL be replaced with Crystal's implicit nil handling
- **AND** the code SHALL pass ameba Style/RedundantNilInControlExpression checks

#### Scenario: Use proper string methods
- **WHEN** checking for multiline strings or patterns
- **THEN** the code SHALL use heredoc syntax where appropriate
- **AND** it SHALL pass ameba Style/MultilineStringLiteral checks

## ADDED Requirements

### Requirement: IPv6 range validation methods
The URL validator SHALL provide dedicated methods for checking IPv6 address ranges.

#### Scenario: Check IPv6 link-local range
- **WHEN** checking if an IPv6 address is link-local
- **THEN** the is_ipv6_link_local? method SHALL return true for fe80::/10
- **AND** it SHALL use proper IP address parsing
- **AND** it SHALL not rely on string prefix matching

#### Scenario: Check IPv6 unique local range
- **WHEN** checking if an IPv6 address is unique local
- **THEN** the is_ipv6_unique_local? method SHALL return true for fc00::/7
- **AND** it SHALL handle both fc00::/8 and fd00::/8 ranges

#### Scenario: Check IPv6 site-local range (deprecated)
- **WHEN** checking if an IPv6 address is site-local
- **THEN** the is_ipv6_site_local? method SHALL return true for fec0::/10
- **AND** it SHALL document that site-local is deprecated but still checked for security

### Requirement: IPv6 loopback and unspecified detection
The URL validator SHALL properly detect IPv6 loopback and unspecified addresses.

#### Scenario: Block IPv6 loopback
- **WHEN** validating a URL with IPv6 loopback address (::1)
- **THEN** the validator SHALL return false
- **AND** it SHALL log appropriate error message

#### Scenario: Block IPv6 unspecified address
- **WHEN** validating a URL with IPv6 unspecified address (::)
- **THEN** the validator SHALL return false
- **AND** it SHALL treat :: as equivalent to 0.0.0.0 in IPv4

### Requirement: Comprehensive address range documentation
The URL validator code SHALL document all blocked IP ranges with RFC references.

#### Scenario: Document IPv4 private ranges
- **WHEN** reviewing URL validator code
- **THEN** each blocked IPv4 range SHALL have a comment with RFC reference
- **AND** it SHALL explain why the range is blocked (e.g., "RFC 1918 private network")

#### Scenario: Document IPv6 ranges
- **WHEN** reviewing URL validator code
- **THEN** each blocked IPv6 range SHALL have a comment with RFC reference
- **AND** it SHALL explain the purpose of the range (link-local, unique local, etc.)
