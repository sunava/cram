;;; Copyright (c) 2012, Lorenz Moesenlechner <moesenle@in.tum.de>
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

(in-package :designators-ros)

(register-location-validation-function 1 filter-solution)

(defvar *filter-functions* nil)

(defmacro with-designator-solution-filter (filter &body body)
  "Executes `body' with a filter function added to the location
designator resolution mechanism. To validate a designator solution
inside `body', all filters have to return T. `filter' must be a
function that takes exactly one parameter, the solution."
  `(let ((*filter-functions* (cons ,filter *filter-functions*)))
     ,@body))

(defun filter-solution (designator solution)
  (declare (ignore designator))
  (cond ((not *filter-functions*)
         :unknown)
        ((every (lambda (function)
                  (funcall function solution))
                *filter-functions*)
         :accept)))

(defun next-filtered-designator-solution (designator filter)
  (with-designator-solution-filter filter
    (next-solution designator)))

(defun make-euclidean-distance-filter (pose distance-threshold)
  "Filters (i.e. removes) all solutions that are closer than
`distance-threshold' to `pose'."
  (lambda (solution)
    (> (cl-transforms:v-dist
        (cl-transforms:origin pose) (cl-transforms:origin solution))
       distance-threshold)))
