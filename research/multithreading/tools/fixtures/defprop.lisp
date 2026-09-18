(in-package :maxima)
(defun d1 () (defprop $a 1 foo))
(defun d2 (n) `(defprop ,n t bar))
(defprop $b 2 foo)
