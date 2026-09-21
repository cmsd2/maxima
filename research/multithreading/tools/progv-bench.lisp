;;; Binding cost spike (add-thread-feasibility-spikes, spike B).
;;;
;;; A threaded Maxima cannot keep MBIND's mechanism: it assigns the symbol's
;;; value cell globally, so one thread's block variable would be every
;;; thread's.  PROGV binds dynamically instead, which is per thread in SBCL.
;;; This measures what that substitution costs.
;;;
;;; Four arms, all binding the same symbols to the same values and running
;;; the same body:
;;;
;;;   :mbind       MBIND then MUNBIND -- what Maxima pays today, wrapper and
;;;                all (handler-case, with-$error, unwind-protect)
;;;   :mbind-doit  the binding loop alone, without MBIND's error wrapper
;;;   :progv       the replacement
;;;   :raw         save the value cell, SETF it, restore it -- no MSET
;;;                checks, no BINDLIST.  The floor for a per-thread binding
;;;                stack, which is the fallback if PROGV is too slow.
;;;
;;; Loads after pool.lisp, whose timing and JSON helpers it reuses.

(in-package :maxima)

(defvar *pv-symbols* (make-hash-table)
  "Cache of the symbol lists used for each variable count.")

(defun pv-symbols (n)
  "N symbols that look like Maxima block variables, bound and special.
   They are made once per count and reused: interning fresh symbols inside
   the timed loop would measure the reader, not the binding."
  (or (gethash n *pv-symbols*)
      (setf (gethash n *pv-symbols*)
            (loop for i below n
                  collect (let ((s (intern (format nil "$PVBENCH~D" i)
                                           :maxima)))
                            (proclaim `(special ,s))
                            (setf (symbol-value s) 0)
                            s)))))

(defun pv-body (vars)
  "Read every bound variable, so the binding cannot be optimised away."
  (let ((acc 0))
    (declare (type fixnum acc))
    (dolist (v vars acc)
      (let ((x (symbol-value v)))
        (when (typep x 'fixnum)
          (setf acc (logand (+ acc (the fixnum x)) most-positive-fixnum)))))))

(defun pv-once (arm vars vals)
  "One bind, body, unbind cycle.  Returns the body's value."
  (ecase arm
    (:progv (progv vars vals (pv-body vars)))
    (:mbind (mbind vars vals nil)
            (prog1 (pv-body vars) (munbind vars)))
    (:mbind-doit (mbind-doit vars vals nil)
                 (prog1 (pv-body vars) (munbind vars)))
    (:raw (let ((old (mapcar #'symbol-value vars)))
            (loop for v in vars for x in vals
                  do (setf (symbol-value v) x))
            (prog1 (pv-body vars)
              (loop for v in vars for x in old
                    do (setf (symbol-value v) x)))))))

(defun pv-measure (arm nvars iterations)
  "Time ITERATIONS bind-body-unbind cycles.  Returns a plist."
  (let* ((vars (pv-symbols nvars))
         (vals (loop for i below nvars collect (1+ i)))
         (sum 0))
    (declare (type fixnum sum))
    ;; One unmeasured cycle, so the first call's compilation and the first
    ;; touch of the value cells land outside the timing.
    (pv-once arm vars vals)
    (let ((b0 (sb-ext:get-bytes-consed))
          (t0 (pool-now)))
      (dotimes (i iterations)
        (setf sum (logand (+ sum (pv-once arm vars vals))
                          most-positive-fixnum)))
      (let* ((wall (pool-secs (- (pool-now) t0)))
             (bytes (- (sb-ext:get-bytes-consed) b0)))
        (list :arm (string-downcase (symbol-name arm))
              :nvars nvars :iterations iterations
              :wall wall :checksum sum
              ;; Every cycle binds NVARS variables, so per-binding cost is
              ;; the cycle cost divided by the variable count.
              :ns_per_call (/ (* wall 1d9) iterations)
              :ns_per_binding (/ (* wall 1d9) iterations nvars)
              :bytes_per_call (/ bytes (float iterations 1d0))
              :bytes_per_binding (/ bytes (float (* iterations nvars) 1d0)))))))

(defun pv-expected-checksum (nvars iterations)
  "What PV-MEASURE must return: every arm binds the same values."
  (logand (* iterations (/ (* nvars (1+ nvars)) 2)) most-positive-fixnum))

(defun pv-read-cost (iterations &key (reads 100))
  "Cost of READING a special variable, globally bound against bound by
   PROGV.  Binding is not the only cost a substitution could add: if
   thread-local bindings made every read dearer, the evaluator would pay it
   everywhere.  SBCL reads a special through its thread-local slot first
   whether or not anything bound it, so the two should agree."
  (let* ((v (first (pv-symbols 1)))
         (vars (list v)) (vals (list 7)))
    (labels ((spin ()
               (let ((acc 0))
                 (declare (type fixnum acc))
                 (dotimes (i reads acc)
                   (let ((x (symbol-value v)))
                     (when (typep x 'fixnum)
                       (setf acc (logand (+ acc (the fixnum x))
                                         most-positive-fixnum)))))))
             (spin-many ()
               (let ((acc 0))
                 (declare (type fixnum acc))
                 (dotimes (i iterations acc)
                   (setf acc (logand (+ acc (spin)) most-positive-fixnum))))))
      (setf (symbol-value v) 7)
      (spin-many)
      (let* ((t0 (pool-now))
             (global (spin-many))
             (t1 (pool-now))
             (bound (progv vars vals (spin-many)))
             (t2 (pool-now)))
        (list :global_ns (/ (* (pool-secs (- t1 t0)) 1d9)
                            (* iterations reads))
              :progv_ns (/ (* (pool-secs (- t2 t1)) 1d9)
                           (* iterations reads))
              ;; Both sums must be ITERATIONS * READS * 7: if a read went
              ;; somewhere other than the value we bound, this catches it.
              :global_sum global :progv_sum bound
              :reads (* iterations reads))))))

(defun pv-bench (record-path &key (nvars '(1 2 5 10)) (iterations 200000)
                                  (arms '(:mbind :mbind-doit :progv :raw))
                                  (label "progv") extra)
  "Run every arm at every variable count and append one JSON record each."
  (dolist (n nvars)
    (dolist (arm arms)
      (let* ((r (pv-measure arm n iterations))
             (want (pv-expected-checksum n iterations))
             (ok (eql (getf r :checksum) want)))
        (pool-append-record record-path
                            (append (list :label label :ok ok :expected want)
                                    r extra))
        (format *debug-io* "~&~a n=~2d ~11a ~8,1F ns/call ~7,1F ns/binding ~
                            ~6,1F B/call  checksum ~:[MISMATCH~;ok~]~%"
                label n (getf r :arm) (getf r :ns_per_call)
                (getf r :ns_per_binding) (getf r :bytes_per_call) ok))))
  (let* ((r (pv-read-cost (max (floor iterations 20) 1)))
         (want (* (getf r :reads) 7))
         (ok (and (eql (getf r :global_sum) want)
                  (eql (getf r :progv_sum) (* (getf r :reads) 7)))))
    (pool-append-record record-path
                        (append (list :label label :kind "read-cost" :ok ok
                                      :arm "read" :nvars 1)
                                r extra))
    (format *debug-io* "~&~a read cost: global ~,2F ns, progv-bound ~,2F ns, ~
                        sums ~:[MISMATCH~;ok~]~%"
            label (getf r :global_ns) (getf r :progv_ns) ok))
  (values))
