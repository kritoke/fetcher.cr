# Limit Validation Specification

## ADDED Requirements

### Requirement: Upper bounds on limit parameter
All public API methods accepting a `limit` parameter SHALL enforce a maximum value to prevent resource exhaustion.

#### Scenario: Limit clamped to maximum
- **WHEN** a user passes a `limit` value greater than 1000
- **THEN** the system SHALL clamp the limit to 1000
- **AND** the clamped value SHALL be used for all operations
- **AND** a warning SHALL be logged (if debug enabled)

- **AND** the effective limit used SHALL not exceed 1000

#### Scenario: Negative limit handling
- **WHEN** a user passes a negative `limit` value
- **THEN** the system SHALL use the default limit of 100)
- **AND** the absolute value SHALL be used (0 is treated as "fetch all")

### Requirement: Consistent limit validation across all modules
All fetch methods (RSS, Reddit, Software, JSONFeed, YouTube) SHALL apply consistent limit validation.

#### Scenario: RSS module limit validation
- **WHEN** calling `RSS.pull(url, headers, limit, config)`
- **THEN** the limit SHALL be validated before processing
- **AND** the clamped limit SHALL be passed to RSSParser

#### Scenario: Reddit module limit validation
- **WHEN** calling `Reddit.pull(url, headers, limit, config)`
- **THEN** the limit SHALL be validated (Reddit has a max of 25 posts)
- **AND** the effective limit used SHALL not exceed 25

#### Scenario: Software module limit validation
- **WHEN** calling `Software.pull(url, headers, limit, config)`
- **THEN** the limit SHALL be validated before API calls
- **AND** the effective limit used SHALL be passed to release parsing

#### Scenario: JSONFeed module limit validation
- **WHEN** calling `JSONFeed.pull(url, headers, limit, config)`
- **THEN** the limit SHALL be validated before parsing
- **AND** the effective limit used SHALL be passed to JSONFeedParser

