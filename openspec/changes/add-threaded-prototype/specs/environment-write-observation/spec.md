## ADDED Requirements

### Requirement: Writes can be observed while threads run

The write observer SHALL be usable inside a threaded region, recording
which thread made each write, so that a workload's write trace can be taken
under the conditions it will actually run in.

#### Scenario: A trace attributes writes to threads

- **WHEN** a workload runs on the thread pool with the observer active
- **THEN** each recorded write carries the thread that made it, and the
  trace can be compared against the same workload's single-threaded trace

#### Scenario: The observer itself is confined

- **WHEN** several threads write at once with the observer active
- **THEN** no write is lost or attributed to the wrong thread, and the
  observer's own state is not shared in a way that corrupts the trace
