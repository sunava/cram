(in-package #:cffi-example)

(define "a0(x)" "+x+x")
(define "a1(x)" "a0(+x+x)")
(define "a2(x)" "a1(+x+x)")
(define "a3(x)" "a2(+x+x)")
(define "a4(x)" "a3(+x+x)")
(define "a5(x)" "a4(+x+x)")

(define "A0" "a0(1)")
(define "A1" "a1(1)")
(define "A2" "a2(1)")
(define "A3" "a3(1)")
(define "A4" "a4(1)")

(constant (+a0+ "A0"))
(constant (+a1+ "A1"))
(constant (+a2+ "A2"))
(constant (+a3+ "A3"))
(constant (+a4+ "A4"))
