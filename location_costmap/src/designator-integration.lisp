;;;
;;; Copyright (c) 2010, Lorenz Moesenlechner <moesenle@in.tum.de>
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;;
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors
;;;       may be used to endorse or promote products derived from this software
;;;       without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.
;;;

(in-package :location-costmap)

(defparameter *costmap-valid-solution-threshold* 0.10)
(defconstant +costmap-n-samples+ 1)

(defvar *costmap-cache* (tg:make-weak-hash-table :test 'eq :weakness :key))
(defvar *costmap-max-values (tg:make-weak-hash-table :test 'eq :weakness :key))

(defun get-cached-costmap (desig)
  (let ((first-designator (first-desig desig)))
    (or (gethash first-designator *costmap-cache*)
        (setf (gethash first-designator *costmap-cache*)
              (with-vars-bound (?cm)
                  (lazy-car
                   (prolog `(merged-desig-costmap ,desig ?cm)))
                (unless (is-var ?cm)
                  ?cm))))))

(defun get-cached-costmap-maxvalue (costmap)
  (or (gethash costmap *costmap-max-values)
      (setf (gethash costmap *costmap-max-values)
            (let ((cm (get-cost-map costmap))
                  (max 0))
              (declare (type cma:double-matrix cm))
              (dotimes (row (cma:height cm) max)
                (dotimes (col (cma:width cm))
                  (when (> (aref cm row col) max)
                    (setf max (aref cm row col)))))))))

(defun robot-current-pose-generator (desig)
  (declare (ignore desig))
  (when *transformer*
    (handler-case
        (let ((robot-pose
                (cl-transforms-stamped:transform-pose-stamped
                 *transformer*
                 :pose (make-pose-stamped
                        designators-ros:*robot-base-frame*
                        (roslisp:ros-time)
                        (cl-transforms:make-identity-vector)
                        (cl-transforms:make-identity-rotation))
                 :target-frame designators-ros:*fixed-frame*
                 :timeout cram-roslisp-common:*tf-default-timeout*)))
          (list robot-pose))
      (transform-stamped-error () nil))))

(defun location-costmap-generator (desig)
  (let ((costmap (get-cached-costmap desig)))
    (unless costmap
      (return-from location-costmap-generator nil))
    (publish-location-costmap costmap)
    (handler-case (costmap-samples costmap)
      (invalid-probability-distribution ()
        nil))))

(defun location-costmap-pose-validator (desig pose)
  (if (typep pose 'cl-transforms:pose)
      (let* ((cm (get-cached-costmap desig))
             (p (cl-transforms:origin pose)))
        (unless cm
          (return-from location-costmap-pose-validator :unknown))
        (handler-case
            (let ((costmap-value (/ (get-map-value
                                     cm
                                     (cl-transforms:x p)
                                     (cl-transforms:y p))
                                    (get-cached-costmap-maxvalue cm)))
                  (costmap-heights (generate-heights
                                    cm (cl-transforms:x p) (cl-transforms:y p))))
              (when (> costmap-value *costmap-valid-solution-threshold*)
                (cond ((not costmap-heights)
                       :accept)
                      ((find-if (lambda (height)
                                  (< (abs (- height (cl-transforms:z p)))
                                     1e-3))
                                costmap-heights)
                       :accept))))
          (cma:invalid-probability-distribution ()
            :maybe-reject)))
      :unknown))

(register-location-generator
 15 robot-current-pose-generator
 "We should move the robot only if we really need to move. Try the
 current robot pose as a first solution.")

(register-location-generator
 20 location-costmap-generator
 "This generator uses a location costmap generated by the predicate
\(DESIG-COSTMAP ?desig ?costmap\) to generate an infinite number of
candidate solutions.")

(register-location-validation-function
 20 location-costmap-pose-validator
 "Generates a costmap from the designator and only allows poses that
 have a costmap value above the threshold
 *COSTMAP-VALID-SOLUTION-THRESHOLD*. Please note that this threshold
 is specifying the fraction of the maximal value in the costmap, not
 the direct value returned by GET-MAP-VALUE.")

