(desig-props:def-desig-package bullet-reasoning-interface
  (:nicknames :reas-inf :btri)
  (:use
   #:cram-designators
   #:roslisp
   #:btr
   #:cpl)
  (:shadowing-import-from #:btr object pose object-pose width height)
  (:import-from #:cram-prolog prolog force-ll)
  (:import-from #:cram-roslisp-common *fixed-frame* *tf-default-timeout*)
  (:export init-interface start-service)
  (:desig-properties
   ;;;object properties
   ;;   #:mondamin
   ;;   #:fruit-orange
   ;;   #:fruit-apple
   ;;   #:bowl
   ;;   #:nesquik
   ;;   #:sugar
   ))
