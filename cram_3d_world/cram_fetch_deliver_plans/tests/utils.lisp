;;;
;;; Copyright (c) 2020, Amar Fayaz <amar@uni-bremen.de>
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

(in-package :fd-plans-tests)

(defparameter *error-counter-look-up* '())

(defmethod cpl:fail :before (&rest args)
  (when (and (not (null args)) (typep (first args) 'symbol))
    (add-error-count-for-error (first args))))
  

(defun init-test-env ()
  (coe:clear-belief)
  (setf cram-tf:*tf-default-timeout* 2.0)
  (setf prolog:*break-on-lisp-errors* t)
  (setf proj-reasoning::*projection-reasoning-enabled* nil))

(roslisp-utilities:register-ros-init-function init-test-env)

(defun init-projection ()
  (btr:clear-costmap-vis-object)
  (btr:add-objects-to-mesh-list "cram_pr2_pick_place_demo")
  (btr-utils:kill-all-objects)
  (setf (btr:pose (btr:get-robot-object)) (cl-transforms:make-identity-pose))
  (reset-error-counter))

(defun make-pose-stamped (pose-list)
  (cl-transforms-stamped:make-pose-stamped 
   "map" 0.0
   (apply #'cl-transforms:make-3d-vector (first pose-list))
   (apply #'cl-transforms:make-quaternion (second pose-list))))

(defun make-pose (pose-list)
  (cl-transforms:make-pose 
   (apply #'cl-transforms:make-3d-vector (first pose-list))
   (apply #'cl-transforms:make-quaternion (second pose-list))))

(defun spawn-object (pose object-type)
  (btr-utils:kill-all-objects)
  (btr:add-objects-to-mesh-list "cram_pr2_pick_place_demo")
  (btr:detach-all-objects (btr:get-robot-object))
  (btr-utils:spawn-object
   (intern (format nil "~a-1" object-type) :keyword)
   object-type
   :pose pose)
  (btr:simulate btr:*current-bullet-world* 100))

(defun error-type-to-keyword (error-type)
  (intern (format nil "~a" error-type) :keyword))

(defun reset-error-counter ()
  (setf *error-counter-look-up* '()))

(defun get-total-error-count ()
  (unless (null *error-counter-look-up*)
    (reduce (lambda (count1 count2) 
              (+ count1 count2))
            *error-counter-look-up*
            :key #'cdr)))

(defun add-error-count-for-error (error-type)
  (let ((error-keyword (error-type-to-keyword error-type)))
    (if (null (assoc error-keyword *error-counter-look-up*))
        (setf *error-counter-look-up* (cons (cons error-keyword 0)
                                            *error-counter-look-up*)))
        (incf (cdr (assoc error-keyword *error-counter-look-up*)))))

(defun get-error-count-for-error (error-type)
  (let ((error-keyword (error-type-to-keyword error-type)))
    (if (null (assoc error-keyword *error-counter-look-up*))
        0
        (cdr (assoc error-keyword *error-counter-look-up*)))))

;;;;;;;;;;;; Object Poses ;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *valid-location-on-island* 
  (make-pose-stamped '((-0.8 0.76 0.86) (0 0 0 1))))

(defparameter *valid-location-on-sink-area-surface*
  (make-pose-stamped '((1.48 0.96 0.86) (0 0 0 1))))


(defparameter *valid-location-on-sink-area-surface-near-oven*
  (make-pose-stamped '((1.54 1.1 0.86) (0 0 0 1))))

;;;;;;;;;;;;; Robot Poses ;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *valid-robot-pose-towards-island*
  (make-pose-stamped '((-0.1 0.74 0) (0 0 1 0))))

(defparameter *valid-robot-pose-towards-island-near-wall*
  (make-pose-stamped '((-0.1 2.2 0) (0 0 1 0))))

(defparameter *valid-robot-pose-towards-sink-area-surface*
  (make-pose-stamped '((0.8 0.7 0) (0 0 0 1))))

(defparameter *invalid-robot-pose-towards-sink-area-surface*
  (make-pose-stamped '((1.0 0.7 0) (0 0 0 1))))