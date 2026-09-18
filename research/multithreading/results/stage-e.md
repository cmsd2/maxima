# Stage E results: validation

Change: `add-environment-accessor-layer`, tasks 7–10. The measurements
are in `docs/multithreading/06-environment-write-hook.md`.

## Validation ladder (doc 05)

| Level | Check | Result |
|---|---|---|
| 0 | Clean build; suite identical to baseline; timing within noise | ✓ |
| 1 | Spec scenarios, including refusal | ✓ 8 of 8 |
| 2 | Expected-writer table | ✓ 6 of 6, after correcting two triggers |
| 3 | Oracle: no unexplained class A outside documented classes | ✓ 0 undocumented |
| 4 | Seeded bypasses | ✓ all caught |
| 5 | Profiles repeatable | ✓ 3 workloads × 3 sessions |

## Findings in stage E

1. **Two expected-writer triggers were wrong,** and so was a claim in doc 03.
   - `rat(x+y)` alone writes no `DISREP`: `$rat` without explicit variables
     only renumbers the CRE gensyms' value cells (class C). `DISREP` is
     written when a CRE is converted back (`ratdisrep`, display). Trigger
     corrected to `ratdisrep(rat(x+y))`.
   - `rectform((-1)^a)` makes a redundant assumption (`-1 # 0`) and writes
     nothing. Trigger corrected to `rectform(x^a)`, which assumes `x # 0`.
2. **Scanner blind spot: `setf` through accessor macros.** `symbol-array`
   is a macro for `(get sym 'array)`. A new pre-pass treats any macro
   expanding to `get`/`symbol-plist` as a plist place. It found 7 run-time
   `(setf (symbol-array …))` sites (in `$array`, `arrstore`, `arraysize`,
   `mdefine`, …), now converted.
3. **Oracle blind spot: autoload through `aload`.** `autof`/`autom` stubs
   call `aload`, which calls CL `load` directly. The oracle now wraps
   `loadfile`, `batchload-stream`, `generic-autoload` and `aload`, and
   attributes each package load to its own `load:` unit.
4. **Funnelled writes to stored objects are now credited.** When `putprop`
   writes into an object stored in a slot (an `mprops` cell, a node
   plist), the resulting `:mutated` difference on the holding slot counts
   as explained. The seeded `rplacd` bypass is still caught.
