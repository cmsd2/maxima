## Purpose

Makes every run-time change to Maxima's symbol-held environment observable
through one reporting point, so that tools can measure, audit or refuse
environment writes during a computation without changing its results.

## ADDED Requirements

### Requirement: Run-time property writes are observable

Every run-time write to a symbol property list made by core Maxima code SHALL
be reportable to an installed environment write observer. This covers
setting a property, removing a property and replacing a whole property list.
Each report MUST identify the object written (a symbol, or a non-symbol
database node), the property indicator where one applies, the new value where
one applies, and the kind of operation.

#### Scenario: Function definition is reported

- **WHEN** an observer is installed and the user evaluates `f(x) := x^2`
- **THEN** the observer receives at least one property-write report for the
  symbol `$f`

#### Scenario: Simplification rule is reported

- **WHEN** an observer is installed and the user evaluates
  `tellsimp(sin(42), foo)`
- **THEN** the observer receives a property-write report for `%sin`

#### Scenario: Property removal is reported

- **WHEN** an observer is installed and the user kills a previously defined
  function with `kill(f)`
- **THEN** the observer receives removal or plist-replacement reports for
  `$f`

#### Scenario: Hidden writes during a query are reported

- **WHEN** an observer is installed, `assume(x > 0)` has been evaluated, and
  the user evaluates `sign(x)`
- **THEN** the observer receives property-write reports even though the user
  requested no definition

### Requirement: Maxima-level assignment is observable

Every Maxima-level assignment to a variable's value, including the temporary
assignments made when binding function parameters, `block` locals and loop
variables, SHALL be reportable to an installed observer as a value-assignment
report that identifies the variable and the new value.

#### Scenario: Plain assignment is reported

- **WHEN** an observer is installed and the user evaluates `y : 5`
- **THEN** the observer receives a value-assignment report for `$y` with
  value 5

#### Scenario: Binding a block local is reported

- **WHEN** an observer is installed and the user evaluates
  `block([z : 1], z + 1)`
- **THEN** the observer receives value-assignment reports for `$z` on entry
  and on restoration at exit

### Requirement: Observation does not change results

Installing no observer SHALL leave every computation's results, printed
output and error behaviour unchanged from the code before this capability.
An installed observer that returns normally MUST NOT change results either.

#### Scenario: Test suite is unchanged without an observer

- **WHEN** the full test suite, share tests included, runs with no observer
  installed
- **THEN** it reports the same results as the baseline build, with no new
  unexpected failures and no newly unexpected passes

#### Scenario: Test suite is unchanged with a passive observer

- **WHEN** the full test suite runs with an observer installed that only
  counts reports
- **THEN** it reports the same results as the baseline build

#### Scenario: Differential corpus gives identical output

- **WHEN** a corpus of share tests, demo files and generated expressions is
  evaluated by the baseline build and by the changed build, with and without
  a passive observer, with `display2d:false`
- **THEN** the printed results of every corresponding input are
  character-for-character identical across all runs, apart from gensym names
  and timing output, which the comparison normalises

### Requirement: An observer can refuse a write

An installed observer SHALL be able to refuse a write by signalling an error.
The write MUST NOT take effect when the observer refuses it, and the error
MUST reach the caller as an ordinary error that error-catching constructs can
intercept.

#### Scenario: Refused definition leaves no trace

- **WHEN** an observer that refuses every write to `$g` is installed and the
  user evaluates `errcatch(g(x) := x)`
- **THEN** `errcatch` returns an empty list and `g` has no function
  definition afterwards

### Requirement: Observation is cheap when unused

With no observer installed, the extra cost per property write and per value
assignment SHALL be a single check of whether an observer is present. A full
test-suite run MUST NOT be measurably slower than the baseline build, where
"measurably" means outside the run-to-run spread seen when timing alternating
baseline and changed runs.

#### Scenario: Suite timing within noise

- **WHEN** the core test suite is timed in alternating runs of the baseline
  and changed builds, at least three runs each, discarding each build's first
  run
- **THEN** the difference between the builds' mean times is smaller than the
  larger build's run-to-run spread

### Requirement: Funnel completeness is checked

A static check SHALL report every run-time property-list write in the core
sources that bypasses the observable path, apart from entries on an explicit
allowlist that records why each exception is acceptable. The check MUST exit
successfully only when no unlisted bypass exists.

#### Scenario: A new bypass is caught

- **WHEN** a developer adds a direct property-list write inside a function
  body in the core sources and runs the check
- **THEN** the check exits unsuccessfully and names the file and enclosing
  function

#### Scenario: Load-time definitions are not flagged

- **WHEN** the check runs on sources whose only direct property writes occur
  at load time (top-level forms and property-definition macros)
- **THEN** the check exits successfully

### Requirement: Observed scope is stated precisely

The documentation SHALL define which classes of write the facility observes
and which it does not, so that "no write observed" has a defined meaning.

- **Observed classes:** property slot puts, removals and whole-plist
  replacements made through the observable path in the core sources;
  Maxima-level value assignment, binding and restoration.
- **Unobserved classes (at least):** in-place mutation of structures stored
  in properties; destructive edits of the global information lists such as
  `values` and `functions`; assignment to Lisp-level special variables; hash
  tables and arrays; add-on packages outside the core sources; writes made
  before an observer is installed.

Every allowlist entry of the static check MUST be accounted for in the
unobserved list.

#### Scenario: Scope statement available

- **WHEN** a developer reads the facility's documentation
- **THEN** it lists the observed classes and each unobserved class, and
  states that only the oracle can support a claim that nothing was written

#### Scenario: Allowlist mirrored

- **WHEN** the allowlist of the static check is compared with the documented
  unobserved classes
- **THEN** every allowlist entry falls within a documented unobserved class

### Requirement: Known hidden writers are reported

For each hidden writer identified in the concurrency analysis, running its
trigger with an observer installed SHALL produce a report of the expected
kind. The expected pairs are at least:

| Trigger | Expected report |
|---|---|
| `ratdisrep(rat(x+y))` | a property put of `disrep` on a Maxima-created symbol |
| `sign(x)` after `assume(x>0)` | label property puts on a database node |
| a limit taking the series path (`gruntz(x^2/exp(x), x, inf)`) | a put of `internal` on the limit variable |
| `integrate(1/(1+x^2), x)` (creates a temporary context) | a put of `subc` on a new context symbol |
| `rectform(x^a)` | fact-database writes for a temporary assumption |
| `block([z:1], z)` | an assignment and a restoration of `z` |

#### Scenario: Every expected writer fires

- **WHEN** each trigger in the table is evaluated in a fresh session with a
  recording observer
- **THEN** each produces at least one report matching its expected kind, and
  the test names any row that produced none

### Requirement: Unexplained environment changes are detected

An oracle independent of the observer SHALL compare a deep structural
fingerprint of environment state before and after an evaluation, and report
every difference that the observer's reports for that evaluation don't
explain. Environment state for this purpose covers at least:

- the property lists and values of every symbol in the Maxima package;
- the Maxima-created symbols reachable from the rational-function variable
  pool;
- the fact database's node and context structures.

The fingerprint MUST be deep enough to detect in-place mutation of structures
stored in properties.

#### Scenario: Suite runs with no unexplained differences

- **WHEN** the test suite runs with the oracle enabled for each test problem
- **THEN** every reported difference is either explained by an observer
  report or falls within a documented unobserved class, and the oracle lists
  any that do neither with the test file and problem number

#### Scenario: In-place mutation of a stored value is caught

- **WHEN** an evaluation destructively modifies a list stored in a property
  without writing the property slot
- **THEN** the oracle reports a difference for that symbol and indicator
  that no observer report explains

### Requirement: Checkers detect seeded bypasses

The static check and the oracle SHALL each be tested against deliberately
planted bypasses. The bypasses are at least:

- a direct property `setf` inside a function body;
- a property write through a functional `setf` call;
- a destructive `rplacd` on a stored property value;
- a destructive `nconc` onto a global information list.

Each planted bypass MUST be reported by the static check, by the oracle, or
by both.

#### Scenario: All seeded bypasses caught

- **WHEN** each seeded bypass is loaded into a test image and exercised
- **THEN** for each one, at least one checker reports it, and the test names
  any bypass that neither checker reported

### Requirement: Profiles are aggregated and repeatable

The facility SHALL provide a profile report that groups observed writes by
operation, object kind (user symbol, Maxima-created symbol, database node,
context) and indicator, without depending on generated symbol names.
Evaluating the same workload repeatedly in fresh sessions MUST produce
identical profiles.

#### Scenario: Repeated runs agree

- **WHEN** the same workload is profiled in three fresh sessions
- **THEN** the three aggregated profiles are identical

#### Scenario: Generated names don't split groups

- **WHEN** a workload creates CRE variables whose generated names differ
  between sessions
- **THEN** their writes are grouped under the Maxima-created symbol kind and
  the indicator, not under individual names
