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

(in-package :bt-vis)

(defclass event-queue ()
  ((event-queue :initform (cons nil nil) :reader event-queue)
   (events-lock :initform (sb-thread:make-mutex) :reader events-lock)
   (events-condition :initform (sb-thread:make-waitqueue) :reader events-condition)))

(defgeneric post-event (queue event)
  (:documentation "Posts an event into the event queue. `event' must
  be a list with the event identifier in the car. The rest is
  interpreted as event parameters."))

(defgeneric get-next-event (queue &optional timeout)
  (:documentation "Returns the next event from the queue. If `timeout'
  is set, waits at most `timeout' seconds."))

(defmethod post-event ((queue event-queue) event)
  (sb-thread:with-mutex ((events-lock queue))
    (let ((new-cons (cons event nil)))
      (if (consp (cdr (event-queue queue)))
          (setf (cdr (cdr (event-queue queue)))
                new-cons)
          (setf (car (event-queue queue))
                new-cons))
      (setf (cdr (event-queue queue))
            new-cons))
    (sb-thread:condition-broadcast (events-condition queue))))

(defmethod get-next-event ((queue event-queue) &optional timeout)
  (flet ((dequeue-event ()
           (loop until (car (event-queue queue)) do
             (sb-thread:condition-wait
              (events-condition queue)
              (events-lock queue)))
           (prog1 (caar (event-queue queue))
             (setf (car (event-queue queue))
                   (cdar (event-queue queue)))
             (unless (car (event-queue queue))
               (setf (cdr (event-queue queue)) nil)))))
    (sb-thread:with-mutex ((events-lock queue))
      (if timeout
          (sb-ext:with-timeout timeout
              (handler-case (dequeue-event)
                (sb-ext:timeout (c)
                  (declare (ignore c))
                  nil)))
          (dequeue-event)))))
