;;; Counts MBIND calls and variables bound (task 3.3).
;;;
;;; MBIND is a plain DEFUN and not declaimed inline (checked with
;;; SB-INT:INFO :FUNCTION :INLINEP), so redefining it at run time catches
;;; every call without rebuilding.  Counting prints to *DEBUG-IO*:
;;; RUN_TESTSUITE rebinds *STANDARD-OUTPUT* per problem to a string stream
;;; and would swallow it (AGENTS.md sec. 4).

(in-package :maxima)

(defvar *mbind-calls* 0)
(defvar *mbind-vars* 0)
(defvar *mbind-original* nil)

(unless *mbind-original*
  (setf *mbind-original* (fdefinition 'mbind))
  (setf (fdefinition 'mbind)
        (lambda (lamvars fnargs fnname)
          (incf *mbind-calls*)
          (incf *mbind-vars* (length lamvars))
          (funcall *mbind-original* lamvars fnargs fnname))))

(defun mbind-count-reset ()
  (setf *mbind-calls* 0 *mbind-vars* 0))

(defun mbind-count-report (label wall record-path)
  (let ((calls *mbind-calls*) (vars *mbind-vars*))
    (pool-append-record
     record-path
     (list :label label :kind "mbind-count"
           :calls calls :vars vars
           :vars_per_call (if (plusp calls) (/ vars (float calls 1d0)) 0d0)
           :wall wall
           :calls_per_second (if (plusp wall) (/ calls wall) 0d0)))
    (format *debug-io* "~&~a: ~:d mbind calls, ~:d variables bound, ~
                        ~,2F per call, ~,2F s, ~:d calls/s~%"
            label calls vars (if (plusp calls) (/ vars (float calls 1d0)) 0d0)
            wall (round (if (plusp wall) (/ calls wall) 0)))
    (values)))

(defmacro with-mbind-count ((label record-path) &body body)
  `(progn
     (mbind-count-reset)
     (let ((t0 (pool-now)))
       (multiple-value-prog1 (progn ,@body)
         (mbind-count-report ,label (pool-secs (- (pool-now) t0))
                             ,record-path)))))
