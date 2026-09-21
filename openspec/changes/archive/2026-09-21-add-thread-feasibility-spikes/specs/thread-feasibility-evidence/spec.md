## ADDED Requirements

### Requirement: Allocation profile matched to the real workload

The GC spike SHALL allocate at a per-worker rate and object-lifetime
profile taken from a measured Maxima run, not from a guess, and MUST record
the measured rate it reproduced. The reference is `wc_systematic` at 12
tolerances: 48 GB consed in 63 s of wall time, 0.76 GB/s, with a 1.5% GC
share in one worker.

#### Scenario: Calibration is checked, not assumed

- **WHEN** the spike's allocation loop runs in one thread
- **THEN** its measured allocation rate is within 20% of 0.76 GB/s, and the
  report states the rate achieved
- **AND** if calibration cannot be met, the spike reports the rate it did
  achieve rather than presenting scaling results as comparable

#### Scenario: Object lifetimes resemble the workload

- **WHEN** the allocation loop is configured
- **THEN** most allocated objects die in the nursery, with a stated
  fraction surviving to later generations, matching the survival fraction
  measured from the Maxima run

### Requirement: Threads and processes measured under one harness

The spike SHALL measure the same allocation work in *p* native threads and
in *p* forked processes for *p* = 1, 2, 4 and 8, from the same built image
and in the same run, so the two arms differ only in the mechanism.

#### Scenario: Both arms reported

- **WHEN** the spike completes
- **THEN** the report gives, for each *p* and each arm, median wall time,
  run-to-run spread, speedup against that arm's own *p* = 1 time, and
  parallel efficiency

#### Scenario: Forking stays legal

- **WHEN** the process arm forks workers
- **THEN** it forks from a single-threaded image, before any benchmark
  thread is created, because `sb-posix:fork` is unsafe in a multi-threaded
  image

### Requirement: Collector behaviour reported, not inferred

The spike SHALL report garbage-collector behaviour directly: total GC time,
number of collections, and the share of wall time each thread spends
stopped. A speedup number alone does not satisfy this requirement, because
it cannot distinguish GC serialisation from memory-bandwidth saturation.

#### Scenario: GC time attributed

- **WHEN** the thread arm runs at *p* = 4
- **THEN** the report states total GC time, collection count, and the
  per-thread stopped share, and names which of GC or bandwidth accounts for
  the gap between measured and ideal speedup

#### Scenario: Collector identified

- **WHEN** any spike run starts
- **THEN** the record includes the SBCL version and the collector features
  in force (`:gencgc`, `:mark-region`, `:gc-parallel`), since the answer is
  specific to the collector that produced it

### Requirement: Binding cost measured against the current mechanism

The `progv` spike SHALL measure `progv` against the save-assign-restore
pattern Maxima uses today in `mbind`/`munbind`, over 1, 2, 5 and 10
variables per binding, reporting nanoseconds per binding and bytes consed
per binding for both.

#### Scenario: Both mechanisms timed

- **WHEN** the microbenchmark runs
- **THEN** it reports, per variable count, the cost of each mechanism and
  the ratio between them

#### Scenario: Compiled, not interpreted

- **WHEN** the microbenchmark is loaded
- **THEN** it is compiled, and the timing loop is structured so the
  compiler cannot elide the binding it is measuring

### Requirement: Microbenchmark converted to a whole-workload estimate

A cost per binding is not an answer on its own. The spike SHALL count how
often `mbind` runs during a real Maxima workload and combine that count
with the measured per-binding cost to estimate the whole-workload cost of
switching to `progv`, stated as a percentage of run time.

#### Scenario: Frequency counted from a real run

- **WHEN** the counting instrumentation runs over the core test suite and
  over `wc_systematic`
- **THEN** the report gives calls per second and variables bound per call
  for each, and the resulting estimated percentage cost

### Requirement: Thresholds fixed before the measurements

Pass, fail and inconclusive thresholds for both spikes SHALL be written
down before the measurements are taken, and the recorded result MUST be
judged against those thresholds, not against thresholds chosen afterwards.

#### Scenario: Thresholds precede data

- **WHEN** the spikes are run
- **THEN** the thresholds in the design document are already committed, and
  the decision record cites them unchanged

#### Scenario: A failing result is reported as failing

- **WHEN** a measurement falls below its stated pass threshold
- **THEN** the decision record states that the spike failed and recommends
  stopping the threading path, without reinterpreting the threshold

### Requirement: Measurements taken under recorded, quiet conditions

Every measurement SHALL record machine state (total CPU busy across all
processes, load average, power source, battery level, SBCL version, commit)
and SHALL be taken on a machine whose total CPU use before the run is below
250% of one core. Load average alone is not an acceptable idleness test.

#### Scenario: Conditions recorded per run

- **WHEN** a measurement record is written
- **THEN** it carries the machine state fields, so a later reader can tell a
  quiet run from a disturbed one

#### Scenario: Warm-up discarded

- **WHEN** a configuration is measured
- **THEN** the first round is discarded and at least three timed rounds
  follow, with configuration order rotated rather than run in blocks

### Requirement: A single recommendation is recorded

The change SHALL produce a decision record in `docs/multithreading/` that
states, for each spike, the measured value, the threshold and the verdict,
and ends with one recommendation: proceed to step 1 of the threading path,
proceed with a stated design change, or stop and ship a process-based
parallel map.

#### Scenario: Record is decisive

- **WHEN** both spikes have run
- **THEN** the document names one of the three outcomes, with the numbers
  that justify it and the conditions under which it would be revisited
