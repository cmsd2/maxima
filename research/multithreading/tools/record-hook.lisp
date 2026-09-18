;;; Recording environment-write hook for ad hoc checks.
;;; (record-writes FORM-STRING) evaluates Maxima input with the hook
;;; installed and returns the list of (OPERATION OBJECT INDICATOR).
(in-package :maxima)

(defun record-writes (input)
  (let ((log '()))
    (let ((*environment-write-hook*
            (lambda (op obj ind val)
              (declare (ignore val))
              (push (list op (if (consp obj) :node obj) ind) log))))
      (meval* (macsyma-read-string input)))
    (nreverse log)))

(defun show-writes (input &key (filter nil))
  (let ((w (record-writes input)))
    (format t "~&~A~%  ~D writes~%" input (length w))
    (dolist (e (if filter (remove-if-not filter w) w))
      (format t "    ~S~%" e))))
