;;; Passive environment-write hook: counts writes and does nothing else.
;;; Loaded before each corpus file for the with-hook differential run.
(in-package :maxima)
(defvar *environment-write-count* 0)
(setq *environment-write-hook*
      (lambda (op obj ind val)
        (declare (ignore op obj ind val))
        (incf *environment-write-count*)))
