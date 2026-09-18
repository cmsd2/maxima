;;; Snapshot-diff oracle for environment writes (design D9).
;;;
;;; A snapshot maps each (OBJECT . INDICATOR) slot of the environment to
;;; (VALUE . DEEP-HASH):
;;;
;;;   - every symbol accessible in the MAXIMA package: each plist entry,
;;;     plus :VALUE for its value cell when bound;
;;;   - the gensyms in GENVAR (CRE variables);
;;;   - the non-symbol fact-database nodes in DOBJECTS and *NOBJECTS*,
;;;     whose plist is their CDR;
;;;   - the current context, if it is an uninterned (temporary) symbol.
;;;
;;; Comparing two snapshots gives, per slot, one of:
;;;
;;;   :ADDED     slot present only after
;;;   :REMOVED   slot present only before
;;;   :REPLACED  slot holds a different (non-EQ) value
;;;   :MUTATED   same EQ value, but its deep hash changed: in-place mutation
;;;   :APPEARED  a whole object joined the tracked set (new symbol, or a node
;;;              linked into DOBJECTS/*NOBJECTS*)
;;;   :VANISHED  a whole object left the tracked set
;;;
;;; The recording hook logs every observed write.  A difference is
;;; EXPLAINED when the log has a matching write: :PUT/:REMOVE on the same
;;; object and indicator, :REPLACE-PLIST on the object, or :ASSIGN/:UNBIND
;;; for a :VALUE slot.  :MUTATED is never explained by the hook, which by
;;; design sees slot writes only.
;;;
;;; Per-problem mode wraps MEVAL* while TEST-BATCH runs: one snapshot after
;;; each top-level evaluation, diffed against the previous one.  Each diff
;;; therefore covers the previous problem's result check plus this problem's
;;; input.  Output is TSV, one line per unexplained difference.

(in-package :maxima)

;;; ------------------------------------------------------------ hashing

(defvar *oracle-ids* (make-hash-table :test 'eq :weakness :key)
  "Identity tokens for objects hashed by identity (functions, structures,
streams, hash tables).")
(defvar *oracle-next-id* 0)

(defun oracle-identity (x)
  (or (gethash x *oracle-ids*)
      (setf (gethash x *oracle-ids*) (incf *oracle-next-id*))))

(declaim (inline oracle-mix))
(defun oracle-mix (h x)
  (logand (+ (* h 31) x 7) most-positive-fixnum))

(defun oracle-hash (x visited)
  "Deep structural hash of X.  Conses and arrays are walked; VISITED
guards against cycles (the fact database contains cyclic lists)."
  (cond ((consp x)
         (if (gethash x visited)
             17
             (let ((h 1))
               (loop for tail = x then (cdr tail)
                     while (consp tail)
                     do (when (gethash tail visited) (return))
                        (setf (gethash tail visited) t)
                        (setq h (oracle-mix h (oracle-hash (car tail) visited)))
                     finally (unless (null tail)
                               (setq h (oracle-mix h (oracle-hash tail visited)))))
               h)))
        ((symbolp x) (sxhash x))
        ((or (numberp x) (characterp x) (stringp x)
             (bit-vector-p x) (pathnamep x))
         (sxhash x))
        ((arrayp x)
         (if (gethash x visited)
             19
             (progn
               (setf (gethash x visited) t)
               (let ((h (sxhash (array-dimensions x))))
                 (dotimes (i (array-total-size x) h)
                   (setq h (oracle-mix h (oracle-hash (row-major-aref x i)
                                                      visited))))))))
        (t (oracle-identity x))))

;;; ------------------------------------------------------------ snapshots

(defun oracle-record-slot (table obj ind val)
  (push (list* ind val (oracle-hash val (make-hash-table :test 'eq)))
        (gethash obj table)))

(defun oracle-record-plist (table obj plist)
  (loop for (ind val) on plist by #'cddr
        do (oracle-record-slot table obj ind val)))

(defvar *oracle-skip-value-symbols*
  '(*oracle-ids* *oracle-next-id* *oracle-log* *oracle-writes* *oracle-out*
    *oracle-file* *oracle-problem* *oracle-snapshot* *oracle-depth*
    *oracle-stats* *oracle-skip-value-symbols*)
  "Symbols whose value cell is not snapshotted: the oracle's own state.
Benign churn is classified after the fact, not skipped here, so that the
raw report stays complete.")

(defun oracle-snapshot ()
  (let ((table (make-hash-table :test 'eq)))
    (do-symbols (s :maxima)
      (unless (gethash s table)
        (let ((pl (symbol-plist s)))
          (when pl (oracle-record-plist table s pl)))
        (when (and (boundp s)
                   (not (constantp s))
                   (not (member s *oracle-skip-value-symbols*)))
          (oracle-record-slot table s :value (symbol-value s)))
        (unless (gethash s table)
          (setf (gethash s table) '()))))
    (dolist (g (and (boundp 'genvar) (symbol-value 'genvar)))
      (when (and (symbolp g) (not (gethash g table)))
        (oracle-record-plist table g (symbol-plist g))
        (when (boundp g) (oracle-record-slot table g :value (symbol-value g)))))
    (dolist (lst (list (and (boundp 'dobjects) (symbol-value 'dobjects))
                       (and (boundp '*nobjects*) (symbol-value '*nobjects*))))
      (dolist (node lst)
        (when (and (consp node) (not (gethash node table)))
          (oracle-record-plist table node (cdr node)))))
    (let ((c (and (boundp 'context) (symbol-value 'context))))
      (when (and (symbolp c) c (null (symbol-package c)) (not (gethash c table)))
        (oracle-record-plist table c (symbol-plist c))))
    table))

(defun oracle-diff (before after)
  "List of (KIND OBJECT INDICATOR) for every slot that differs."
  (let ((diffs '()))
    (flet ((slots (table obj) (gethash obj table)))
      (maphash
       (lambda (obj new-slots)
         (let ((old-slots (slots before obj)))
           ;; An object new to the tracked set (a fresh symbol, or a node
           ;; just linked into DOBJECTS/*NOBJECTS*) is one :APPEARED record,
           ;; not a slot write per property.
           (when (and new-slots (not (nth-value 1 (gethash obj before))))
             (push (list :appeared obj nil) diffs)
             (setq new-slots nil))
           (dolist (ns new-slots)
             (let ((os (assoc (car ns) old-slots :test #'eq)))
               (cond ((null os) (push (list :added obj (car ns)) diffs))
                     ((not (eq (cadr os) (cadr ns)))
                      (unless (= (cddr os) (cddr ns))
                        (push (list :replaced obj (car ns)) diffs)))
                     ((/= (cddr os) (cddr ns))
                      (push (list :mutated obj (car ns)) diffs)))))
           (dolist (os old-slots)
             (unless (assoc (car os) new-slots :test #'eq)
               (push (list :removed obj (car os)) diffs)))))
       after)
      (maphash (lambda (obj old-slots)
                 (unless (nth-value 1 (gethash obj after))
                   (when old-slots
                     (push (list :vanished obj nil) diffs))))
               before))
    diffs))

;;; ------------------------------------------------------------ hook log

(defvar *oracle-log* (make-hash-table :test 'eq)
  "OBJECT -> list of observed indicators (:ANY for plist replacement,
:VALUE for assignment).  Keyed by EQ identity: fact-database nodes are
conses whose contents change, so EQUAL keys would not be found again.")
(defvar *oracle-writes* 0)

(defun oracle-hook (op obj ind val)
  (declare (ignore val))
  (incf *oracle-writes*)
  (pushnew (case op
             ((:put :remove) ind)
             (:replace-plist :any)
             ((:assign :unbind) :value))
           (gethash obj *oracle-log*)))

(defun oracle-explained-p (d)
  (destructuring-bind (kind obj ind) d
    (and (not (member kind '(:mutated :appeared :vanished)))
         (let ((seen (gethash obj *oracle-log*)))
           (or (member ind seen) (member :any seen))))))

;;; ------------------------------------------------------------ reporting

(defvar *oracle-out* nil)
(defvar *oracle-file* "?")
(defvar *oracle-problem* 0)
(defvar *oracle-snapshot* nil)
(defvar *oracle-depth* 0)
(defvar *oracle-stats* (list :problems 0 :diffs 0 :unexplained 0 :writes 0))

(defun oracle-object-kind (obj)
  (cond ((consp obj) "node")
        ((null (symbol-package obj)) "gensym")
        (t "symbol")))

(defun oracle-object-name (obj)
  (let ((s (with-standard-io-syntax
             (let ((*package* (find-package :maxima))
                   (*print-readably* nil))
               (if (consp obj)
                   (let ((*print-length* 4) (*print-level* 3))
                     (format nil "~S" (car obj)))
                   (format nil "~S" obj))))))
    ;; Keep the TSV one line per record.
    (substitute-if #\Space (lambda (c) (member c '(#\Newline #\Tab #\Return)))
                   s)))

(defun oracle-report (diffs)
  (incf (getf *oracle-stats* :problems))
  (incf (getf *oracle-stats* :diffs) (length diffs))
  (dolist (d diffs)
    (unless (oracle-explained-p d)
      (incf (getf *oracle-stats* :unexplained))
      (when *oracle-out*
        (destructuring-bind (kind obj ind) d
          (with-standard-io-syntax
            (let ((*package* (find-package :maxima)))
              (format *oracle-out* "~A~C~D~C~(~A~)~C~A~C~A~C~S~%"
                      *oracle-file* #\Tab *oracle-problem* #\Tab kind #\Tab
                      (oracle-object-kind obj) #\Tab (oracle-object-name obj)
                      #\Tab ind)))))))
  (clrhash *oracle-log*))

(defun oracle-step ()
  "Snapshot now and report the diff against the previous snapshot."
  (let ((snap (oracle-snapshot)))
    (when *oracle-snapshot*
      (oracle-report (oracle-diff *oracle-snapshot* snap)))
    (setq *oracle-snapshot* snap)))

;;; ------------------------------------------------------------ wiring

(defvar *oracle-original-meval** (fdefinition 'meval*))
(defvar *oracle-original-test-batch* (fdefinition 'test-batch))

(defun oracle-install (output-path)
  "Install the oracle: recording hook, MEVAL* and TEST-BATCH wrappers.
Differences are appended to OUTPUT-PATH."
  (setq *oracle-out* (open output-path :direction :output
                                       :if-exists :append
                                       :if-does-not-exist :create))
  (setq *environment-write-hook* #'oracle-hook)
  (oracle-wrap-loads)
  (setf (fdefinition 'test-batch)
        (lambda (filename &rest args)
          (let ((*oracle-file* (file-namestring filename))
                (*oracle-problem* 0))
            (setq *oracle-snapshot* (oracle-snapshot))
            (clrhash *oracle-log*)
            ;; RUN_TESTSUITE reads four values from TEST-BATCH.
            (multiple-value-prog1
                (apply *oracle-original-test-batch* filename args)
              (setq *oracle-snapshot* nil)
              (finish-output *oracle-out*)))))
  (setf (fdefinition 'meval*)
        (lambda (expr)
          (if (or (null *oracle-snapshot*) (> *oracle-depth* 0))
              (funcall *oracle-original-meval** expr)
              (let ((*oracle-depth* 1))
                (incf *oracle-problem*)
                (prog1 (funcall *oracle-original-meval** expr)
                  (let ((*environment-write-hook* nil))
                    (oracle-step)))))))
  t)

(defun oracle-around-load (label thunk)
  "Attribute everything written while THUNK runs to a separate unit named
load:LABEL, so package loading is not charged to the problem that
triggered it."
  (if (or (null *oracle-snapshot*) (null *oracle-out*))
      (funcall thunk)
      (let ((*environment-write-hook* nil))
        (oracle-step)                   ; close the enclosing unit so far
        (multiple-value-prog1
            (let ((*oracle-file* (format nil "load:~A" label))
                  (*environment-write-hook* #'oracle-hook))
              (multiple-value-prog1 (funcall thunk)
                (let ((*environment-write-hook* nil))
                  (oracle-step))))))))

(defun oracle-load-label (x)
  (let ((p (cond ((pathnamep x) x)
                 ((stringp x) (pathname x))
                 ((and (consp x) (or (stringp (cdr x)) (pathnamep (cdr x))))
                  (pathname (cdr x)))
                 ((typep x 'file-stream) (pathname x))
                 (t nil))))
    (if p (file-namestring p) "?")))

(defvar *oracle-original-loadfile* (fdefinition 'loadfile))
(defvar *oracle-original-batchload-stream* (fdefinition 'batchload-stream))
(defvar *oracle-original-generic-autoload* (fdefinition 'generic-autoload))
(defvar *oracle-original-aload* (fdefinition 'aload))

(defun oracle-wrap-loads ()
  (setf (fdefinition 'loadfile)
        (lambda (file &rest args)
          (oracle-around-load (oracle-load-label file)
                              (lambda () (apply *oracle-original-loadfile*
                                                file args)))))
  (setf (fdefinition 'batchload-stream)
        (lambda (stream &rest args)
          (oracle-around-load (oracle-load-label (or (getf args :truename)
                                                     stream))
                              (lambda () (apply *oracle-original-batchload-stream*
                                                stream args)))))
    ;; AUTOF/AUTOM stubs (autol.lisp) call ALOAD -> CL LOAD directly.
  (setf (fdefinition 'aload)
        (lambda (file &rest args)
          (oracle-around-load (oracle-load-label file)
                              (lambda () (apply *oracle-original-aload*
                                                file args)))))
  (setf (fdefinition 'generic-autoload)
        (lambda (file &rest args)
          (oracle-around-load (oracle-load-label file)
                              (lambda () (apply *oracle-original-generic-autoload*
                                                file args))))))

(defun oracle-summary ()
  (format t "~&ORACLE ~S writes-observed ~D~%" *oracle-stats* *oracle-writes*)
  (when *oracle-out* (finish-output *oracle-out*)))
