;;; Fixture: each run-time pattern once.  The scanner must report 7 runtime
;;; hits and exit 1.
(in-package :maxima)
(defun w1 (x) (setf (get x 'a) 1))
(defun w2 (x) (remprop x 'a))
(defun w3 (x y) (setf (symbol-plist x) (symbol-plist y)))
(defun w4 (n) (setf (getf (cdr n) 'a) 1))
(defun w5 (x) (funcall #'(setf get) 1 x 'a))
(defun w6 (x) (push 1 (get x 'a)))
(let ((cache nil)) (defun w7 (x) (incf (get x 'count 0)) cache))
