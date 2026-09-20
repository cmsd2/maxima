;;; GC scaling spike (add-thread-feasibility-spikes, spike A).
;;;
;;; GCSPIKE-REFERENCE measures the allocation profile of a real Maxima
;;; workload (task 1.1): rate, GC share, collections and promoted bytes.
;;; The synthetic allocator calibrated against it, and the thread and
;;; process arms, are added in stage B.
;;;
;;; Loads after pool.lisp, whose JSON and timing helpers it reuses.
;;;
;;; SB-EXT:GENERATION-NUMBER-OF-GCS is not a cumulative counter -- it resets
;;; when the generation is collected -- so collections are counted in an
;;; SB-EXT:*AFTER-GC-HOOKS* hook instead.  The hook also samples
;;; SB-EXT:GENERATION-BYTES-ALLOCATED, whose rises in generation 1 are the
;;; bytes that survived a nursery collection.

(in-package :maxima)

(defconstant +gcspike-generations+ 3
  "Generations whose occupancy is sampled.  Gen 0 is the nursery; anything
   reaching gen 3 in a run this short is image data, not garbage.")

(defstruct (gcspike-gc (:conc-name gcspike-))
  (count 0 :type fixnum)                ; collections seen
  (real-time 0 :type integer)           ; ticks of GC wall time
  (run-time 0 :type integer)            ; ticks of GC run time
  (promoted 0 :type integer)            ; bytes that rose into generation 1
  (durations '() :type list)            ; per-collection wall time, seconds
  (last-real 0 :type integer)
  (last-run 0 :type integer)
  (last-gen1 0 :type integer))

(defvar *gcspike-gc* nil "Collector statistics for the run in progress.")

(defun gcspike-gen-bytes ()
  (loop for g from 0 below +gcspike-generations+
        collect (sb-ext:generation-bytes-allocated g)))

(defun gcspike-gc-hook ()
  (let ((s *gcspike-gc*))
    (when s
      (let ((real sb-ext:*gc-real-time*)
            (run sb-ext:*gc-run-time*)
            (gen1 (sb-ext:generation-bytes-allocated 1)))
        (incf (gcspike-count s))
        (push (pool-secs (- real (gcspike-last-real s))) (gcspike-durations s))
        (incf (gcspike-real-time s) (- real (gcspike-last-real s)))
        (incf (gcspike-run-time s) (- run (gcspike-last-run s)))
        ;; A rise in generation 1 is promotion out of the nursery; a fall is
        ;; generation 1 itself being collected, which promotes nothing.
        (let ((rise (- gen1 (gcspike-last-gen1 s))))
          (when (plusp rise) (incf (gcspike-promoted s) rise)))
        (setf (gcspike-last-real s) real
              (gcspike-last-run s) run
              (gcspike-last-gen1 s) gen1)))))

(defmacro with-gcspike-stats ((var) &body body)
  "Run BODY with collector statistics gathered into VAR.
   SB-EXT:*AFTER-GC-HOOKS* is a global lexical, so it cannot be bound with
   LET; the hook is pushed and removed instead.  The list is shared by every
   thread, which is what the thread arm needs: the hook runs in whichever
   thread collected."
  `(let ((,var (make-gcspike-gc :last-real sb-ext:*gc-real-time*
                                :last-run sb-ext:*gc-run-time*
                                :last-gen1 (sb-ext:generation-bytes-allocated 1))))
     (setf *gcspike-gc* ,var)
     (push #'gcspike-gc-hook sb-ext:*after-gc-hooks*)
     (unwind-protect (progn ,@body)
       (setf sb-ext:*after-gc-hooks*
             (remove #'gcspike-gc-hook sb-ext:*after-gc-hooks*)
             *gcspike-gc* nil))))

(defun gcspike-live-bytes ()
  "Live heap in bytes, after a full collection.  Perturbs timing, so call
   this only outside a timed region."
  (sb-ext:gc :full t)
  (sb-kernel:dynamic-usage))

(defun gcspike-collector-features ()
  (list :gencgc (and (find :gencgc *features*) t)
        :mark-region (and (find :mark-region-gc *features*) t)
        :gc-parallel (and (find :gc-parallel *features*) t)
        :threads (and (find :sb-thread *features*) t)
        :nursery-bytes (sb-ext:bytes-consed-between-gcs)
        :gcs-before-promotion
        (loop for g from 0 below +gcspike-generations+
              collect (sb-ext:generation-number-of-gcs-before-promotion g))))

(defun gcspike-stats-plist (s wall)
  (let ((d (gcspike-durations s)))
    (list :collections (gcspike-count s)
          :gc_real (pool-secs (gcspike-real-time s))
          :gc_run (pool-secs (gcspike-run-time s))
          :gc_share (/ (pool-secs (gcspike-real-time s)) (max wall 1d-9))
          :promoted (gcspike-promoted s)
          :pause_mean (if d (/ (reduce #'+ d) (length d)) 0d0)
          :pause_max (if d (reduce #'max d) 0d0))))

(defun gcspike-reference (fn n record-path &key (label "wc-reference"))
  "Evaluate the Maxima function FN over 0..N-1, recording the allocation
   profile the synthetic allocator has to reproduce."
  (let ((live0 (gcspike-live-bytes))
        (wall 0d0) (bytes 0) (stats nil) (gen-bytes nil))
    ;; The statistics region covers the timed loop only.  GCSPIKE-LIVE-BYTES
    ;; forces a full collection, and reporting conses; neither belongs in the
    ;; run's collector statistics.
    (with-gcspike-stats (s)
      (let ((bytes0 (sb-ext:get-bytes-consed))
            (t0 (pool-now)))
        (dotimes (i n) (pool-item fn i))
        (setf wall (pool-secs (- (pool-now) t0))
              bytes (- (sb-ext:get-bytes-consed) bytes0)
              gen-bytes (gcspike-gen-bytes)
              stats (copy-gcspike-gc s))))
    (let ((live (gcspike-live-bytes)))
      (pool-append-record
       record-path
       (append
        (list :label label :kind "reference" :items n
              :wall wall :bytes_consed bytes
              :alloc_rate_gbs (/ bytes wall 1073741824d0))
        (gcspike-stats-plist stats wall)
        (list :survival (/ (gcspike-promoted stats) (max bytes 1))
              :gen_bytes gen-bytes
              :live_before live0 :live_after live
              :maxrss (pool-maxrss)
              :collector (gcspike-collector-features))))
      (gcspike-report label stats wall bytes)
      (format *debug-io* "  live ~:d -> ~:d~%" live0 live)
      (values))))

(defun gcspike-report (label s wall bytes)
  "One line of console summary, from the same numbers as the JSON record."
  (let* ((d (gcspike-durations s))
         (mean (if d (/ (reduce #'+ d) (length d)) 0d0))
         (worst (if d (reduce #'max d) 0d0)))
    (format *debug-io*
            "~&~a: ~,2F s, ~,1F GB, ~,3F GB/s, ~d collections, GC ~,2F% ~
             (mean pause ~,2F ms, max ~,2F ms), promoted ~,2F MB ~
             (~,4F% of consed)~%"
            label wall (/ bytes 1073741824d0) (/ bytes wall 1073741824d0)
            (gcspike-count s)
            (* 100 (/ (pool-secs (gcspike-real-time s)) (max wall 1d-9)))
            (* 1000 mean) (* 1000 worst)
            (/ (gcspike-promoted s) 1048576d0)
            (* 100 (/ (gcspike-promoted s) (max bytes 1d0))))))

;;; ------------------------------------------------------ synthetic allocator
;;;
;;; The loop builds small tree structures shaped like simplified Maxima
;;; expressions -- a header list, then WIDTH arguments, nested DEPTH deep --
;;; walks each one, and drops it.  Pointer-rich garbage is what a symbolic
;;; run produces and what makes marking expensive; one large vector per
;;; iteration would allocate the same bytes and cost the collector nothing.
;;;
;;; Three knobs, set at calibration (task 1.3):
;;;   DEPTH, WIDTH   node size, and so bytes per iteration
;;;   WALKS          traversals per node: raises time per iteration, and so
;;;                  lowers the allocation rate to the workload's
;;;   RETAIN-EVERY, RING-SIZE
;;;                  one node in RETAIN-EVERY is held in a ring of RING-SIZE,
;;;                  so it is live at the next collection and promotes out of
;;;                  the nursery.  This sets the survival fraction.
;;;
;;; Calibrated settings (gate A), against wc_systematic at 12 tolerances:
;;;
;;;   :depth 2 :width 3 :walks 9 :retain-every 512 :ring-size 4096
;;;
;;;                     reference (wc12)   calibrated
;;;   allocation rate    0.74 GB/s          0.78 GB/s
;;;   GC share           1.33%              1.17%
;;;   mean pause         0.90 ms            0.75 ms
;;;   collections per GB 20                 20
;;;   survival           0.047%             0.25%
;;;
;;; Survival is the one mismatch, and it cannot be fixed at the same time as
;;; the pause: promotion has a floor of about 31 KB per collection from page
;;; granularity (measured with retention switched off), already above the
;;; workload's 24 KB, while reaching the workload's pause length needs a
;;; multi-megabyte live ring.  Matching GC cost was preferred over matching
;;; survival, because pause length is what stops threads.  The
;;; survival-matched alternative, :retain-every 32768 :ring-size 64
;;; (survival 0.069%, pause 0.64 ms, GC 0.99%), is the sensitivity check.

(defun gcspike-build (depth width seed)
  (declare (type fixnum depth width seed) (optimize speed))
  (if (<= depth 0)
      (cons (list 'gcspike-atom 'simp) (list seed (the fixnum (1+ seed))))
      (let ((args '()))
        (dotimes (k width)
          (push (gcspike-build (1- depth) width (+ seed k)) args))
        (cons (list 'gcspike-op 'simp) args))))

(defun gcspike-sum (node)
  "Walk NODE, adding every fixnum in it.  Returns a fixnum."
  (declare (optimize speed))
  (let ((acc 0))
    (declare (type fixnum acc))
    (labels ((walk (x)
               (cond ((consp x) (walk (car x)) (walk (cdr x)))
                     ((typep x 'fixnum)
                      (setf acc (logand (+ acc (the fixnum x))
                                        most-positive-fixnum))))))
      (walk node))
    acc))

(defun gcspike-node-bytes (depth width)
  "Bytes allocated by one GCSPIKE-BUILD call."
  (let ((bytes 0))
    (labels ((count-node (d)
               ;; header list (2 conses) + spine, plus a 2-cons payload at a
               ;; leaf; SB-VM:CONS-SIZE words per cons.
               (incf bytes (* (+ 2 (if (<= d 0) 2 width))
                              sb-vm:cons-size sb-vm:n-word-bytes))
               (when (> d 0) (dotimes (k width) (count-node (1- d))))))
      (count-node depth))
    bytes))

(defstruct (gcspike-worker (:conc-name gcspike-w-))
  (id 0 :type fixnum)
  (iterations 0 :type fixnum)
  (checksum 0 :type integer)
  (bytes 0 :type integer)
  (wall 0d0 :type double-float))

(defun gcspike-work (id iterations &key (depth 2) (width 3) (walks 9)
                                        (retain-every 512) (ring-size 4096))
  "Allocate and drop ITERATIONS nodes, returning a GCSPIKE-WORKER record.
   Runs no shared state: everything it touches is its own."
  (declare (type fixnum iterations depth width walks retain-every ring-size)
           (optimize speed))
  (let ((ring (when (plusp ring-size) (make-array ring-size
                                                  :initial-element nil)))
        (ri 0) (sum 0) (b0 (sb-ext:get-bytes-consed)) (t0 (pool-now)))
    (declare (type fixnum ri) (type integer sum))
    (dotimes (i iterations)
      (declare (type fixnum i))
      (let ((node (gcspike-build depth width i)))
        (dotimes (w walks)
          (setf sum (logand (+ sum (gcspike-sum node)) most-positive-fixnum)))
        (when (and ring (zerop (mod i retain-every)))
          (setf (aref ring ri) node
                ri (mod (1+ ri) ring-size)))))
    ;; Keep the ring reachable past the timed region, so its contents really
    ;; did survive; then drop it.
    (when ring (setf sum (logand (+ sum (if (aref ring 0) 1 0))
                                 most-positive-fixnum)))
    (make-gcspike-worker
     :id id :iterations iterations :checksum sum
     :bytes (- (sb-ext:get-bytes-consed) b0)
     :wall (pool-secs (- (pool-now) t0)))))

(defun gcspike-calibrate (iterations &rest args
                          &key (depth 2) (width 3) (walks 9)
                               (retain-every 512) (ring-size 4096)
                               (record-path nil) (label "calibrate"))
  "Run the allocator once in this thread and report the profile it produced,
   for comparison with GCSPIKE-REFERENCE's numbers (task 1.3)."
  (declare (ignorable depth width walks retain-every ring-size))
  (let ((work-args (loop for (k v) on args by #'cddr
                         unless (member k '(:record-path :label))
                           append (list k v))))
    (gcspike-live-bytes)
    (let ((w nil) (stats nil))
      (with-gcspike-stats (s)
        (setf w (apply #'gcspike-work 0 iterations work-args)
              stats (copy-gcspike-gc s)))
      (let* ((wall (gcspike-w-wall w))
             (bytes (gcspike-w-bytes w))
             (plist (append
                     (list :label label :kind "calibration"
                           :iterations iterations
                           :node_bytes (gcspike-node-bytes depth width)
                           :depth depth :width width :walks walks
                           :retain_every retain-every :ring_size ring-size
                           :wall wall :bytes_consed bytes
                           :alloc_rate_gbs (/ bytes wall 1073741824d0)
                           :checksum (gcspike-w-checksum w))
                     (gcspike-stats-plist stats wall)
                     (list :survival (/ (gcspike-promoted stats) (max bytes 1))
                           :collector (gcspike-collector-features)))))
        (when record-path (pool-append-record record-path plist))
        (gcspike-report label stats wall bytes)
        (format *debug-io* "  node ~d B~%" (gcspike-node-bytes depth width))
        (values)))))
