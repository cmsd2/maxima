;;; Functional tests for the environment write hook (tasks 7.1-7.3).
;;;
;;; Load into a built image.  (ENVHOOK-TEST-SCENARIOS) runs the spec
;;; scenarios in the current session; (ENVHOOK-TEST-WRITER NAME) runs one
;;; expected-writer row and is meant to be called in a fresh session.
;;; Each check prints "PASS name" or "FAIL name: detail"; the driver script
;;; counts them.

(in-package :maxima)

(defun envhook-record (input &optional (hook-extra nil))
  "Evaluate Maxima INPUT with a recording hook; return the list of
(OP OBJECT INDICATOR VALUE) in order.  HOOK-EXTRA, if given, is called
with the same arguments first (it may refuse by signalling)."
  (let ((log '()))
    (let ((*environment-write-hook*
            (lambda (op obj ind val)
              (when hook-extra (funcall hook-extra op obj ind val))
              (push (list op obj ind val) log))))
      (meval* (macsyma-read-string input)))
    (nreverse log)))

(defun envhook-check (name ok &optional detail)
  (if ok
      (format t "~&PASS ~A~%" name)
      (format t "~&FAIL ~A: ~A~%" name detail))
  ok)

(defun envhook-find (log op obj &optional ind)
  (find-if (lambda (e)
             (and (eq (first e) op)
                  (eq (second e) obj)
                  (or (null ind) (eq (third e) ind))))
           log))

(defun envhook-record-result (input hook-extra)
  "Like ENVHOOK-RECORD, but return the evaluation result."
  (let ((*environment-write-hook*
          (lambda (op obj ind val) (funcall hook-extra op obj ind val))))
    (meval* (macsyma-read-string input))))

(defun cleanup-after-scenarios ()
  (meval* (macsyma-read-string "(forget(x>0), kill(y), 0);")))

(defun envhook-test-scenarios ()
  ;; Function definition is reported.
  (let ((log (envhook-record "f(x):=x^2;")))
    (envhook-check "definition reports :put on $f"
                   (envhook-find log :put '$f)
                   (remove-duplicates (mapcar #'second log))))
  ;; Simplification rule is reported.
  (let ((log (envhook-record "tellsimp(sin(42), foo);")))
    (envhook-check "tellsimp reports a write on %sin"
                   (or (envhook-find log :put '%sin)
                       (envhook-find log :put '$sin))
                   (remove-duplicates (mapcar #'second log))))
  ;; Property removal is reported.
  (let ((log (envhook-record "kill(f);")))
    (envhook-check "kill reports :remove or :replace-plist on $f"
                   (or (envhook-find log :remove '$f)
                       (envhook-find log :replace-plist '$f))
                   (length log)))
  ;; Hidden writes during a query are reported.
  (envhook-record "(assume(x>0), 0);")
  (let ((log (envhook-record "sign(x);")))
    (envhook-check "sign(x) after assume reports writes"
                   (> (length log) 0) "no writes"))
  ;; Plain assignment is reported, with its value.
  (let* ((log (envhook-record "y:5;"))
         (e (envhook-find log :assign '$y)))
    (envhook-check "y:5 reports :assign $y 5"
                   (and e (eql (fourth e) 5)) e))
  ;; Binding a block local is reported on entry and restoration.
  (let* ((log (envhook-record "block([z:1], z+1);"))
         (ops (mapcar #'first (remove-if-not (lambda (e) (eq (second e) '$z))
                                             log))))
    (envhook-check "block local reports :assign then :unbind for $z"
                   (and (member :assign ops)
                        (member :unbind (member :assign ops)))
                   ops))
  ;; An observer can refuse a write (task 7.2).
  (let* ((refuse (lambda (op obj ind val)
                   (declare (ignore ind val))
                   (when (and (eq obj '$g) (not (eq op :unbind)))
                     (merror "refused"))))
         (res (let (($errormsg nil))
                (envhook-record-result "errcatch(g(x):=x);" refuse))))
    (envhook-check "refused definition: errcatch returns []"
                   (and (consp res) (eq (caar res) 'mlist) (null (cdr res)))
                   res)
    (envhook-check "refused definition: g has no function definition"
                   (null (mget '$g 'mexpr))
                   (mget '$g 'mexpr)))
  (cleanup-after-scenarios))

;;; ------------------------------------------------------------ writers

(defun envhook-any (log pred) (find-if pred log))

(defun envhook-test-writer (name)
  (flet ((row (label input pred &optional setup)
           (when setup (meval* (macsyma-read-string setup)))
           (let ((log (envhook-record input)))
             (envhook-check label (envhook-any log pred)
                            (let ((*print-length* 12))
                              (format nil "~D writes; ops/indicators ~S"
                                      (length log)
                                      (remove-duplicates
                                       (mapcar (lambda (e)
                                                 (list (first e) (third e)))
                                               log)
                                       :test #'equal)))))))
    (ecase name
      (:rat
       ;; $RAT itself only renumbers the CRE gensyms' value cells; DISREP is
       ;; written when the CRE is converted back (RATDISREPD).
       (row "ratdisrep(rat(x+y)): :put DISREP on a Maxima-created symbol"
            "ratdisrep(rat(x+y));"
            (lambda (e) (and (eq (first e) :put) (eq (third e) 'disrep)
                             (symbolp (second e))
                             (null (symbol-package (second e)))))))
      (:sign
       (row "sign(x) after assume(x>0): label puts"
            "sign(x);"
            (lambda (e) (and (eq (first e) :put)
                             (member (third e) '(+labs -labs))))
            "(assume(x>0), 0);"))
      (:limit
       (row "gruntz series path: :put INTERNAL on the limit variable"
            "gruntz(x^2/exp(x), x, inf);"
            (lambda (e) (and (eq (first e) :put) (eq (third e) 'internal)))))
      (:integrate
       (row "integrate: :put SUBC on a new context symbol"
            "integrate(1/(1+x^2), x);"
            (lambda (e) (and (eq (first e) :put) (eq (third e) 'subc)))))
      (:rectform
       ;; ABSARG1 assumes BASE # 0 only for a base that is not a number:
       ;; for (-1)^a the assumption is redundant and nothing is written.
       (row "rectform(x^a): fact-database writes (temporary x # 0)"
            "rectform(x^a);"
            (lambda (e) (and (eq (first e) :put)
                             (member (third e) '(data con))))))
      (:block
       (row "block([z:1], z): :assign and :unbind of $z"
            "block([z:1], z);"
            (lambda (e) (and (eq (first e) :unbind) (eq (second e) '$z))))))))
