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

(defun pool-json-string (v)
  "V as a JSON string literal.  ~S escapes only the quote and the
   backslash; a newline inside an error message would split the record
   across lines, so control characters are escaped here."
  (with-output-to-string (o)
    (write-char #\" o)
    (loop for c across v
          do (case c
               (#\" (write-string "\\\"" o))
               (#\\ (write-string "\\\\" o))
               (#\Newline (write-string "\\n" o))
               (#\Tab (write-string "\\t" o))
               (#\Return (write-string "\\r" o))
               (t (if (< (char-code c) 32)
                      (format o "\\u~4,'0X" (char-code c))
                      (write-char c o)))))
    (write-char #\" o)))

(defun pool-json-value (v)
  (cond ((null v) "null")
        ((eq v t) "true")
        ((stringp v) (pool-json-string v))
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

(defun seq-run (fn n record-path &key (label "seq") (item-times t) extra)
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
       (append
        extra
        (list :kind "sequential" :label label :items n
             :wall wall
             :gc (- (pool-gc-secs) gc0)
             :bytes_consed (- (sb-ext:get-bytes-consed) bytes0)
             :maxrss (pool-maxrss)
             :item_times (and item-times (nreverse times)))))
      wall)))

;;; ------------------------------------------------------------ results I/O

(defun pool-print-result (index value stream)
  "Write (INDEX . VALUE) as a re-readable form (design D3)."
  (with-standard-io-syntax
    (let ((*package* (find-package :maxima))
          (*read-default-float-format* 'double-float))
      (prin1 (cons index value) stream)
      (terpri stream))))

(defun pool-read-forms (path)
  (with-open-file (s path)
    (with-standard-io-syntax
      (let ((*package* (find-package :maxima))
            (*read-default-float-format* 'double-float))
        (loop for form = (read s nil s)
              until (eq form s)
              collect form)))))

(defun seq-save-results (path)
  "Save *POOL-SEQUENTIAL-RESULTS* for later correctness checks."
  (with-open-file (s path :direction :output :if-exists :supersede)
    (loop for v in *pool-sequential-results*
          for i from 0
          do (pool-print-result i v s))))

(defun seq-load-results (path)
  (let* ((forms (pool-read-forms path))
         (v (make-array (length forms))))
    (dolist (f forms) (setf (aref v (car f)) (cdr f)))
    (coerce v 'list)))

;;; ------------------------------------------------------------ token pipe

(defconstant +pool-token-bytes+ 4)
(defconstant +pool-tokens-per-write+ 64)  ; 256 bytes <= PIPE_BUF (512)

(defun pool-write-tokens (fd n)
  "Write indices 0..N-1 as little-endian 4-byte tokens.  Each write is at
most PIPE_BUF bytes, so the pipe always holds whole tokens."
  (let ((buf (make-array (* +pool-token-bytes+ +pool-tokens-per-write+)
                         :element-type '(unsigned-byte 8))))
    (loop for start from 0 below n by +pool-tokens-per-write+
          do (let ((k (min +pool-tokens-per-write+ (- n start))))
               (dotimes (j k)
                 (let ((i (+ start j)) (o (* j +pool-token-bytes+)))
                   (setf (aref buf o) (ldb (byte 8 0) i)
                         (aref buf (+ o 1)) (ldb (byte 8 8) i)
                         (aref buf (+ o 2)) (ldb (byte 8 16) i)
                         (aref buf (+ o 3)) (ldb (byte 8 24) i))))
               (let ((len (* k +pool-token-bytes+)))
                 (multiple-value-bind (written err)
                     (sb-unix:unix-write fd buf 0 len)
                   (unless (eql written len)
                     (error "token write failed: ~A ~A" written err))))))))

(defun pool-read-token (fd buf)
  "Next index from the token pipe, or NIL at end of file."
  (multiple-value-bind (got err)
      (sb-sys:with-pinned-objects (buf)
        (sb-unix:unix-read fd (sb-sys:vector-sap buf) +pool-token-bytes+))
    (cond ((eql got 0) nil)
          ((eql got +pool-token-bytes+)
           (logior (aref buf 0) (ash (aref buf 1) 8)
                   (ash (aref buf 2) 16) (ash (aref buf 3) 24)))
          (t (error "token read returned ~A (~A)" got err)))))

;;; ------------------------------------------------------------ worker

(defun pool-worker (k fn next-index out-path fault)
  "Run in a forked child: evaluate items until NEXT-INDEX returns NIL, write
results and a summary to OUT-PATH, then exit without unwinding."
  (let ((code 0))
    (unwind-protect
         (handler-case
             (let ((gc0 (pool-gc-secs))
                   (heap0 (sb-kernel:dynamic-usage))
                   (items 0) (first nil) (last nil) (write-secs 0d0))
               (with-open-file (s out-path :direction :output
                                           :if-exists :supersede)
                 (loop for i = (funcall next-index)
                       while i
                       do (let* ((t0 (pool-now))
                                 (v (if (eql i fault) 42 (pool-item fn i))))
                            (unless first (setq first t0))
                            (let ((w0 (pool-now)))
                              (pool-print-result i v s)
                              (incf write-secs (pool-secs (- (pool-now) w0))))
                            (setq last (pool-now))
                            (incf items)))
                 (pool-print-result
                  -1 (list :worker k :items items
                           :busy (if first (pool-secs (- last first)) 0d0)
                           :gc (- (pool-gc-secs) gc0)
                           :maxrss (pool-maxrss)
                           :heap_growth (- (sb-kernel:dynamic-usage) heap0)
                           :write write-secs)
                  s)
                 (finish-output s)))
           (error (e)
             (setq code 3)
             (ignore-errors
              (with-open-file (s (concatenate 'string out-path ".err")
                                 :direction :output :if-exists :supersede)
                (format s "~A~%" e)))))
      (sb-ext:exit :code code :abort t))))

;;; ------------------------------------------------------------ parent

(defvar *pool-run-counter* 0)

(defun pool-run (fn n p record-path
                 &key (mode :dynamic) (label "") expected fault
                      (tmp-dir "/tmp/") extra)
  "Fork P workers over items 0..N-1 of Maxima function FN.  MODE is :DYNAMIC
(shared token pipe) or :STATIC (worker k takes indices = k mod P).
EXPECTED, if given, is the list of sequential results to check against.
FAULT, if given, is an index for which the worker returns a wrong value
(for testing the check).  Appends a JSON record; returns (values correct
first-mismatch)."
  (let ((nthreads (length (sb-thread:list-all-threads))))
    (unless (= nthreads 1)
      (error "pool-run: image runs ~D threads; fork needs exactly one"
             nthreads)))
  (let* ((run (format nil "~Apool-~D-~D" tmp-dir (sb-posix:getpid)
                      (incf *pool-run-counter*)))
         (paths (loop for k below p
                      collect (format nil "~A-w~D.out" run k)))
         (pids '())
         (t0 (pool-now))
         token-r token-w t-forked t-waited)
    (when (eq mode :dynamic)
      (multiple-value-setq (token-r token-w) (sb-posix:pipe)))
    (finish-output *standard-output*)
    (dotimes (k p)
      (let ((pid (sb-posix:fork)))
        (when (zerop pid)
          ;; Child.
          (let ((next
                  (if (eq mode :dynamic)
                      (let ((buf (make-array +pool-token-bytes+
                                             :element-type '(unsigned-byte 8))))
                        (sb-posix:close token-w)
                        (lambda () (pool-read-token token-r buf)))
                      (let ((i k))
                        (lambda ()
                          (when (< i n) (prog1 i (incf i p))))))))
            (pool-worker k fn next (nth k paths) fault)))
        (push pid pids)))
    (setq t-forked (pool-now))
    (when (eq mode :dynamic)
      (sb-posix:close token-r)
      (pool-write-tokens token-w n)
      (sb-posix:close token-w))
    (let ((bad-exits 0))
      (dolist (pid pids)
        (multiple-value-bind (wpid status) (sb-posix:waitpid pid 0)
          (declare (ignore wpid))
          (unless (and (sb-posix:wifexited status)
                       (zerop (sb-posix:wexitstatus status)))
            (incf bad-exits))))
      (setq t-waited (pool-now))
      (let ((results (make-array n :initial-element '%missing))
            (workers '()))
        (dolist (path paths)
          (when (probe-file path)
            (dolist (form (pool-read-forms path))
              (if (eql (car form) -1)
                  (push (cdr form) workers)
                  (setf (aref results (car form)) (cdr form))))
            (delete-file path)))
        (let* ((t-read (pool-now))
               (missing (count '%missing results))
               (mismatch
                 (cond ((plusp missing) (position '%missing results))
                       (expected
                        (loop for i from 0
                              for e in expected
                              unless (alike1 e (aref results i))
                                return i))))
               (correct (and (zerop bad-exits) (zerop missing)
                             (null mismatch))))
          (pool-append-record
           record-path
           (append
            extra
            (list :kind "pool" :label label :mode (string-downcase mode)
                 :workers p :items n
                 :wall (pool-secs (- t-read t0))
                 :t_fork (pool-secs (- t-forked t0))
                 :t_wait (pool-secs (- t-waited t-forked))
                 :t_read (pool-secs (- t-read t-waited))
                 :correct correct :checked (and expected t)
                 :first_mismatch mismatch :missing missing
                 :bad_exits bad-exits
                 :parent_maxrss (pool-maxrss)
                 :worker_stats (reverse workers))))
          (values correct mismatch))))))
