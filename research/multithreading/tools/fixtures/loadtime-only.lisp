;;; Fixture: only load-time plist writes.  The scanner must exit 0.
(in-package :maxima)
(defprop $foo bar baz)
(setf (get '$foo 'qux) 1)
(dolist (s '($a $b)) (setf (get s 'kind) t))
(eval-when (:load-toplevel :execute) (remprop '$foo 'baz))
;; Quoted data is not code:
(defvar *data* '((setf (get x y) z)))
#+nil (defun dead () (setf (get 'x 'y) 1))
#| (defun commented () (remprop 'x 'y)) |#
(defun reads-only (x) (get x 'foo))
