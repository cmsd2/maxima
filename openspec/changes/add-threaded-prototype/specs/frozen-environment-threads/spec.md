## ADDED Requirements

### Requirement: Threaded results equal sequential results

For every run, the results produced by the thread pool SHALL be identical,
element for element and in order, to those produced by evaluating the same
items sequentially in one thread. A run whose results differ MUST be
reported as failed and excluded from timing.

#### Scenario: Threads match sequential

- **WHEN** a workload runs sequentially and then on the thread pool at any
  thread count
- **THEN** the two result lists are equal and the run is marked correct

#### Scenario: A planted fault is caught

- **WHEN** one thread returns a wrong value for one item
- **THEN** the run is reported failed, naming the first differing item

### Requirement: Writes are confined to the thread that makes them

Every symbol a worker assigns during the parallel region SHALL be bound in
that worker's own thread before the region starts, so that assignment
writes the thread's binding rather than the global value cell. The symbol
set comes from a recorded write trace of the same workload, not from
inspection.

#### Scenario: A worker's assignment does not reach other threads

- **WHEN** a worker assigns a Maxima variable during the region
- **THEN** no other worker and not the parent observes the new value, and
  the parent's value after the region is what it was before

#### Scenario: The symbol set comes from a trace

- **WHEN** the runner is configured for a workload
- **THEN** it takes its symbol set from that workload's recorded trace, and
  the trace used is named in the run record

### Requirement: An unconfined write is refused, not tolerated

A write to a symbol with no thread-local binding SHALL signal an error that
names the symbol and stops the run. Silence is not acceptable: such a write
reaches the global value cell and corrupts every other thread, and it
produces no other symptom.

#### Scenario: A symbol missing from the set is caught

- **WHEN** a worker assigns a symbol that was not bound at thread entry
- **THEN** the run fails with an error naming that symbol, and no result is
  reported as correct

#### Scenario: The guard is proven to fire

- **WHEN** the test suite for the runner deliberately assigns an unbound
  symbol inside the region
- **THEN** the guard reports it, and the test records that it did

### Requirement: Sign queries do not write to shared structure

Fact-database query labels SHALL be held in per-query state rather than
written as properties onto the database's nodes, so that a `sign` query
made while other threads run leaves no trace on structure they share.

#### Scenario: A query leaves the nodes unchanged

- **WHEN** `sign` is called on an expression whose atoms carry facts
- **THEN** the nodes involved carry no label properties afterwards, and the
  answer is the same as before the change

#### Scenario: Concurrent queries do not interfere

- **WHEN** several threads query the sign of expressions over the same
  assumed variables at once
- **THEN** each thread's answers match what it would get alone

### Requirement: The environment is frozen while threads run

The parallel region SHALL reject work that redefines functions, declares
properties, adds facts, kills bindings or loads files, because those change
structure every thread shares and no per-thread binding can confine them.

#### Scenario: A definition attempt inside the region is refused

- **WHEN** an item evaluates `:=`, `tellsimp`, `declare`, `kill`, `assume`
  or `load`
- **THEN** the run fails, naming the operation, rather than continuing with
  a definition some threads see and others do not

### Requirement: First-iteration writes are absorbed before the region

One iteration SHALL run to completion before the parallel region starts, so
that autoload, cache population and other one-time writes happen in one
thread. The run record MUST state that it happened.

#### Scenario: Warm-up precedes the region

- **WHEN** a threaded run starts
- **THEN** one item is evaluated first, outside the region, and the record
  says so

### Requirement: Threads are measured against the process pool

The measurement SHALL compare the thread pool with the process pool of
`process-pool-benchmark` on the same workload, machine and methodology:
fresh image per measurement, a discarded warm-up round, at least three
timed rounds, rotated configuration order, and recorded machine state.

#### Scenario: Both mechanisms reported together

- **WHEN** the sweep completes
- **THEN** the report gives, per worker count, each mechanism's median wall
  time, spread, speedup against sequential, and the ratio between them

#### Scenario: Synchronisation cost is reported

- **WHEN** the thread arm runs
- **THEN** the report states what the threaded run spends on locks and on
  the guard, so a win or loss can be attributed rather than guessed
