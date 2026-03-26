# String Builder Optimization Specification

## ADDED Requirements

### Requirement: Use String::Builder in streaming parsers
The streaming RSS parser SHALL use `String::Builder` for text content accumulation instead of string concatenation.

#### Scenario: Build text content efficiently
- **WHEN** reading text content from XML nodes in `StreamingRSSParser`
- **THEN** the code SHALL use `String::Builder` 
- **AND** the builder SHALL be initialized with estimated capacity
- **AND** text SHALL be appended using `<<` operator
- **AND** the final string SHALL be created via `builder.to_s` only once

### Requirement: Pre-allocate builder capacity
String builders SHALL be pre-allocated with reasonable capacity estimates.

#### Scenario: Estimate capacity from average entry size
- **WHEN** creating a String::Builder for RSS entry content
- **THEN** the initial capacity SHALL be at least 256 bytes
- **AND** if content exceeds capacity, the builder SHALL grow automatically
- **AND** growth SHALL use geometric expansion (e.g., 1.5x current capacity)
