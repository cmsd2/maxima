;;; Process-pool benchmark (add-process-pool-benchmark).
;;;
;;; SEQ-RUN evaluates a Maxima item function over 0..N-1 in this process.
;;; POOL-RUN forks P workers from this image and spreads the same items over
;;; them (design D1-D4).  Both append one JSON record per run to a file.

(in-package :maxima)
(require :sb-posix)

;;; ------------------------------------------------------------ utilities

(defun pool-now () (get-internal-real-time))
(defun pool-secs (ticks) (/ ticks (float internal-time-units-per-second 1d0)))

(defun pool-json-value (v)
  (cond ((null v) "null")
        ((eq v t) "true")
        ((stringp v) (format nil "~S" v))
        ((integerp v) (format nil "~D" v))
        ((realp v) (format nil "~,6F" v))
        ((and (consp v) (keywordp (car v)))
         (pool-json-object v))
        ((listp v) (format nil "[~{~A~^,~}]" (mapcar #'pool-json-value v)))
        (t (format nil "~S" (princ-to-string v)))))

(defun pool-json-object (plist)
  (format nil "{~{~A~^,~}}"
          (loop for (k v) on plist by #'cddr
                collect (format nil "~S:~A" (string-downcase (symbol-name k))
                                (pool-json-value v)))))

(defun pool-append-record (path plist)
  (with-open-file (s path :direction :output :if-exists :append
                          :if-does-not-exist :create)
    (write-line (pool-json-object plist) s)))

(defun pool-maxrss ()
  "Peak resident set size of this process, in bytes (macOS reports bytes)."
  (multiple-value-bind (ok utime stime maxrss)
      (sb-unix:unix-getrusage sb-unix:rusage_self)
    (declare (ignore utime stime))
    (if ok maxrss 0)))

(defun pool-gc-secs () (pool-secs sb-ext:*gc-run-time*))

(defun pool-item (fn i)
  "Evaluate the Maxima function FN on index I."
  (mfuncall fn i))

;;; ------------------------------------------------------------ sequential

(defvar *pool-sequential-results* nil
  "Results of the last SEQ-RUN, in index order, for correctness checks.")

(defun seq-run (fn n record-path &key (label "seq") (item-times t))
  (let* ((gc0 (pool-gc-secs))
         (bytes0 (sb-ext:get-bytes-consed))
         (times '())
         (results (make-array n))
         (t0 (pool-now)))
    (dotimes (i n)
      (let ((s (pool-now)))
        (setf (aref results i) (pool-item fn i))
        (push (pool-secs (- (pool-now) s)) times)))
    (let ((wall (pool-secs (- (pool-now) t0))))
      (setq *pool-sequential-results* (coerce results 'list))
      (pool-append-record
       record-path
       (list :kind "sequential" :label label :items n
             :wall wall
             :gc (- (pool-gc-secs) gc0)
             :bytes_consed (- (sb-ext:get-bytes-consed) bytes0)
             :maxrss (pool-maxrss)
             :item_times (and item-times (nreverse times))))
      wall)))
