;;; Symbol set for thread-entry binding (add-threaded-prototype, task 1.1).
;;;
;;; A worker thread must enter with every symbol it will assign already
;;; bound, so that MSET's (SETF (SYMBOL-VALUE X) Y) writes the thread's
;;; binding instead of the global value cell.  This collects that set from a
;;; fresh trace of the workload rather than from the stored one.
;;;
;;; Two sources, because one is not enough:
;;;   - the environment-write hook sees every MSET assignment and unbind;
;;;   - it does NOT see a Lisp special SETQ'd outside MSET (ANS,
;;;     *LAST-MEVAL1-FORM*, VARLIST, ...).  Those were found by the oracle's
;;;     snapshot diff in the earlier change and are listed in
;;;     research/multithreading/oracle-churn.tsv under the T1 categories.
;;;
;;; Loads after pool.lisp.

(in-package :maxima)

(defvar *symbolset-log* nil)

(defun symbolset-trace (fn n)
  "Run items 0..N-1 of Maxima function FN with the write hook recording.
   Returns two lists: symbols assigned or unbound, and symbols whose plist
   was written (which thread-entry binding does NOT confine)."
  (let ((assigned (make-hash-table :test 'eq))
        (plists (make-hash-table :test 'eq)))
    (let ((*environment-write-hook*
            (lambda (op obj ind val)
              (declare (ignore val))
              (when (symbolp obj)
                (case op
                  ((:assign :unbind) (setf (gethash obj assigned) t))
                  (t (push ind (gethash obj plists))))))))
      (dotimes (i n) (pool-item fn i)))
    (values (sort (loop for k being the hash-keys of assigned collect k)
                  #'string< :key #'symbol-name)
            (sort (loop for k being the hash-keys of plists collect k)
                  #'string< :key #'symbol-name)
            plists)))

(defun symbolset-report (fn n &key (skip 1))
  "Trace FN over N items and print the symbol set.  SKIP items run first and
   are not recorded: their writes are the warm-up's (autoload, caches), which
   the runner absorbs outside the parallel region."
  (dotimes (i skip) (pool-item fn i))
  (multiple-value-bind (assigned plists table) (symbolset-trace fn n)
    (format *debug-io* "~&;; assigned or unbound (~d), confined by ~
                        thread-entry binding:~%" (length assigned))
    (dolist (s assigned) (format *debug-io* "  ~s~%" s))
    (format *debug-io* "~&;; plist writes (~d), NOT confined by binding:~%"
            (length plists))
    (dolist (s plists)
      (format *debug-io* "  ~s ~s~%" s
              (remove-duplicates (gethash s table))))
    (values assigned plists)))
