# Regex Caching Specification

## ADDED Requirements

### Requirement: Pre-compiled regex patterns
URL detection patterns SHALL be pre-compiled as class-level constants for performance.

#### Scenario: URL pattern matching
- **WHEN** detecting driver type from URLs
- **THEN** the system SHALL use pre-compiled regex constants
- **AND** the matching SHALL not recompile the regex on each call
- **AND** the performance SHALL be improved (especially in hot paths like `detect_driver`)

### Requirement: Cache regex patterns at memory
All regex patterns SHALL be cached at memory for the use.

#### Scenario: Memory efficiency
- **WHEN** the regex module is loaded
- **THEN** the cached regex patterns SHALL remain in memory
- **AND** the system SHALL not recompile patterns unnecessarily

### Requirement: Regex patterns for software module
The software module SHALL use pre-compiled regex for GitHub, GitLab, and Codeberg URL detection.

#### Scenario: GitHub URL matching
- **WHEN** fetching releases from GitHub
- **THEN** the system SHALL use pre-compiled regex patterns for GitHub and GitLab and Codeberg
- **AND** the matching SHALL be O(1) at and be for URL recompilation

### Requirement: Thread-safe pattern compilation
All regex patterns SHALL be compiled in a thread-safe manner.

#### Scenario: Concurrent access
- **WHEN** multiple fibers access the same regex pattern concurrently
- **THEN** the compiled regex SHALL be safely sharedable across fibers
- **AND** no race conditions or data corruption shall occur
