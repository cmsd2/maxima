;;; Aggregated environment-write profile (design D10).
;;;
;;; (ENVPROFILE INPUT &KEY (REPEAT 1)) evaluates the Maxima string INPUT
;;; REPEAT times with a counting hook and prints one line per
;;;   count  per-iteration  operation  object-kind  indicator
;;; sorted deterministically.  Object kinds: symbol (interned), gensym
;;; (uninterned, e.g. CRE variables), context (a member of CONTEXTS or an
;;; uninterned temporary context), node (a fact-database cell).  Generated
;;; names never appear, so profiles from separate sessions compare
;;; directly.
;;;
;;; (ENVPROFILE-REGION-BEGIN) / (ENVPROFILE-REGION-END) bracket a region
;;; inside a larger computation; only writes between them are counted.

(in-package :maxima)

(defvar *envprofile-counts* (make-hash-table :test 'equal))
(defvar *envprofile-active* nil)

(defun envprofile-kind (obj)
  (cond ((consp obj) "node")
        ((not (symbolp obj)) "other")
        ((or (member obj (cdr $contexts))
             (and (boundp 'context) (eq obj (symbol-value 'context))))
         (if (symbol-package obj) "context" "context-temp"))
        ((null (symbol-package obj)) "gensym")
        (t "symbol")))

(defun envprofile-hook (op obj ind val)
  (declare (ignore val))
  (when *envprofile-active*
    (incf (gethash (list op (envprofile-kind obj)
                         (if (symbolp ind) (symbol-name ind) (princ-to-string ind)))
                   *envprofile-counts* 0))))

(defun envprofile-region-begin ()
  (clrhash *envprofile-counts*)
  (setq *environment-write-hook* #'envprofile-hook
        *envprofile-active* t))

(defun envprofile-region-end ()
  (setq *envprofile-active* nil))

(defun envprofile-print (repeat)
  (let ((rows '()) (total 0))
    (maphash (lambda (k n) (push (cons k n) rows) (incf total n))
             *envprofile-counts*)
    (setq rows (sort rows (lambda (a b)
                            (string< (format nil "~{~A~^ ~}" (car a))
                                     (format nil "~{~A~^ ~}" (car b))))))
    (format t "~&PROFILE total ~D writes, ~D per iteration, ~D keys~%"
            total (/ total repeat) (length rows))
    (dolist (r rows)
      (destructuring-bind ((op kind ind) . n) r
        (format t "~&PROFILE ~8D ~10,2F ~(~A~) ~A ~A~%"
                n (/ n repeat 1.0) op kind ind)))))

(defun envprofile (input &key (repeat 1))
  (let ((form (macsyma-read-string input)))
    (envprofile-region-begin)
    (unwind-protect
         (dotimes (i repeat) (meval* form))
      (envprofile-region-end))
    (envprofile-print repeat)))
