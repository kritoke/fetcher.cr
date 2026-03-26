## ADDED Requirements

### Requirement: Domain Batch Processing
The system SHALL group feeds by domain to reduce DNS lookups and TLS handshakes, implementing domain-based rate limiting.

#### Scenario: Domain-based feed grouping
- **WHEN** multiple feeds are scheduled for fetching
- **THEN** feeds from the same domain are grouped together
- **THEN** DNS lookups and TLS handshakes are minimized through reuse

#### Scenario: Domain rate limiting
- **WHEN** feeds from the same domain are processed
- **THEN** requests are throttled according to domain-specific rate limits
- **THEN** default rate limit is applied when no specific configuration exists

#### Scenario: Concurrent cross-domain processing
- **WHEN** feeds from different domains are available
- **THEN** they are processed concurrently across domains
- **THEN** within each domain, processing follows the configured rate limits

#### Scenario: Configurable domain settings
- **WHEN** feeds.yml includes domain-specific configuration
- **THEN** the system applies custom rate limits, retry policies, or timeout settings per domain