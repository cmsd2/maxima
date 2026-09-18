;;; Seeded bypasses (task 5.2).  Each function writes the environment
;;; without going through the observable funnel.  The scanner and/or the
;;; oracle must catch each one.
(in-package :maxima)

(defun seeded-setf-get ()               ; scanner + oracle (:added)
  (setf (get '$seeded_a 'seeded-ind) 1))

(defun seeded-funcall-setf-get ()       ; scanner only: #'(setf get) is
  (funcall #'(setf get) 2 '$seeded_b 'seeded-ind))   ; undefined in SBCL

(defun seeded-getf-symbol-plist ()      ; scanner + oracle (:added)
  (setf (getf (symbol-plist '$seeded_b) 'seeded-ind) 2))

(defun seeded-rplacd-stored-value ()    ; oracle only (:mutated)
  (let ((cell (list 1 2)))
    (putprop '$seeded_c cell 'seeded-ind)       ; observed write first
    (let ((*environment-write-hook* nil))       ; not what we test
      nil)
    cell))

(defun seeded-rplacd-now (cell)
  (rplacd (last cell) (list 3)))

(defun seeded-nconc-values ()           ; oracle only (:mutated $values)
  (nconc $values (list '$seeded_d)))
