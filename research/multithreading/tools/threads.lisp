;;; Thread runner for the frozen-environment prototype
;;; (add-threaded-prototype, stage A).
;;;
;;; Each worker enters through PROGV over a symbol set, so that MSET's
;;; (SETF (SYMBOL-VALUE X) Y) writes the worker's own binding rather than
;;; the global value cell.  Verified on this build: a SETF of a symbol bound
;;; in this thread stays in the thread; the same SETF with nothing bound
;;; writes the global cell and every thread sees it.  That second case is
;;; silent, which is why THREAD-GUARD exists.
;;;
;;; What binding confines: Maxima-level assignment and binding (MSET), and
;;; Lisp specials the workload SETQs.
;;; What it does NOT confine: property-list writes.  Those go onto structure
;;; every thread shares, and the guard reports them unless they are
;;; explicitly tolerated for the run.
;;;
;;; Loads after pool.lisp.

(in-package :maxima)
;; SB-THREAD is built into this image, not a loadable module.

;;; ------------------------------------------------------- the symbol set

(defparameter +thread-special-names+
  '(;; driver-io
    "*STANDARD-OUTPUT*" "*STANDARD-INPUT*" "*QUERY-IO*" "*STREAM-ALIST*"
    "*MREAD-PROMPT*" "*PARSE-STRING-INPUT-STREAM*" "*CURRENT-LINE-INFO*"
    "*PARSE-WINDOW*"
    ;; repl-labels
    "$%" "$LABELS" "$LINENUM" "*LINELABEL*"
    ;; eval-trace
    "*LAST-MEVAL1-FORM*" "*MLAMBDA-CALL-STACK*" "*$ERRORMSG-VALUE*" "$ERROR"
    ;; cre-pool
    "VARLIST" "GENVAR"
    ;; bigfloat-cache
    "*BFLOAT-HEADER*" "*BFLOAT-HEADER-PREC*" "*BIGFLOATZERO*" "*BIGFLOATONE*"
    "*BFHALF*" "*BFMHALF*" "FPPREC"
    ;; result-vars
    "$%RNUM_LIST" "$MULTIPLICITIES" "$PIECE"
    ;; algorithm-scratch
    "*CANCELLED" "*M" "XA*" "*COLINV*" "*COL*" "*ROW*" "*MAT*" "*JM*"
    "*MINOR1*" "*CHRPS*" "*ACURSOR*" "LIMK" "NN*" "*PRIME" "ANS"
    ;; the binding stack MBIND and MUNBIND push onto
    "BINDLIST" "MSPECLIST"
    ;; the local() frame stack: every MLAMBDA call, block and ev pushes a
    ;; frame on entry and MUNLOCAL pops it on exit, with MPROPLIST and
    ;; FACTLIST alongside.  Not in the earlier classification: the hook
    ;; cannot see a Lisp PUSH, and the oracle's snapshot never saw a change
    ;; because each iteration restores it (doc 05's stated blind spot).
    ;; Shared across threads, lost-update pushes and pops let MUNLOCAL walk
    ;; past a thread's own frames and "restore" whatever it found there.
    "LOCLIST" "MPROPLIST" "FACTLIST"
    ;; set with a raw SETQ by every block statement
    "$%%"
    ;; factdb-scratch: the fact database's per-query state (db.lisp), reset
    ;; by CLEAR at the start of every query
    "+LABS" "-LABS" "ULABS" "+S" "+SM" "+SL" "-S" "-SM" "-SL" "*LABS*"
    "*LPRS*" "*LABINDEX*" "*LPRINDEX*" "*MARKS*" "*DB*" "CURRENT" "+L" "-L")
  "Specials the earlier change classified T1: confined by a binding at
   thread entry.  Names, not symbols, because a few live in COMMON-LISP and
   the rest in MAXIMA; see research/multithreading/oracle-churn.tsv.")

(defparameter +thread-fresh-bindings+
  `(("*+LABS-TABLE*" . ,(lambda () (make-hash-table :test 'eq)))
    ("*-LABS-TABLE*" . ,(lambda () (make-hash-table :test 'eq)))
    ;; Same constructor as globals.lisp.  MLAMBDA pushes a frame onto this
    ;; vector per call and pops it in an unwind cleanup; four threads sharing
    ;; one drove the fill pointer to -4 (stage C).
    ("*MLAMBDA-CALL-STACK*" . ,(lambda () (make-array 30 :fill-pointer 0
                                                         :adjustable t))))
  "Specials a worker binds to a FRESH value rather than to a copy of the
   global one.  A thread-entry PROGV copies the parent's value by reference,
   so binding a mutable object that way hands every thread the same object:
   a hash table, an adjustable vector, anything mutated in place.  Lists are
   safe only because Maxima grows them with fresh conses on the thread's own
   binding.")

(defparameter +thread-copied-names+
  '("$VALUES" "$MYOPTIONS" "$FUNCTIONS" "$PROPS" "$ARRAYS" "$MACROS"
    "$RULES" "$DEPENDENCIES")
  "Specials a worker binds to a COPY of the global list (COPY-LIST), the
   third binding class.  These are the info lists doc 03 classed T3:
   ADD2LNC grows them with NCONC and MUNBIND-MAKUNBOUND shrinks $VALUES
   with DELETE, both destructive on the list's own conses.  A PROGV
   binding by reference would share exactly those conses, and every block
   entry in every thread splices them: wc_systematic's three locals are
   unbound between calls, so each MSET of one runs ADD2LNC on $VALUES and
   each MUNBIND runs DELETE.  At 6 tolerances the window was never hit; at
   10, every run with four or more threads corrupted the list.")

(defun thread-resolve (name)
  "The symbol NAME denotes, looked up in MAXIMA then COMMON-LISP."
  (or (find-symbol name :maxima) (find-symbol name :common-lisp)))

(defun thread-symbol-set (&optional extra)
  "The symbols a worker binds at entry: the T1 specials, plus EXTRA, which
   is the workload's own set from a recorded trace (see symbolset.lisp).

   Symbols that are currently unbound stay in the set.  Several of them,
   ANS among them, are written during the workload, and ANS is SETQ'd by
   Lisp code rather than through MSET, so the write hook never sees it and
   THREAD-GUARD cannot catch it.  Dropping them would leak those writes to
   the global cell in silence.  THREAD-WORKER binds them as unbound, which
   PROGV does for any symbol past the end of the value list."
  (remove-duplicates
   (append (remove nil (mapcar #'thread-resolve +thread-special-names+))
           extra)))

;;; ------------------------------------------------------------ the guard

(defvar *thread-bound* nil
  "Per worker: the symbols this thread may assign.  NIL outside a worker.")
(defvar *thread-tolerate* nil
  "Per worker: plist indicators this run tolerates, as an explicit list so
   the tolerance appears in the record instead of hiding in the code.")
(defvar *thread-violations* nil
  "Per worker: what the guard caught, newest first.")

(defvar *thread-writes* nil
  "Per worker, observe mode only: alist of ((op object indicator) . count).")

(defun thread-check (op obj ind)
  "NIL if this write is confined, else a (op object indicator) violation."
  (case op
    ((:assign :unbind)
     ;; An assignment to a symbol with no binding in this thread reaches the
     ;; global value cell, where every other thread sees it.
     (unless (and (symbolp obj) (gethash obj *thread-bound*))
       (list op obj ind)))
    (t
     ;; Property writes land on shared structure whatever is bound.
     (unless (member ind *thread-tolerate*)
       (list op (if (consp obj) :node obj) ind)))))

(defun thread-guard (op obj ind val)
  "Refuse a write this design cannot confine.  Installed as
   *ENVIRONMENT-WRITE-HOOK* inside a worker only."
  (declare (ignore val))
  (let ((v (thread-check op obj ind)))
    (when v
      (push v *thread-violations*)
      (if (member op '(:assign :unbind))
          (error "thread-guard: ~a of ~s is not confined to this thread: ~
                  the symbol was not bound at thread entry" op obj)
          (error "thread-guard: ~a of ~s on ~s writes shared structure"
                 op ind (second v))))))

(defun thread-observe (op obj ind val)
  "Record every write this worker makes, flagging what the guard would have
   refused, without stopping.  For the write trace under threads."
  (declare (ignore val))
  (let* ((key (list op (if (consp obj) :node obj) ind))
         (cell (assoc key *thread-writes* :test #'equal)))
    (if cell (incf (cdr cell)) (push (cons key 1) *thread-writes*)))
  (let ((v (thread-check op obj ind)))
    (when v (pushnew v *thread-violations* :test #'equal))))

;;; ----------------------------------------------------------- the runner

(defun thread-worker (k fn next results symbols tolerate guard
                      &optional observe)
  "One worker: bind the symbol set, then evaluate items until NEXT returns
   NIL.  GUARD NIL turns the check off, which is only for the negative
   control that shows what happens without confinement.  OBSERVE records
   every write instead of refusing any."
  (let* ((fresh (loop for (name . init) in +thread-fresh-bindings+
                      for s = (thread-resolve name)
                      when s collect (cons s init)))
         (copied-lists (loop for name in +thread-copied-names+
                             for s = (thread-resolve name)
                             when (and s (boundp s) (listp (symbol-value s)))
                               collect s))
         (copied (remove-if (lambda (s) (or (assoc s fresh)
                                            (member s copied-lists)))
                            symbols))
         (has-value (remove-if-not #'boundp copied))
         ;; PROGV binds every symbol in its first list, but only those with
         ;; a corresponding value get one; the rest are bound and unbound,
         ;; which is what a symbol that has no global value should start as.
         ;; Fresh-valued symbols go first, with a value each thread makes.
         (ordered (append (mapcar #'car fresh) copied-lists has-value
                          (remove-if #'boundp copied)))
         (values (append (mapcar (lambda (f) (funcall (cdr f))) fresh)
                         (mapcar (lambda (s) (copy-list (symbol-value s)))
                                 copied-lists)
                         (mapcar #'symbol-value has-value)))
         (bound (make-hash-table :test 'eq :size (* 2 (length symbols))))
         (t0 (pool-now)) (items 0))
    (dolist (s ordered) (setf (gethash s bound) t))
    (progv ordered values
      (let ((*thread-bound* bound)
            (*thread-tolerate* tolerate)
            (*thread-violations* '())
            (*thread-writes* '())
            (*environment-write-hook* (cond (observe #'thread-observe)
                                            (guard #'thread-guard)))
            ;; An error that escapes HANDLER-CASE -- one signalled inside an
            ;; unwind cleanup, say -- would otherwise put this thread into
            ;; the interactive debugger, reading *DEBUG-IO*, and the run
            ;; would hang.  Abort the thread instead; the parent sees a
            ;; missing worker record.
            (*debugger-hook* (lambda (c h)
                               (declare (ignore h))
                               (format *error-output*
                                       "~&thread-worker ~d: debugger ~
                                        reached: ~a~%" k c)
                               (sb-thread:abort-thread)))
            (sb-ext:*invoke-debugger-hook*
              (lambda (c h)
                (declare (ignore h))
                (format *error-output*
                        "~&thread-worker ~d: debugger reached: ~a~%" k c)
                (sb-thread:abort-thread))))
        (let ((backtrace nil))
          (handler-case
              (handler-bind ((error (lambda (e)
                                      (declare (ignore e))
                                      ;; Capture the stack where the error
                                      ;; was signalled, before HANDLER-CASE
                                      ;; unwinds it.
                                      (unless backtrace
                                        (setf backtrace
                                              (with-output-to-string (o)
                                                (sb-debug:print-backtrace
                                                 :stream o :count 40)))))))
                (loop for i = (funcall next)
                      while i
                      do (setf (aref results i) (pool-item fn i))
                         (incf items)))
            (error (e)
              (return-from thread-worker
                (list :id k :items items :error (princ-to-string e)
                      :backtrace backtrace
                      :violations *thread-violations*
                      :busy (pool-secs (- (pool-now) t0)))))))
        (list :id k :items items :error nil
              :violations *thread-violations*
              :writes (and observe (reverse *thread-writes*))
              :busy (pool-secs (- (pool-now) t0)))))))

(defvar *thread-join-timeout* 600
  "Seconds the parent waits for a worker before reporting it stuck.")

(defun thread-next-fn (k n p mode counter)
  "A closure yielding this worker's next item index, or NIL when done.
   :STATIC gives worker K the indices congruent to K mod P.  :DYNAMIC
   hands out indices in order through a shared counter advanced with
   SB-EXT:ATOMIC-INCF, the thread analogue of the process pool's token
   pipe."
  (ecase mode
    (:static (let ((i k))
               (lambda () (when (< i n) (prog1 i (incf i p))))))
    (:dynamic (lambda ()
                (let ((i (sb-ext:atomic-incf (car counter))))
                  (when (< i n) i))))))

(defun thread-run (fn n p &key (mode :static) (symbols nil) (tolerate nil)
                            (guard t) (warmup t) (observe nil)
                            (record-path nil) (label "threads") extra)
  "Evaluate items 0..N-1 of Maxima function FN over P threads.  Returns
   (values results workers wall ok).

   WARMUP evaluates item 0 once in this thread before any worker starts,
   so that autoload, cache population and other first-use writes happen
   once, single-threaded, outside the region; the workers then compute
   every item including item 0, and the warm-up's value is discarded."
  (when (and warmup (plusp n))
    (pool-item fn 0))
  (let* ((syms (or symbols (thread-symbol-set)))
         (results (make-array n :initial-element '%missing))
         (ready (sb-thread:make-semaphore :count 0))
         (start (sb-thread:make-semaphore :count 0))
         (counter (list 0))
         (threads (loop for k below p
                        collect (let ((k k))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (sb-thread:signal-semaphore ready)
                                     (sb-thread:wait-on-semaphore start)
                                     (thread-worker
                                      k fn (thread-next-fn k n p mode counter)
                                      results syms tolerate guard observe))
                                   :name (format nil "mx-~D" k))))))
    (dotimes (k p) (sb-thread:wait-on-semaphore ready))
    (let ((t0 (pool-now)))
      (sb-thread:signal-semaphore start p)
      (let* ((workers (mapcar (lambda (th)
                                (let ((w (sb-thread:join-thread
                                          th :default :aborted
                                             :timeout *thread-join-timeout*)))
                                  (if (eq w :aborted)
                                      (list :id (sb-thread:thread-name th)
                                            :items 0
                                            :error "worker aborted or timed out"
                                            :violations nil :busy 0d0)
                                      w)))
                              threads))
             (wall (pool-secs (- (pool-now) t0)))
             (errors (remove nil (mapcar (lambda (w) (getf w :error)) workers)))
             (missing (count '%missing results))
             (ok (and (null errors) (zerop missing))))
        (when record-path
          (pool-append-record
           record-path
           (append (list :label label :kind "threads" :workers p
                         :mode (string-downcase (symbol-name mode))
                         :items n :wall wall :ok ok
                         :symbols (length syms) :guard (and guard t)
                         :warmup (and warmup (plusp n) t)
                         :observe (and observe t)
                         :tolerated (mapcar #'princ-to-string tolerate)
                         :errors (mapcar #'princ-to-string errors)
                         :missing missing
                         :busy_max (reduce #'max
                                           (mapcar (lambda (w) (getf w :busy))
                                                   workers))
                         :maxrss (pool-maxrss))
                   extra)))
        (values results workers wall ok)))))
