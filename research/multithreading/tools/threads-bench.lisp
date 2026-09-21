;;; Thread arm for the stage D sweep (add-threaded-prototype).  Same record
;;; shape as POOL-RUN's, so one report can read both.
;;; Loads after pool.lisp and threads.lisp.

(in-package :maxima)

(defun thread-bench (fn n p record-path
                     &key (mode :static) (label "") expected (guard t) extra
                          (extra-symbols '($wc_num $wc_tol $wc_tolnum)))
  "Evaluate items 0..N-1 of Maxima function FN on P threads and check
   against EXPECTED, the sequential results.  Appends a JSON record.
   Returns (values correct first-mismatch)."
  (let ((syms (thread-symbol-set extra-symbols)))
    (multiple-value-bind (results workers wall ok)
        (thread-run fn n p :mode mode :symbols syms :guard guard :warmup t)
      (let* ((expected (and expected (coerce expected 'vector)))
             (mismatch (and expected
                            (loop for i below n
                                  unless (alike1 (aref results i)
                                                 (aref expected i))
                                    return i)))
             (missing (count '%missing results))
             (correct (and ok (null mismatch) (zerop missing)))
             (errors (remove nil (mapcar (lambda (w) (getf w :error))
                                         workers))))
        (pool-append-record
         record-path
         (append
          extra
          (list :kind "threads" :label label
                :mode (string-downcase (symbol-name mode))
                :workers p :items n
                :wall wall
                :correct correct :checked (and expected t)
                :first_mismatch mismatch :missing missing
                :guard (and guard t) :symbols (length syms)
                :errors (mapcar #'princ-to-string errors)
                ;; A failed worker's backtrace, so the record explains itself.
                :backtraces (remove nil (mapcar (lambda (w) (getf w :backtrace))
                                                workers))
                :violations (loop for w in workers
                                  append (mapcar #'princ-to-string
                                                 (getf w :violations)))
                :gc (pool-gc-secs)
                :parent_maxrss (pool-maxrss)
                :worker_stats (mapcar (lambda (w)
                                        (list :worker (getf w :id)
                                              :items (getf w :items)
                                              :busy (getf w :busy)))
                                      workers))))
        (values correct mismatch)))))
