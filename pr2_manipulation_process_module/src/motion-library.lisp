;;; Copyright (c) 2012, Jan Winkler <winkler@informatik.uni-bremen.de>
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
;;;       Universitaet Bremen nor the names of its contributors may be used to
;;;       endorse or promote products derived from this software without
;;;       specific prior written permission.
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

(in-package :pr2-manipulation-process-module)

(defvar *registered-arm-poses* nil)

(defclass manipulation-parameters ()
  ((arm :accessor arm :initform nil :initarg :arm)
   (safe-pose :accessor safe-pose :initform nil :initarg :safe-pose)
   (grasp-type :accessor grasp-type :initform nil :initarg :grasp-type)
   (object-part :accessor object-part :initform nil :initarg :object-part)))

(defclass grasp-parameters (manipulation-parameters)
  ((grasp-pose :accessor grasp-pose :initform nil :initarg :grasp-pose)
   (pregrasp-pose :accessor pregrasp-pose :initform nil :initarg :pregrasp-pose)
   (effort :accessor effort :initform nil :initarg :effort)
   (close-radius :accessor close-radius :initform nil :initarg :close-radius)))

(defclass putdown-parameters (manipulation-parameters)
  ((pre-putdown-pose :accessor pre-putdown-pose :initform nil :initarg :pre-putdown-pose)
   (putdown-pose :accessor putdown-pose :initform nil :initarg :putdown-pose)
   (unhand-pose :accessor unhand-pose :initform nil :initarg :unhand-pose)
   (open-radius :accessor open-radius :initform nil :initarg :open-radius)))

;; Conversion functions for generating trajectories based on
;; manipulation parameterizations.
(defgeneric parameter-set->pregrasp-trajectory (parameter-set))
(defgeneric parameter-set->grasp-trajectory (parameter-set))
(defgeneric parameter-set->pre-putdown-trajectory (parameter-set))
(defgeneric parameter-set->putdown-trajectory (parameter-set))
(defgeneric parameter-set->unhand-trajectory (parameter-set))
(defgeneric parameter-set->safe-trajectory (parameter-set))

(define-hook on-execute-grasp-with-effort (object-name))
(define-hook on-execute-grasp-gripper-closed
    (object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose))
(define-hook on-execute-grasp-gripper-positioned-for-grasp
    (object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose))
(define-hook on-execute-grasp-pregrasp-reached
    (object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose))

(defun execute-grasp (&key (mode :traditional);:smooth)
                        object-name
                        object-pose
                        pregrasp-pose
                        grasp-pose
                        side (gripper-open-pos 0.2)
                        (gripper-close-pos 0.0)
                        allowed-collision-objects
                        safe-pose
                        (gripper-effort 100.0))
  (let ((allowed-collision-objects (append
                                    allowed-collision-objects
                                    (list object-name))))
    (cond ((eql mode :traditional)
           (execute-grasp-traditional
            :object-name object-name
            :object-pose object-pose
            :pregrasp-pose pregrasp-pose
            :grasp-pose grasp-pose
            :side side
            :gripper-open-pos gripper-open-pos
            :gripper-close-pos gripper-close-pos
            :allowed-collision-objects allowed-collision-objects
            :safe-pose safe-pose
            :gripper-effort gripper-effort))
          ((eql mode :smooth)
           (execute-grasp-smooth
            :object-name object-name
            :object-pose object-pose
            :pregrasp-pose pregrasp-pose
            :grasp-pose grasp-pose
            :side side
            :gripper-open-pos gripper-open-pos
            :gripper-close-pos gripper-close-pos
            :allowed-collision-objects allowed-collision-objects
            :safe-pose safe-pose
            :gripper-effort gripper-effort))
          (t (ros-error (pr2 grasp)
                        "Invalid grasping motion executer: ~a" mode)))))

(defun execute-grasp-smooth (&key object-name
                               object-pose
                               pregrasp-pose
                               grasp-pose
                               side (gripper-open-pos 0.2)
                               (gripper-close-pos 0.0)
                               allowed-collision-objects
                               safe-pose
                               (gripper-effort 100.0)
                               max-tilt)
  (declare (ignorable object-pose gripper-close-pos max-tilt))
  ;; Generate trajectories for grasp and pregrasp
  (let* ((pregrasp-trajectory
           (execute-move-arm-pose
            side pregrasp-pose
            :allowed-collision-objects allowed-collision-objects
            :plan-only t))
         (pregrasp-end-state (robot-trajectory-end-joint-state pregrasp-trajectory)))
    (unless pregrasp-trajectory
      (ros-warn (pr2 grasp) "Unable to assume pregrasp pose.")
      (cpl:fail 'manipulation-pose-unreachable))
    (let ((grasp-trajectory
            (execute-move-arm-pose
             side grasp-pose
             :allowed-collision-objects allowed-collision-objects
             :plan-only t
             :start-state (roslisp:make-message
                           "moveit_msgs/RobotState"
                           :joint_state pregrasp-end-state))))
      (unless grasp-trajectory
        (ros-warn (pr2 grasp) "Unable to assume grasp pose.")
        (cpl:fail 'manipulation-pose-unreachable))
      (let ((merged-trajectory (merge-robot-trajectories pregrasp-trajectory grasp-trajectory)))
        (ros-info (pr2 grasp) "Opening gripper")
        (open-gripper side :max-effort gripper-effort :position gripper-open-pos)
        (moveit:remove-collision-object object-name)
        (unwind-protect
             (moveit::execute-trajectory merged-trajectory)
          (moveit:add-collision-object object-name))
        (when (< (get-gripper-state side) 0.0025)
          (ros-warn
           (pr2 grasp)
           "Missed the object (am at ~a). Going into fallback pose for side ~a."
           (get-gripper-state side) side)
          (open-gripper side)
          (execute-move-arm-pose side pregrasp-pose
                                 :allowed-collision-objects
                                 allowed-collision-objects)
          (moveit:add-collision-object object-name)
          (when safe-pose
            (execute-move-arm-pose side safe-pose
                                   :allowed-collision-objects
                                   allowed-collision-objects))
          (cpl:fail 'cram-plan-failures:object-lost))))
    (moveit:add-collision-object object-name)
    (let ((link-frame
            (cut:var-value
             '?link
             (first
              (crs:prolog
               `(manipulator-link ,side ?link))))))
      (moveit:attach-collision-object-to-link
       object-name link-frame))))

(defun merge-robot-trajectories (&rest trajectories)
  (when trajectories
    (let ((first-trajectory (first trajectories))
          (trajectory-gap-time 0.1))
      (roslisp:with-fields (joint_trajectory) first-trajectory
        (roslisp:with-fields (header joint_names) joint_trajectory
          (roslisp:make-message
           "moveit_msgs/RobotTrajectory"
           :joint_trajectory
           (roslisp:make-message
            "trajectory_msgs/JointTrajectory"
            :header header
            :joint_names joint_names
            :points
            (map 'vector #'identity
                 (let ((traj-end-time 0.0))
                   (loop for trajectory in trajectories
                         appending (prog1
                                       (map 'list
                                            (lambda (point-old)
                                              (roslisp:with-fields (positions
                                                                    velocities
                                                                    accelerations
                                                                    time_from_start) point-old
                                                (roslisp:make-message
                                                 "trajectory_msgs/JointTrajectoryPoint"
                                                 :positions positions
                                                 :velocities velocities
                                                 :accelerations accelerations
                                                 :time_from_start (+ time_from_start traj-end-time))))
                                            (roslisp:with-fields (joint_trajectory) trajectory
                                              (roslisp:with-fields (points) joint_trajectory
                                                points)))
                                     (roslisp:with-fields (joint_trajectory) trajectory
                                       (roslisp:with-fields (points) joint_trajectory
                                         (let ((last-pt (elt points (1- (length points)))))
                                           (roslisp:with-fields (time_from_start) last-pt
                                             (setf traj-end-time (+ time_from_start
                                                                    trajectory-gap-time)))))))
                           into aggr-points
                         finally (return aggr-points)))))))))))

(defun robot-trajectory-end-joint-state (robot-trajectory)
  (when robot-trajectory
    (roslisp:with-fields (joint_trajectory) robot-trajectory
      (roslisp:with-fields (header joint_names points) joint_trajectory
        (when points
          (joint-trajectory-point->joint-state
           header joint_names (elt points (1- (length points)))))))))

(defun joint-trajectory-point->joint-state (header joint-names trajectory-point)
  (roslisp:with-fields (positions) trajectory-point
    (roslisp:make-message
     "sensor_msgs/JointState"
     :header header
     :name joint-names
     :position positions)))

(defun execute-grasp-traditional (&key object-name
                                    object-pose
                                    pregrasp-pose
                                    grasp-pose
                                    side (gripper-open-pos 0.2)
                                    (gripper-close-pos 0.0)
                                    allowed-collision-objects
                                    safe-pose
                                    (gripper-effort 100.0))
  (declare (ignore object-pose))
  ;; Gather hook'ed information for the grasp
  (let ((gripper-effort (or (first (on-execute-grasp-with-effort
                                    object-name))
                            gripper-effort)))
    (let ((link-frame
            (cut:var-value
             '?link
             (first
              (crs:prolog
               `(manipulator-link ,side ?link))))))
      (ros-info (pr2 grasp) "Executing pregrasp for side ~a~%" side)
      (cpl:with-retry-counters ((pregrasp-retry 1))
        (cpl:with-failure-handling
            (((or cram-plan-failures::manipulation-failure
                  moveit::moveit-failure) (f)
               (declare (ignore f))
               (ros-error (pr2 grasp)
                          "Failed to go into pregrasp pose for side ~a."
                          side)
               (cpl:do-retry pregrasp-retry
                 (execute-move-arm-pose side safe-pose)
                 (cpl:retry))
               (when safe-pose
                 (cpl:fail 'manipulation-pose-unreachable))))
          (execute-move-arm-pose side pregrasp-pose)))
      (ros-info (pr2 grasp) "Opening gripper")
      (open-gripper side :max-effort gripper-effort :position gripper-open-pos)
      (unless object-name
        (ros-warn (pr2 grasp) "You didn't specify an object name to grasp. This might cause the grasping to fail because of a misleading collision environment configuration."))
      (when object-name (moveit:remove-collision-object object-name))
      (on-execute-grasp-pregrasp-reached
       object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose)
      (ros-info (pr2 grasp) "Executing grasp for side ~a~%" side)
      (cpl:with-failure-handling
          ((manipulation-failed (f)
             (declare (ignore f))
             (ros-error
              (pr2 grasp)
              "Failed to go into grasp pose for side ~a."
              side)
             (when object-name (moveit:add-collision-object object-name))
             (cpl:fail 'manipulation-pose-unreachable)))
        (execute-move-arm-pose side grasp-pose :ignore-collisions t))
      (on-execute-grasp-gripper-positioned-for-grasp
       object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose)
      (ros-info (pr2 grasp) "Closing gripper")
      (close-gripper side :max-effort gripper-effort
                          :position gripper-close-pos)
      (on-execute-grasp-gripper-closed
       object-name gripper-effort gripper-close-pos side pregrasp-pose safe-pose)
      (when (< (get-gripper-state side) 0.0075);;gripper-close-pos)
        (cpl:with-failure-handling
            ((manipulation-failed (f)
               (declare (ignore f))
               (ros-error
                (pr2 grasp)
                "Failed to go into fallback pose for side ~a. Retrying."
                side)
               (cpl:retry))
             (moveit:pose-not-transformable-into-link (f)
               (declare (ignore f))
               (ros-warn
                (pr2 grasp)
                "TF error. Retrying.")
               (cpl:retry)))
          (ros-warn
           (pr2 grasp)
           "Missed the object (am at ~a). Going into fallback pose for side ~a."
           (get-gripper-state side) side)
          (open-gripper side)
          (execute-move-arm-pose side pregrasp-pose
                                 :allowed-collision-objects
                                 allowed-collision-objects)
          (moveit:add-collision-object object-name)
          (when safe-pose
            (execute-move-arm-pose side safe-pose
                                   :allowed-collision-objects
                                   allowed-collision-objects))
          (cpl:fail 'cram-plan-failures:object-lost)))
      (when object-name
        (moveit:add-collision-object object-name)
        (moveit:attach-collision-object-to-link
         object-name link-frame)))))

(defun arm-pose->trajectory (arm pose)
  (cpl:with-failure-handling
      (((or cram-plan-failures::manipulation-failure
            moveit::moveit-failure) (f)
         (declare (ignore f))
         (ros-error
          (pr2 grasp)
          "Failed to generate trajectory for ~a."
          arm)))
    (execute-move-arm-pose arm pose :quiet t :plan-only t)))

(defmethod parameter-set->pregrasp-trajectory ((parameter-set grasp-parameters))
  (ros-info (pr2 grasp) "Generating pregrasp trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (pregrasp-pose parameter-set)))

(defmethod parameter-set->grasp-trajectory ((parameter-set grasp-parameters))
  (ros-info (pr2 grasp) "Generating grasp trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (grasp-pose parameter-set)))

(defmethod parameter-set->safe-trajectory ((parameter-set manipulation-parameters))
  (ros-info (pr2 grasp) "Generating safe trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (safe-pose parameter-set)))

(defun execute-grasps (object-name parameter-sets)
  (labels ((assume-safe-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->safe-trajectory
                      (cpl:mapcar-clean
                       (lambda (parameter-set)
                         (when (safe-pose parameter-set)
                           parameter-set))
                       parameter-sets))
              :ignore-va t))
           (assume-pregrasp-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->pregrasp-trajectory parameter-sets)
              :ignore-va t))
           (assume-grasp-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->grasp-trajectory parameter-sets)
              :ignore-va t))
           (open-gripper-if-necessary (arm)
             (when (< (get-gripper-state arm) 0.08)
               (open-gripper arm)))
           (gripper-closed (arm)
             (< (get-gripper-state arm) 0.0025)))
    (cpl:with-failure-handling
        (((or cram-plan-failures:manipulation-failure
              cram-plan-failures:object-lost) (f)
           (declare (ignore f))
           (assume-safe-poses)))
      (assume-pregrasp-poses)
      (dolist (parameter-set parameter-sets)
        (open-gripper-if-necessary (arm parameter-set)))
      (cpl:with-failure-handling
          (((or cram-plan-failures:manipulation-failure
              cram-plan-failures:object-lost) (f)
             (declare (ignore f))
             (assume-pregrasp-poses)))
        (moveit:without-collision-object object-name
          (assume-grasp-poses)
          (cpl:par-loop (parameter-set parameter-sets)
            (close-gripper (arm parameter-set) :max-effort (effort parameter-set)))
          (unless (every #'not (mapcar
                                (lambda (parameter-set)
                                  (gripper-closed (arm parameter-set)))
                                parameter-sets))
            (cpl:par-loop (parameter-set parameter-sets)
              (when (gripper-closed (arm parameter-set))
                (open-gripper (arm parameter-set))))
            (cpl:fail 'cram-plan-failures:object-lost)))
        (dolist (parameter-set parameter-sets)
          (let ((link-frame
                  (cut:var-value
                   '?link
                   (first
                    (crs:prolog
                     `(manipulator-link ,(arm parameter-set)
                                        ?link))))))
            (moveit:attach-collision-object-to-link object-name link-frame)))))))

(defmethod parameter-set->pre-putdown-trajectory ((parameter-set putdown-parameters))
  (ros-info (pr2 grasp) "Generating pre-putdown trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (pre-putdown-pose parameter-set)))

(defmethod parameter-set->putdown-trajectory ((parameter-set putdown-parameters))
  (ros-info (pr2 grasp) "Generating putdown trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (putdown-pose parameter-set)))

(defmethod parameter-set->unhand-trajectory ((parameter-set putdown-parameters))
  (ros-info (pr2 grasp) "Generating unhand trajectory")
  (arm-pose->trajectory
   (arm parameter-set) (unhand-pose parameter-set)))

(defun execute-putdowns (object-name parameter-sets)
  (labels ((assume-safe-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->safe-trajectory
                      (cpl:mapcar-clean
                       (lambda (parameter-set)
                         (when (safe-pose parameter-set)
                           parameter-set))
                       parameter-sets))))
           (assume-pre-putdown-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->pre-putdown-trajectory parameter-sets)))
           (assume-putdown-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->putdown-trajectory parameter-sets)))
           (assume-unhand-poses ()
             (moveit:execute-trajectories
              (mapcar #'parameter-set->unhand-trajectory parameter-sets))))
    (cpl:with-failure-handling
        ((cram-plan-failures:manipulation-failure (f)
           (declare (ignore f))
           (assume-safe-poses)))
      (assume-pre-putdown-poses)
      (cpl:with-failure-handling
          ((cram-plan-failures:manipulation-failure (f)
             (declare (ignore f))
             (assume-pre-putdown-poses)))
        (assume-putdown-poses)
        (cram-language:par-loop (param-set parameter-sets)
          (open-gripper (arm param-set)))
        (block unhand
          (cpl:with-failure-handling
              ((cram-plan-failures:manipulation-failure (f)
                 (declare (ignore f))
                 (assume-safe-poses)
                 (return-from unhand)))
            (assume-unhand-poses))))))
  (dolist (param-set parameter-sets)
    (let ((link-frame
            (cut:var-value
             '?link
             (first
              (crs:prolog
               `(manipulator-link ,(arm param-set)
                                  ?link))))))
      (moveit:detach-collision-object-from-link
       object-name link-frame))))

(defun lift-grasped-object-with-one-arm (side distance)
  "Executes a lifting motion with the `side' arm which grasped the
object in order to lift it at `distance' form the supporting plane"
  (let* ((frame-id (cut:var-value
                    '?link
                    (first
                     (crs:prolog
                      `(manipulator-link ,side ?link)))))
         (arm-in-tll (cl-tf2:ensure-pose-stamped-transformed
                      *tf2*
                      (tf:make-pose-stamped frame-id (ros-time)
                                            (tf:make-identity-vector)
                                            (tf:make-identity-rotation))
                      "/torso_lift_link" :use-current-ros-time t))
         (raised-arm-pose
           (tf:copy-pose-stamped
            arm-in-tll
            :origin (tf:v+ (tf:origin arm-in-tll)
                           (tf:make-3d-vector 0 0 distance)))))
            
    (unless raised-arm-pose
      (cpl:fail 'cram-plan-failures:manipulation-pose-unreachable))
    (execute-move-arm-pose side raised-arm-pose :ignore-collisions t)))

(defun lift-grasped-object-with-two-arms (obj-name arms distance)
  (let ((trajectories
          (mapcar (lambda (arm)
                    (let* ((frame-id
                             (ecase arm
                               (:left "l_wrist_roll_link")
                               (:right "r_wrist_roll_link")))
                           (arm-in-tll
                             (cl-tf2:ensure-pose-stamped-transformed
                              *tf2*
                              (tf:make-pose-stamped
                               frame-id (ros-time)
                               (tf:make-identity-vector)
                               (tf:make-identity-rotation))
                              "/torso_lift_link" :use-current-ros-time t))
                           (raised
                             (tf:copy-pose-stamped
                              arm-in-tll
                              :origin
                              (tf:v+ (tf:origin arm-in-tll)
                                     (tf:make-3d-vector 0 0 distance)))))
                      (execute-move-arm-pose
                       arm raised :plan-only t
                       :allowed-collision-objects `(,obj-name))))
                  arms)))
    (moveit::execute-trajectories trajectories)))

(defun relative-pose (pose pose-offset)
  (tf:pose->pose-stamped
   (tf:frame-id pose)
   (ros-time)
   (cl-transforms:transform-pose
    (cl-transforms:pose->transform pose)
    pose-offset)))

(defun register-default-arm-poses ()
  (setf *registered-arm-poses* nil)
  (register-arm-pose-values
   'park-up :left
   (list "l_shoulder_pan_joint" "l_shoulder_lift_joint" "l_upper_arm_roll_joint"
         "l_elbow_flex_joint" "l_forearm_roll_joint" "l_wrist_flex_joint"
         "l_wrist_roll_joint")
   (list 2.1349352742720713d0 -0.3515787802727127d0 0.4053726979454475d0
         -1.935268076613257d0 -8.933192323000247d0 -0.9837825111704411d0
         -2.8312057658851035d0))
  (register-arm-pose-values
   'park-up :right
   (list "r_shoulder_pan_joint" "r_shoulder_lift_joint" "r_upper_arm_roll_joint"
         "r_elbow_flex_joint" "r_forearm_roll_joint" "r_wrist_flex_joint"
         "r_wrist_roll_joint")
   (list -2.1355468854287043d0 -0.3526004879889815d0 -0.32790126674665676d0
         -1.9663937795607156d0 21.50934421706672d0 -0.8279821032327457d0
         34.06996833442799d0))
  (register-arm-pose-values
   'park-front :left
   (list "l_shoulder_pan_joint" "l_shoulder_lift_joint" "l_upper_arm_roll_joint"
         "l_elbow_flex_joint" "l_forearm_roll_joint" "l_wrist_flex_joint"
         "l_wrist_roll_joint")
   (list -0.030171038005611828d0 0.8129549311832104d0 0.03816014555840819d0
         -2.123180459989076d0 -12.555576907844346d0 -0.9193458005029428d0
         -3.1270229136422465d0))
  (register-arm-pose-values
   'park-front :right
   (list "r_shoulder_pan_joint" "r_shoulder_lift_joint" "r_upper_arm_roll_joint"
         "r_elbow_flex_joint" "r_forearm_roll_joint" "r_wrist_flex_joint"
         "r_wrist_roll_joint")
   (list -0.016868278870932896d0 0.9287588122741933d0 -0.020180354942845424d0
         -2.122601377143542d0 18.86567449633915d0 -0.9526351593180957d0
         34.50727649034902d0))
  (register-arm-pose-values
   'park-low :left
   (list "l_shoulder_pan_joint" "l_shoulder_lift_joint" "l_upper_arm_roll_joint"
         "l_elbow_flex_joint" "l_forearm_roll_joint" "l_wrist_flex_joint"
         "l_wrist_roll_joint")
   (list 1.6966908949230448d0 1.2937924741089306d0 2.1740864328052925d0
         -1.880689518421667d0 -11.21641684493887d0 -1.0517869532861077d0
         -3.2655553152393537d0))
  (register-arm-pose-values
   'park-low :right
   (list "r_shoulder_pan_joint" "r_shoulder_lift_joint" "r_upper_arm_roll_joint"
         "r_elbow_flex_joint" "r_forearm_roll_joint" "r_wrist_flex_joint"
         "r_wrist_roll_joint")
   (list -1.7367660559416027d0 1.2964083480861532d0 -2.168133254167471d0
         -1.908340724295921d0 17.52072972473862d0 -1.109876396558022d0
         34.60691191737709d0)))
