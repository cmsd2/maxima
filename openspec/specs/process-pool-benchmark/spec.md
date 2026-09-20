# process-pool-benchmark Specification

## Purpose

Measures how Maxima computations scale when their independent work items
are spread over forked worker processes, so that any later thread mode can
be judged against a measured process baseline instead of a sequential run.

## Requirements

### Requirement: Pooled results equal sequential results

For every benchmark run, the list of results produced by the process pool
SHALL be identical, element for element and in order, to the list produced
by evaluating the same work items sequentially in one process. A run whose
results differ MUST be reported as failed and excluded from timing results.

#### Scenario: Pool matches sequential

- **WHEN** a workload is run sequentially and then through the pool with any
  worker count and either scheduling mode
- **THEN** the two result lists are equal and the run is marked correct

#### Scenario: A mismatch is caught

- **WHEN** a worker returns a wrong result for one item (a deliberately
  planted fault in a test run)
- **THEN** the run is reported as failed, naming the first differing item

### Requirement: Workers share nothing at run time

Workers SHALL start from the parent's environment as it was at fork time,
and nothing a worker changes in its own environment may reach the parent or
other workers. Only each item's returned value comes back to the parent.

#### Scenario: Worker side effects stay in the worker

- **WHEN** a work item assigns a global variable and defines a function in
  a worker
- **THEN** after the run, the parent has neither the variable nor the
  function, and the returned values are still correct

### Requirement: Scaling curve with repeats

The benchmark SHALL measure wall time for the sequential baseline and for
the pool at 1, 2, 3, 4, 6, 8 and 10 workers, with at least three timed
repeats per configuration after a discarded warm-up run, alternating
configurations rather than running them in blocks. It MUST report the
median time, the run-to-run spread, speedup relative to sequential, and
parallel efficiency, for each configuration and each workload size.

#### Scenario: Curve reported with spread

- **WHEN** the benchmark completes for a workload
- **THEN** the report gives, per worker count, the median wall time, its
  spread, the speedup and the efficiency, and marks the worker counts that
  exceed the number of performance cores

### Requirement: Memory is measured per worker and in total

The benchmark SHALL record the peak resident memory of the parent and of
each worker during every pooled run, and the total across all of them. It
MUST state how shared copy-on-write pages are counted, so that the total is
not mistaken for private memory.

#### Scenario: Memory reported for the largest run

- **WHEN** the 10-worker run of the largest workload completes
- **THEN** the report gives peak per-worker memory, the summed total, and a
  note on how pages shared through fork are counted

### Requirement: Overheads and load balance are measured

The benchmark SHALL measure:

- the time to fork the workers;
- the time to transfer results back;
- the per-item cost distribution in the sequential run (mean and coefficient
  of variation);
- the GC share of sequential run time.

For pooled runs it MUST report load imbalance: the spread of busy time
across workers. Both static chunking and dynamic scheduling are measured.

#### Scenario: Scheduling modes compared

- **WHEN** the 4-worker and 10-worker runs complete in both scheduling modes
- **THEN** the report gives each mode's wall time and worker busy-time
  spread, so the effect of scheduling on imbalance is visible

#### Scenario: Model parameters recorded

- **WHEN** the sequential baseline completes
- **THEN** the report gives the GC share, the per-item mean and coefficient
  of variation, and the fork and transfer overheads, as parameters of doc 02's
  performance model

### Requirement: Scalability model fitted

The benchmark SHALL fit the Universal Scalability Law
`C(p) = p / (1 + σ(p − 1) + κ·p(p − 1))` to the measured throughput curve
and report the fitted contention and coherency parameters with the fit
residual. The fit MUST be reported separately for worker counts up to the
number of performance cores and for the full curve, because the machine has
two core types.

#### Scenario: Fit reported

- **WHEN** the scaling curve for a workload is complete
- **THEN** the report gives σ, κ and the residual for both ranges, and the
  worker count at which throughput peaks if κ > 0

### Requirement: Results are reproducible and documented

The benchmark SHALL be runnable from one script against a built Maxima
tree, and SHALL record the machine's core layout and memory, the SBCL
version, the Maxima commit, and the workload definitions alongside the
results. The results document MUST state that it contains no thread
measurement and why.

#### Scenario: Rerun on the same machine

- **WHEN** the benchmark script is run twice on the same machine and commit
- **THEN** both runs report the same correctness outcome, and their median
  times per configuration agree within the reported spread
