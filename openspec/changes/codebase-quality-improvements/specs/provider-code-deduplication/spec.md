# Provider Code Deduplication Specification

## ADDED Requirements

### Requirement: Extract shared provider logic
GitLab and Codeberg provider implementations SHALL share common code patterns.

#### Scenario: GitLab and Codeberg share base URL
- **WHEN** fetching releases from GitLab or Codeberg
- **THEN** both SHALL use the same base logic:
  - API endpoint detection
  - API response parsing
  - Atom feed fallback
  - Tag extraction from title/content
- **AND** the code SHALL be DRY (no duplication)

### Requirement: Provider abstraction module
The system SHALL include a `ForgeProvider` module with shared logic for API-based and Atom-based release fetching.

#### Scenario: API-based release fetch
- **WHEN** fetching releases via API
- **THEN** the `ForgeProvider` SHALL:
  - Build API URL
  - Parse response
  - Map to Entry objects
- **AND** the shared code SHALL not be duplicated across providers

#### Scenario: Atom feed fallback
- **WHEN** API fetch fails or returns empty
- **THEN** the `ForgeProvider` SHALL try Atom feed as fallback
- **AND** the Atom parser SHALL be reused across providers

### Requirement: Provider-specific configuration
Each provider SHALL have configurable endpoints and metadata extraction.

#### Scenario: GitLab configuration
- **WHEN** configuring GitLab provider
- **THEN** the system SHALL support:
  - Base URL (for self-hosted instances)
  - API version
  - Atom feed paths
- **AND** the configuration SHALL be used by both API and Atom fallback attempts

#### Scenario: Codeberg configuration
- **WHEN** configuring Codeberg provider
- **THEN** the system SHALL support:
  - Base URL (codeberg.org)
  - API version
  - Atom feed paths
- **AND** the configuration SHALL be used consistently with GitLab
