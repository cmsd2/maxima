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
    "BINDLIST" "MSPECLIST")
  "Specials the earlier change classified T1: confined by a binding at
   thread entry.  Names, not symbols, because a few live in COMMON-LISP and
   the rest in MAXIMA; see research/multithreading/oracle-churn.tsv.")

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

(defun thread-guard (op obj ind val)
  "Refuse a write this design cannot confine.  Installed as
   *ENVIRONMENT-WRITE-HOOK* inside a worker only."
  (declare (ignore val))
  (case op
    ((:assign :unbind)
     ;; An assignment to a symbol with no binding in this thread reaches the
     ;; global value cell, where every other thread sees it.
     (unless (and (symbolp obj) (gethash obj *thread-bound*))
       (push (list op obj ind) *thread-violations*)
       (error "thread-guard: ~a of ~s is not confined to this thread: ~
               the symbol was not bound at thread entry" op obj)))
    (t
     ;; Property writes land on shared structure whatever is bound.
     (unless (member ind *thread-tolerate*)
       (push (list op (if (consp obj) :node obj) ind) *thread-violations*)
       (error "thread-guard: ~a of ~s on ~s writes shared structure"
              op ind (if (consp obj) :node obj))))))

;;; ----------------------------------------------------------- the runner

(defun thread-worker (k fn indices results symbols tolerate guard)
  "One worker: bind the symbol set, then evaluate its items.  GUARD NIL
   turns the check off, which is only for the negative control that shows
   what happens without confinement."
  (let* ((has-value (remove-if-not #'boundp symbols))
         ;; PROGV binds every symbol in its first list, but only those with
         ;; a corresponding value get one; the rest are bound and unbound,
         ;; which is what a symbol that has no global value should start as.
         (ordered (append has-value (remove-if #'boundp symbols)))
         (values (mapcar #'symbol-value has-value))
         (bound (make-hash-table :test 'eq :size (* 2 (length symbols))))
         (t0 (pool-now)) (items 0))
    (dolist (s symbols) (setf (gethash s bound) t))
    (progv ordered values
      (let ((*thread-bound* bound)
            (*thread-tolerate* tolerate)
            (*thread-violations* '())
            (*environment-write-hook* (and guard #'thread-guard)))
        (handler-case
            (dolist (i indices)
              (setf (aref results i) (pool-item fn i))
              (incf items))
          (error (e)
            (return-from thread-worker
              (list :id k :items items :error (princ-to-string e)
                    :violations *thread-violations*
                    :busy (pool-secs (- (pool-now) t0))))))
        (list :id k :items items :error nil
              :violations *thread-violations*
              :busy (pool-secs (- (pool-now) t0)))))))

(defun thread-indices (k n p mode)
  (ecase mode
    (:static (loop for i from k below n by p collect i))
    (:block (let* ((per (ceiling n p)) (lo (* k per)))
              (loop for i from lo below (min n (+ lo per)) collect i)))))

(defun thread-run (fn n p &key (mode :static) (symbols nil) (tolerate nil)
                            (guard t) (record-path nil) (label "threads")
                            extra)
  "Evaluate items 0..N-1 of Maxima function FN over P threads.  Returns
   (values results workers wall ok)."
  (let* ((syms (or symbols (thread-symbol-set)))
         (results (make-array n :initial-element '%missing))
         (ready (sb-thread:make-semaphore :count 0))
         (start (sb-thread:make-semaphore :count 0))
         (threads (loop for k below p
                        collect (let ((k k))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (sb-thread:signal-semaphore ready)
                                     (sb-thread:wait-on-semaphore start)
                                     (thread-worker k fn
                                                    (thread-indices k n p mode)
                                                    results syms tolerate
                                                    guard))
                                   :name (format nil "mx-~D" k))))))
    (dotimes (k p) (sb-thread:wait-on-semaphore ready))
    (let ((t0 (pool-now)))
      (sb-thread:signal-semaphore start p)
      (let* ((workers (mapcar #'sb-thread:join-thread threads))
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
                         :tolerated (mapcar #'princ-to-string tolerate)
                         :errors (mapcar #'princ-to-string errors)
                         :missing missing
                         :busy_max (reduce #'max
                                           (mapcar (lambda (w) (getf w :busy))
                                                   workers))
                         :maxrss (pool-maxrss))
                   extra)))
        (values results workers wall ok)))))
