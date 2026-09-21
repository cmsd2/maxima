;;; Stage A checks for the thread runner (add-threaded-prototype).
;;; Every check prints PASS or FAIL; the runner script greps for FAIL.
;;; Loads after pool.lisp and threads.lisp.

(in-package :maxima)

(defvar *tt-failures* 0)

(defun tt-check (name ok &optional detail)
  (format *debug-io* "~&~:[FAIL~;PASS~] ~a~@[ -- ~a~]~%" ok name detail)
  (unless ok (incf *tt-failures*))
  ok)

;;; Work items.  Each goes through MSET, so the write hook sees it.

(defvar $tt_var 0)
(defvar $tt_loose 0)

(defmfun $tt_confined (i)
  "Assign a symbol that IS in the thread's binding set, then read it back
   after giving the other threads time to overwrite it if they can."
  (mset '$tt_var i)
  (sleep 0.05)
  (symbol-value '$tt_var))

(defmfun $tt_escape (i)
  "Assign a symbol that is NOT in the binding set."
  (mset '$tt_loose i)
  i)

(defmfun $tt_plist (i)
  "Write a property, which no binding can confine."
  (putprop '$tt_var i 'tt-indicator)
  i)

(defmfun $tt_fresh_write (i)
  "Write a Lisp special directly, the way ANS is written: no MSET, so the
   write hook never sees it."
  (setf (symbol-value '$tt_fresh) i)
  (sleep 0.05)
  (symbol-value '$tt_fresh))

(defmfun $tt_block (i)
  "A block binding a symbol that is unbound between calls, as
   wc_systematic's locals are: MBIND assigns it (ADD2LNC on $VALUES, since
   it is not BOUNDP) and MUNBIND restores it to unbound (DELETE)."
  (mbind '($tt_blockvar) (list i) nil)
  (prog1 (* 2 (symbol-value '$tt_blockvar))
    (munbind '($tt_blockvar))))

(defun tt-run-stage-a ()
  (let* ((extra (list '$tt_var))
         (syms (thread-symbol-set extra)))

    ;; 1. The symbol set resolves to real, bound symbols.
    (let ((missing (remove-if #'thread-resolve +thread-special-names+))
          (unbound (remove-if-not
                    (lambda (n) (let ((s (thread-resolve n)))
                                  (and s (not (boundp s)))))
                    +thread-special-names+)))
      (format *debug-io* "~&;; symbol set: ~d bound, ~d names unresolved ~a, ~
                          ~d resolved but unbound ~a~%"
              (length syms) (length missing) missing
              (length unbound) unbound))
    (tt-check "symbol set resolves to symbols"
              (and syms (every #'symbolp syms))
              (format nil "~d symbols" (length syms)))
    (tt-check "unbound specials are kept, not dropped"
              (member (thread-resolve "ANS") syms)
              "ANS is written during the workload and is unbound in a fresh image")
    (tt-check "binding stack is in the set"
              (and (member (thread-resolve "BINDLIST") syms)
                   (member (thread-resolve "MSPECLIST") syms)))

    ;; 2. Confinement: each worker sees its own write, the parent sees none.
    (setf $tt_var :parent)
    (multiple-value-bind (results workers wall ok)
        (thread-run '$tt_confined 8 4 :symbols syms :warmup nil)
      (declare (ignore wall))
      (tt-check "confined run completes" ok
                (format nil "~a" (remove nil (mapcar (lambda (w)
                                                       (getf w :error))
                                                     workers))))
      ;; Each item returns what that worker read back after sleeping.  With
      ;; confinement each reads its own index; without it, whichever worker
      ;; wrote last.
      (tt-check "each worker read back its own write"
                (loop for i below 8 always (eql (aref results i) i))
                (format nil "~a" (coerce results 'list)))
      (tt-check "parent's value survived the region"
                (eq $tt_var :parent)
                (format nil "~s" $tt_var)))

    ;; 2b. Negative control.  The check above only means something if it
    ;; can fail: run the same work with the symbol left out of the set and
    ;; the guard off, which is what today's Maxima does on threads.
    (setf $tt_var :parent)
    (let ((without (remove '$tt_var syms)))
      (multiple-value-bind (results workers wall ok)
          (thread-run '$tt_confined 8 4 :symbols without :guard nil :warmup nil)
        (declare (ignore workers wall ok))
        (tt-check "negative control: unbound writes collide"
                  (notevery (lambda (i) (eql (aref results i) i))
                            (loop for i below 8 collect i))
                  (format nil "~a" (coerce results 'list)))
        (tt-check "negative control: the write reached the parent"
                  (not (eq $tt_var :parent))
                  (format nil "~s" $tt_var))))
    (setf $tt_var :parent)

    ;; 2c. A symbol with no global value is still confined.  ANS is like
    ;; this: unbound in a fresh image, written during the workload, and
    ;; SETQ'd by Lisp rather than through MSET, so the guard cannot see it.
    (makunbound '$tt_fresh)
    (let ((with-fresh (thread-symbol-set (list '$tt_var '$tt_fresh))))
      (tt-check "an unbound symbol stays in the set"
                (member '$tt_fresh with-fresh))
      (multiple-value-bind (results workers wall ok)
          (thread-run '$tt_fresh_write 8 4 :symbols with-fresh :warmup nil)
        (declare (ignore workers wall))
        (tt-check "unbound symbol: run completes" ok)
        (tt-check "unbound symbol: each worker read back its own write"
                  (loop for i below 8 always (eql (aref results i) i))
                  (format nil "~a" (coerce results 'list)))
        (tt-check "unbound symbol: still unbound in the parent"
                  (not (boundp '$tt_fresh)))))

    ;; 3. The guard fires on a symbol outside the set.
    (setf $tt_loose :parent)
    (multiple-value-bind (results workers wall ok)
        (thread-run '$tt_escape 4 2 :symbols syms :warmup nil)
      (declare (ignore results wall))
      (let ((errs (remove nil (mapcar (lambda (w) (getf w :error)) workers))))
        (tt-check "guard refuses the unconfined write" (and (not ok) errs)
                  (first errs))
        (tt-check "guard names the symbol"
                  (and errs (search "TT_LOOSE" (first errs))))
        (tt-check "the escaping write never reached the parent"
                  (eq $tt_loose :parent)
                  (format nil "~s" $tt_loose))))

    ;; 4. The guard reports a plist write, and tolerates one when told to.
    (multiple-value-bind (results workers wall ok)
        (thread-run '$tt_plist 4 2 :symbols syms :warmup nil)
      (declare (ignore results wall))
      (tt-check "guard refuses an untolerated plist write" (not ok)
                (first (remove nil (mapcar (lambda (w) (getf w :error))
                                           workers)))))
    (multiple-value-bind (results workers wall ok)
        (thread-run '$tt_plist 4 2 :symbols syms :tolerate '(tt-indicator) :warmup nil)
      (declare (ignore results workers wall))
      (tt-check "guard allows a tolerated plist write" ok))

    ;; 4b. A block local that is unbound between calls: MSET runs ADD2LNC
    ;; on $VALUES and MUNBIND runs DELETE, both destructive.  With $VALUES
    ;; copied per thread, the parent's list is untouched afterwards and
    ;; every worker's block completes.
    (let* ((before (copy-list $values))
           (with-loc (thread-symbol-set (list '$tt_var '$tt_blockvar))))
      (makunbound '$tt_blockvar)
      (multiple-value-bind (results workers wall ok)
          (thread-run '$tt_block 400 4 :symbols with-loc :warmup nil)
        (declare (ignore workers wall))
        (tt-check "unbound block local: 400 blocks on 4 threads complete" ok)
        (tt-check "unbound block local: every result right"
                  (loop for i below 400 always (eql (aref results i) (* 2 i))))
        (tt-check "unbound block local: parent's $values untouched"
                  (equal $values before)
                  (format nil "~d entries before, ~d after"
                          (length before) (length $values)))
        (tt-check "unbound block local: still unbound in the parent"
                  (not (boundp '$tt_blockvar)))))

    ;; 5. The warm-up runs item 0 once, in the parent, before the region:
    ;; the parent's variable holds item 0's write afterwards, and the guard
    ;; is not involved because no worker is running yet.
    (setf $tt_var :parent)
    (multiple-value-bind (results workers wall ok)
        (thread-run '$tt_confined 8 4 :symbols syms :warmup t)
      (declare (ignore workers wall))
      (tt-check "warm-up: run completes" ok)
      (tt-check "warm-up: item 0 ran in the parent" (eql $tt_var 0)
                (format nil "parent holds ~s" $tt_var))
      (tt-check "warm-up: workers still confined"
                (loop for i below 8 always (eql (aref results i) i))))
    (setf $tt_var :parent)

    (format *debug-io* "~&;; stage A checks: ~:[all passed~;~:*~d FAILED~]~%"
            (if (plusp *tt-failures*) *tt-failures* nil))
    *tt-failures*))
