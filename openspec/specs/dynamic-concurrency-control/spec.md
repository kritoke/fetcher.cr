# Dynamic Concurrency Control

## Purpose

This specification defines the requirements for adaptive concurrency control that adjusts based on system resources to optimize performance and prevent resource exhaustion.

## Requirements

### Requirement: Dynamic Concurrency Control
The system SHALL replace fixed semaphore concurrency limits with adaptive concurrency control based on system resources, configurable via feeds.yml.

#### Scenario: System resource based concurrency
- **WHEN** the system has sufficient available memory and CPU capacity
- **THEN** the concurrency limit increases to utilize available resources
- **WHEN** system resources are constrained
- **THEN** the concurrency limit decreases to prevent resource exhaustion

#### Scenario: Configurable maximum concurrency
- **WHEN** feeds.yml includes max_concurrent_fetches setting
- **THEN** the system respects this as the upper bound for concurrency
- **WHEN** no configuration is provided
- **THEN** the system calculates concurrency based on available CPU cores (default: 2 * core count)

#### Scenario: Real-time concurrency adjustment
- **WHEN** system resource availability changes during operation
- **THEN** the concurrency limit adjusts dynamically within configured bounds