;;; Run a Maxima workload on the thread pool and check it against the
;;; sequential result (add-threaded-prototype, stage C onward).
;;; Loads after pool.lisp and threads.lisp, with the workload loaded and
;;; set up (wc_setup).

(in-package :maxima)

(defun thread-wc-check (fn n p record-path
                        &key (mode :static) (label "wc-threads") extra
                             (tolerate nil) (guard t) (warmup t) (observe nil)
                             (extra-symbols '($wc_num $wc_tol $wc_tolnum)))
  "Evaluate FN over 0..N-1 sequentially, then on P threads, and compare
   element by element with ALIKE1.  Appends one record.  Returns
   (values correct first-mismatch)."
  (seq-run fn n record-path :label (format nil "~a-seq" label)
                            :item-times nil :extra extra)
  (let ((expected (coerce *pool-sequential-results* 'vector))
        (syms (thread-symbol-set extra-symbols)))
    (multiple-value-bind (results workers wall ok)
        (thread-run fn n p :mode mode :symbols syms :tolerate tolerate
                           :guard guard :warmup warmup :observe observe)
      (let* ((first-mismatch
               (loop for i below n
                     unless (alike1 (aref results i) (aref expected i))
                       return i))
             (correct (and ok (null first-mismatch)))
             (errors (remove nil (mapcar (lambda (w) (getf w :error))
                                         workers)))
             (violations (loop for w in workers
                               append (getf w :violations))))
        (pool-append-record
         record-path
         (append (list :label label :kind "wc-threads" :workers p
                       :mode (string-downcase (symbol-name mode))
                       :items n :wall wall :ok ok :correct correct
                       :first_mismatch first-mismatch
                       :errors (mapcar #'princ-to-string errors)
                       :violations (mapcar #'princ-to-string violations)
                       :symbols (length syms) :guard (and guard t)
                       :warmup (and warmup t)
                       :tolerated (mapcar #'princ-to-string tolerate)
                       :busy_max (reduce #'max (mapcar (lambda (w)
                                                         (getf w :busy))
                                                       workers))
                       :maxrss (pool-maxrss))
                 extra))
        (format *debug-io*
                "~&~a p=~d ~(~a~): ~,2F s, ~:[INCORRECT~;correct~]~
                 ~@[, first mismatch at ~d~]~@[, errors: ~a~]~%"
                label p mode wall correct first-mismatch
                (and errors (first errors)))
        (when observe
          ;; The write trace under threads: every distinct write, summed
          ;; over workers, with the per-worker counts so an uneven
          ;; distribution shows.  Flagged rows are what the guard would
          ;; have refused.
          (let ((total (make-hash-table :test 'equal))
                (flagged (remove-duplicates violations :test #'equal)))
            (dolist (w workers)
              (loop for (key . count) in (getf w :writes)
                    do (push (cons (getf w :id) count) (gethash key total))))
            (format *debug-io* "~&;; write trace under threads, p=~d: ~d ~
                                distinct writes, ~d flagged~%"
                    p (hash-table-count total) (length flagged))
            (loop for key being the hash-keys of total using (hash-value per)
                  do (format *debug-io* "  ~:[   ~;!! ~]~s ~s ~s  total ~d  ~
                                         per worker ~a~%"
                             (member key flagged :test #'equal)
                             (first key) (second key) (third key)
                             (reduce #'+ (mapcar #'cdr per))
                             (mapcar #'cdr (sort (copy-list per) #'<
                                                 :key #'car))))))
        (dolist (w workers)
          (when (getf w :backtrace)
            (format *debug-io* "~&;; backtrace, worker ~d (items done ~d):~%~a~%"
                    (getf w :id) (getf w :items) (getf w :backtrace))))
        (values correct first-mismatch)))))
