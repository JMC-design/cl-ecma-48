;CL-ECMA-48 - Provide for emitting ECMA-48 control functions.
;Copyright 2017,2018,2019 Prince Trippy programmer@verisimilitudes.net .

;This program is free software: you can redistribute it and/or modify
;it under the terms of the GNU Affero General Public License version 3
;as published by the Free Software Foundation

;This program is distributed in the hope that it will be useful,
;but WITHOUT ANY WARRANTY; without even the implied warranty of
;MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;GNU Affero General Public License for more details.

;You should have received a copy of the GNU Affero General Public License
;along with this program.  If not, see <http://www.gnu.org/licenses/>.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((string (mapcar 'code-char (loop for i from 0 to 127 collecting i))))
    (or (every 'identity string)
        (error "This Common Lisp implementation does not supply characters for all character codes 0 to 127, inclusive.
Due to this, CL-ECMA-48 will not function entirely correctly.
It is possible to continue, but any function using NIL rather than a character will probably signal an error."))
    (and (equal (coerce (subseq string 32 127) 'string)
                " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
         (every 'digit-char-p (subseq string #x30 #x3A))
         (notany 'graphic-char-p (subseq string 0 32))
         (not (graphic-char-p (elt string 127)))
         (pushnew :ascii *features*))))

(cl:defpackage #:cl-ecma-48
  (:documentation "This package exports a macro for defining ECMA-48 control functions and the 162 functions defined by this.")
  (:use #:common-lisp)
  (:shadow #:null #:substitute #:ed #-ascii #:princ)
  (:export #:define-control-function)
  (:nicknames #:ecma-48))

(cl:in-package #:cl-ecma-48)

#-ascii
(defun princ (value &optional (stream *standard-output*) &aux (*standard-output* stream))
  "Print the decimal representation of value to stream using characters #x30 to #x39, if it is an integer.
The normal PRINC behavior takes place, otherwise."
  (if (integerp value)
      (write-string (map 'string (lambda (c)
                                   (code-char (+ #x30 (digit-char-p c))))
                         (princ-to-string value)))
      (cl:princ value))
  value)

(defmacro defc0 (symbol character &optional documentation)
  "Define an emitter for a control function belonging to the C0 set."
  `(defun ,symbol (&optional (stream *standard-output*) &aux (*standard-output* stream))
     ,@(if documentation `(,documentation))
     (declare (ignorable stream))
     (write-char ,(if (characterp character) character (code-char character)))
     (values)))

(defmacro defc1 (symbol character &optional documentation)
  "Define an emitter for a control function belonging to the C1 set."
  `(defun ,symbol (&optional (stream *standard-output*) &aux (*standard-output* stream))
     ,@(if documentation `(,documentation))
     (declare (ignorable stream))
     (write-string ,(format nil "~c~c" (code-char #x1B) (if (characterp character) character (code-char character))))
     (values)))

(defmacro deffs (symbol character &optional documentation)
  "Define an emitter for an independent control function belonging to the Fs set."
  `(defc1 ,symbol ,character ,documentation))

(defmacro defcs (symbol lambda-list characters &optional documentation
                 &aux (&o (position '&optional lambda-list)) (optional (if &o (subseq lambda-list &o)))
                      (&r (position '&rest lambda-list)) (rest (if &r (subseq lambda-list &r)))
                      (required (subseq lambda-list 0 (or &o &r))))
  "Define an emitter for a control function that is a control sequence."
  (if (intersection lambda-list (set-difference lambda-list-keywords '(&optional &rest)))
      (error "Invalid lambda-list keywords have been used.
Only &OPTIONAL and &REST are permitted."))
  (if (notevery (lambda (e) (or (symbolp e)
                                (and (listp e)
                                     (symbolp (car e))
                                     (consp (cdr e))
                                     (cl:null (cddr e)))))
                lambda-list)
      (error "Invalid lambda-list elements have been used.
Only symbols and lists of length two starting with symbols are permitted."))
  `(defun ,symbol ,(append required (cond (&o optional)
                                        (&r (if (symbolp (cadr rest))
                                                `(,(cadr rest) &optional)
                                                `(&optional ,(cadr rest))))
                                        (t '(&optional)))
                         '((stream *standard-output*) &aux (*standard-output* stream) (*print-base* 10) *print-radix*))
     ,@(if documentation `(,documentation))
     (declare (ignorable stream))
     ,@(loop for elt in required collecting `(check-type ,elt (or unsigned-byte character)))
     ,@(cond (&o (loop for elt in (cdr optional) collecting `(check-type ,(if (listp elt) (car elt) elt) (or cl:null unsigned-byte character))))
             (&r `((check-type ,(if (listp (cadr rest)) (caadr rest) (cadr rest)) (or list unsigned-byte character)))))
     (control-sequence-introducer)
     ,@(nconc (mapcon (lambda (n)
                        `((princ ,(car n))
                          ,@(if (cdr n)
                                (list `(write-char ,(code-char #x3B))))))
                      required)
              (cond (&o (append (if (not required)
                                    (let ((a (if (symbolp (cadr optional))
                                                 (cadr optional)
                                                 (caadr optional))))
                                      `((or (cl:null ,a)
                                            ,@(if (not (symbolp (cadr optional)))
                                                  `((eql ,(caadr optional) ,(cadadr optional))))
                                            (princ ,a)))))
                                (cond ((butlast (cddr optional))
                                       (let ((g (mapcar (lambda (n &aux (s (if (symbolp n) n (car n)))
                                                                        (v (if (not (symbolp n)) (cadr n))))
                                                          (list s v (gensym (symbol-name s))))
                                                        (if required
                                                            (cdr optional)
                                                            (cddr optional)))))
                                         `((let ,(mapcar (lambda (s)
                                                           `(,(caddr s)
                                                              (or (cl:null ,(car s))
                                                                  ,@(if (cadr s) `((eql ,(car s) ,(cadr s)))))))
                                                         g)
                                             (declare (type boolean ,@(mapcar 'caddr g))
                                                      (dynamic-extent ,@(mapcar 'caddr g)))
                                             ,@(mapcon (lambda (n)
                                                         (if (cdr n)
                                                             `((or (and ,@(mapcar 'caddr n))
                                                                   (write-char ,(code-char #x3B)))
                                                               (or ,(caddar n) (princ ,(caar n))))
                                                             `((or ,(caddar n)
                                                                   (progn (write-char ,(code-char #x3B))
                                                                          (princ ,(caar n)))))))
                                                       g)))))
                                      ((or required (cddr optional))
                                       (let* ((l (car (last optional)))
                                              (a (if (symbolp l) l (car l))))
                                         `((or (cl:null ,a)
                                               ,@(if (not (symbolp l))
                                                     `((eql ,(car l) ,(cadr l))))
                                               (progn (write-char ,(code-char #x3B))
                                                      (princ ,a)))))))))
                    (&r `(,@(if required `((if ,(if (symbolp (cadr rest))
                                                    (cadr rest)
                                                    (caadr rest))
                                               (write-char ,(code-char #x3B)))))
                            (if (listp ,(if (symbolp (cadr rest))
                                            (cadr rest)
                                            (caadr rest)))
                                (mapl (lambda (list &aux (elt (car list)))
                                        (or (cl:null elt)
                                            ,@(if (not (symbolp (cadr rest)))
                                                  `((eql elt ,(cadadr rest))))
                                            (princ elt))
                                        (if (cdr list) (write-char ,(code-char #x3B))))
                                      ,(if (symbolp (cadr rest))
                                           (cadr rest)
                                           (caadr rest)))
                                (or (cl:null ,(if (symbolp (cadr rest))
                                                  (cadr rest)
                                                  (caadr rest)))
                                    ,@(if (not (symbolp (cadr rest)))
                                          `((eql ,(if (symbolp (cadr rest))
                                                      (cadr rest)
                                                      (caadr rest))
                                                 ,(cadadr rest))))
                                    (princ ,(if (symbolp (cadr rest))
                                                (cadr rest)
                                                (caadr rest)))))))))
     ,(typecase characters
        (character `(write-char ,characters))
        (integer `(write-char ,(code-char characters)))
        (t `(write-string ,(make-array (length characters) :element-type 'character
                                       :initial-contents (mapcar (lambda (n)
                                                                   (if (characterp n) n (code-char n)))
                                                                 characters)))))
     (values)))

(defmacro define-control-function (identity type sequence &optional documentation)
  "Define an ECMA-48 control function emitting function.
The identity is a symbol or a list of two symbols, acronym and proper name.
The type is one of :C0, :C1, :Fs, or a modified lambda list containing required, &OPTIONAL, and &REST arguments.
All non-required arguments may be given a default value according to normal &OPTIONAL convention.
The sequence is the value designating the control function.
The optional documentation is a documentation string for this function."
  (check-type identity (or list symbol))
  (check-type type (or list (member :C0 :C1 :Fs)))
  (check-type sequence (or character sequence unsigned-byte))
  (check-type documentation (or cl:null string))
  (let ((acronym (if (symbolp identity) identity (first identity)))
        (name (if (symbolp identity) identity (second identity))))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (,(getf '(:C0 defc0 :C1 defc1 :Fs deffs) type 'defcs)
         ,name ,@(if (listp type) `(,type)) ,sequence ,documentation)
       (setf (symbol-function ',acronym) (symbol-function ',name)
             (documentation ',acronym 'function) ,documentation
             (get ',acronym :expansion) ',name
             (get ',name :acronym) ',acronym))))

#.`(progn
     ,@(mapcan
        (lambda (d)
          `((define-control-function ,@d)
            (export ',(car d))))
        '(((ack acknowledge) :C0 #x06 "Acknowledge with affirmative response.  See ISO 1745.")
          ((apc application-program-command) :C1 #x5F "Begins a command string delimited by STRING TERMINATOR (ST).")
          ((bel bell) :C0 #x07 "Bell typically sounds or flashes the device for attention.")
          ((bph break-permitted-here) :C1 #x42 "Indicates a line break is permitted between two graphical characters.")
          ((bs backspace) :C0 #x08 "Backspace, moving in the reverse of the normal data movement.")
          ((can cancel) :C0 #x18 "Cancel previous data by signalling according to an external protocol.")
          ((csi control-sequence-introducer) :C1 #x5B "Introduce a control sequence.") ;Violate the order for niceties.
          ((cbt cursor-backward-tabulation) (&optional (count 1)) #x5A "Move the cursor to the nth preceding character tabstop.")
          ((cch cancel-character) :C1 #x54 "Ignore the preceding graphical character and this control function.")
          ((cha cursor-character-absolute) (&optional (count 1)) #x47 "Move the cursor to the nth position of the current line.")
          ((cht cursor-forward-tabulation) (&optional (count 1)) #x49 "Move the cursor to the nth following character tabstop.")
          ((cmd coding-method-delimiter) :Fs #x64 "Delimit a string of data and switch control.  See ECMA-35.")
          ((cnl cursor-next-line) (&optional (count 1)) #x45 "Move the cursor to the first position of the nth following line.")
          ((cpl cursor-preceding-line) (&optional (count 1)) #x46 "Move the cursor to the first position of the nth preceding line.")
          ((cpr active-position-report) (&optional (line 1) (character 1)) #x52 "Reports current line and character position.")
          ((cr carriage-return) :C0 #x0D "Carriage return moves to the home or limit position of a line.")
          ((ctc cursor-tabulation-control) (&rest (tabstops 0)) #x57 "Modify tabstops according to parameters.  See ECMA-48.")
          ((cub cursor-left) (&optional (count 1)) #x44 "Move the cursor left count times.")
          ((cud cursor-down) (&optional (count 1)) #x42 "Move the cursor down count times.")
          ((cuf cursor-right) (&optional (count 1)) #x43 "Move the cursor right count times.")
          ((cup cursor-position) (&optional (line 1) (character 1)) #x48 "Reposition the cursor at line and character.")
          ((cuu cursor-up) (&optional (count 1)) #x41 "Move the cursor up count times.")
          ((cvt cursor-line-tabulation) (&optional (count 1)) #x59 "Move the cursor to the nth following line tabstop.")
          ((da device-attributes) (&optional (n 0)) #x63 "If n is zero, request a DA; if not, self identify with n.")
          ((daq define-area-qualification) (&rest (n 0)) #x6F "Define a qualified area according to parameters.  See ECMA-48.")
          ((dch delete-character) (&optional (count 1)) #x50 "Remove the current and count-1 following or preceding characters.")
          ((dcs device-control-string) :C1 #x50 "Begin a control string delimited by STRING TERMINATOR (ST).")
          ((dc1 device-control-one) :C0 #x11 "Device control one is used for primary device control.  See ECMA-48.")
          ((dc2 device-control-two) :C0 #x12 "Device control two is used for secondary device control.  See ECMA-48.")
          ((dc3 device-control-three) :C0 #x13 "Device control three is used for tertiary device control.  See ECMA-48.")
          ((dc4 device-control-four) :C0 #x14 "Device control four is used for miscellaneous device control.  See ECMA-48.")
          ((dl delete-line) (&optional (count 1)) #x4D "Remove the current and count-1 following or preceding lines.")
          ((dle data-link-escape) :C0 #x10 "Data link escape provides transmission control functions.  See ISO 1745.")
          ((dmi disable-manual-input) :Fs #x60 "Disable the manual input facilities of a device.")
          ((dsr device-status-report) (&optional (n 0)) #x6E "Report or request a status.  A 6 requests a CPR.  See ECMA-48.")
          ((dta dimension-text-area) (m n) (#x20 #x54) "Establish rectangular text dimensions.")
          ((ea erase-in-area) (&optional (n 0)) #x4F "Erase a section of the current qualified area.  See ECMA-48.")
          ((ech erase-character) (&optional (count 1)) #x58 "Erase the current and count-1 following characters.")
          ((ed erase-in-page) (&optional (n 0)) #x4A "Erase a section of the current page.  See ECMA-48.")
          ((ef erase-in-field) (&optional (n 0)) #x4E "Erase a section of the current field.  See ECMA-48.")
          ((el erase-in-line) (&optional (n 0)) #x4B "Erase a section of the current line.  See ECMA-48.")
          ((em end-of-medium) :C0 #x19 "End of medium is used to identify the end of a medium for access.")
          ((emi enable-manual-input) :Fs #x62 "Enable the manual input facilities of a device.")
          ((enq enquiry) :C0 #x05 "Enquiry is used as a request for response.  See ISO 1745.")
          ((eot end-of-transmission) :C0 #x04 "End of transmission indicates a finishing.  See ISO 1745.")
          ((epa end-of-guarded-area) :C1 #x57 "Indicate the end of a guarded area.  See ECMA-48.")
          ((esa end-of-selected-area) :C1 #x47 "Indicate the end of a selected area.  See ECMA-48.")
          ((esc escape) :C0 #x1B "Escape causes following characters to be interpreted differently.  See ECMA-35.")
          ((etb end-of-transmission-block) :C0 #x17 "End of transmission block indicates the end of a block.  See ISO 1745.")
          ((etx end-of-text) :C0 #x03 "End of text indicates the end of a text.  See ISO 1745.")
          ((ff form-feed) :C0 #x12 "Form feed breaks a form or page.")
          ((fnk function-key) (n) (#x20 #x57) "Indicate the nth function key.")
          ((fnt font-selection) (&optional (font 0) (register 0)) (#x20 #x44) "Select a font.  See ECMA-48.")
          ((gcc graphic-character-combination) (&optional (n 0)) (#x20 #x5F) "Combine graphic characters.  See ECMA-48.")
          ((gsm graphic-size-modification) (&optional (height 100) (width 100)) (#x20 #x42) "Modify font size.  See ECMA-48.")
          ((gss graphic-size-selection) (height) (#x20 #x43) "Establish font height, and implicitly width, in terms of SSU.")
          ((hpa character-position-absolute) (&optional (count 1)) #x60 "Move to the nth position of the current line.  See CHA.")
          ((hpb character-position-backward) (&optional (count 1)) #x6A "Move opposite of the normal data movement count times.  See BS.")
          ((hpr character-position-forward) (&optional (count 1)) #x61 "Move with the normal data movement count times.")
          ((ht character-tabulation) :C0 #x09 "Character tabulation moves to the following character tabstop.")
          ((htj character-tabulation-with-justification) :C1 #x49 "Justify with regards to the following tabstop.  See ECMA-48.")
          ((hts character-tabulation-set) :C1 #x48 "Set a tabstop.")
          ((hvp character-and-line-position) (&optional (line 1) (character 1)) #x66 "Move to line and character.  See CUP.")
          ((ich insert-character) (&optional (count 1)) #x40 "Insert room at the current and count-1 following or preceding characters.")
          ((idcs identify-device-control-string) (string) (#x20 #x4F) "Define the structure of a control string.  See ECMA-35.  See ECMA-48.")
          ((igs identify-graphic-subrepertoire) (repertoire) (#x20 #x4D) "See ISO 7350.  See ISO 10367.  See ECMA-48.")
          ((il insert-line) (&optional (count 1)) #x4C "Insert a line at the current and count-1 following or preceding lines.")
          ((int interrupt) :Fs #x61 "Alert a device to stop and begin an already agreed upon execution.")
          ((is1 information-separator-one) :C0 #x1F "Information separator one can be used to organize units.  See ECMA-48.")
          ((is2 information-separator-two) :C0 #x1E "Information separator two can be used to organize records.  See ECMA-48.")
          ((is3 information-separator-three) :C0 #x1D "Information separator three can be used to organize groups.  See ECMA-48.")
          ((is4 information-separator-four) :C0 #x1C "Information separator four can be used to organize files.  See ECMA-48.")
          ((jfy justify) (&rest (n 0)) (#x20 #x46) "Delimit and define justification of a string.  See ECMA-48.")
          ((lf line-feed) :C0 #x0A "Line feed moves to the corresponding position of the following line.")
          ((ls0 locking-shift-zero) :C0 #x0F "Locking shift zero is an extension control function.  See ECMA-35.")
          ((ls1 locking-shift-one) :C0 #x0E "Locking shift one is an extension control function.  See ECMA-35.")
          ((ls1r locking-shift-one-right) :Fs #x7E "See ECMA-35.")
          ((ls2 locking-shift-two) :Fs #x6E "See ECMA-35.")
          ((ls2r locking-shift-two-right) :Fs #x7D "See ECMA-35.")
          ((ls3 locking-shift-three) :Fs #x6F "See ECMA-35.")
          ((ls3r locking-shift-three-right) :Fs #x7C  "See ECMA-35.")
          ((mc media-copy) (&optional (n 0)) #x69 "Begin or end transfer of data to an auxiliary device.  See ECMA-48.")
          ((mw message-waiting) :C1 #x55 "Indicate that a message is waiting.  A response can be sent with DSR.")
          ((nak negative-acknowledge) :C0 #x15  "Negative acknowledge gives a negative response.  See ISO 1745.")
          ((nbh no-break-here) :C1 #x43 "Indicates a line break is not permitted between two graphical characters.")
          ((nel next-line) :C1 #x45 "Move to the home or limit position of the following line.  See CNL.")
          ((np next-page) (&optional (count 1)) #x55 "Display the nth following page.")
          ((nul null) :C0 #x00 "Null is a control function that may be added or removed with little or no consequence.")
          ((osc operating-system-command) :C1 #x5D "Begins an operating system command string delimited by STRING TERMINATOR (ST).")
          ((pec presentation-expand-or-contract) (&optional (spacing 0)) (#x20 #x5A) "Controls spacing and size of text.  See ECMA-48.")
          ((pfs page-format-selection) (&optional (n 0)) (#x20 #x4A) "Specify page size and format based on paper.  See ECMA-48.")
          ((pld partial-line-forward) :C1 #x4B "Move forward by a partial line to allow for subscripts or return to the active line.")
          ((plu partial-line-backward) :C1 #x4C "Move backwards by a partial line to allow for superscripts or return to the active line.")
          ((pm privacy-message) :C1 #x5E "Begins a privacy message command string delimited by STRING TERMINATOR (ST).")
          ((pp preceding-page) (&optional (count 1)) #x56 "Display the nth preceding page.")
          ((ppa page-position-absolute) (&optional (count 1)) (#x20 #x50) "Move to the corresponding position of the nth page.")
          ((ppb page-position-backward) (&optional (count 1)) (#x20 #x52) "Move to the corresponding position of the nth preceding page.")
          ((ppr page-position-forward) (&optional (count 1)) (#x20 #x51) "Move to the corresponding position of the nth following page.")
          ((ptx parallel-texts) (&optional (n 0)) #x5C "Delimit a string of characters to be displayed in parallel.  See ECMA-48.")
          ((pu1 private-use-one) :C1 #x51 "This control function has no standard behavior and is intended for private use as wanted.")
          ((pu2 private-use-two) :C1 #x52 "This control function has no standard behavior and is intended for private use as wanted.")
          (quad (&rest (n 0)) (#x20 #x48) "Position string with layout as specified.  See ECMA-48.")
          ((rep repeat) (&optional (count 1)) #x62 "Repeat the preceding graphic character count times.")
          ((ri reverse-line-feed) :C1 #x4D "Moves to the corresponding position of the preceding line.")
          ((ris reset-to-initial-state) :Fs #x63 "Reset the device to its initial state.")
          ((rm reset-mode) (&rest n) #x6C "Reset the device as specified.  See ECMA-48.")
          ((sacs set-additional-character-separation) (&optional (n 0)) (#x20 #x5C) "Works in terms of SSU.  See ECMA-48.")
          ((sapv select-alternative-presentation-variants) (&rest (n 0)) (#x20 #x5D) "See ECMA-48.")
          ((sci single-character-introducer) :C1 #x5A "The following character is consumed.  See ECMA-48.")
          ((sco select-character-orientation) (&optional (rotation 0)) (#x20 #x65) "Establish character rotation.  See ECMA-48.")
          ((scp select-character-path) (path effect) (#x20 #x6B) "Establish character direction.  See ECMA-48.")
          ((scs set-character-spacing) (spacing) (#x20 #x67) "Establish character spacing in terms of SSU.  See ECMA-48.")
          ((sd scroll-down) (&optional (count 1)) #x54 "Move the contents of the device down count positions, appearing to scroll down.")
          ((sds start-directed-string) (&optional (n 0)) #x5D "Delimit a string of characters of a certain direction.  See ECMA-48.")
          ((see select-editing-extent) (&optional (extent 0)) #x51 "Establish editing bounds.  See ECMA-48.")
          ((sef sheet-eject-and-feed) (&optional (m 0) (n 0)) (#x20 #x59) "Control paper feeding and ejecting during printing.  See ECMA-48.")
          ((sgr select-graphic-rendition) (&rest (n 0)) #x6D "Establish character font and other characteristics.  See ECMA-48.")
          ((shs select-character-spacing) (&optional (spacing 0)) (#x20 #x4B) "Establish character spacing.  See ECMA-48.")
          ((si shift-in) :C0 #x0F "Shift in causes following characters to be interpreted differently.  See ECMA-35.")
          ((simd select-implicit-movement-direction) (&optional (direction 0)) #x5E "Establish the implicit movement direction.  See ECMA-48.")
          ((sl scroll-left) (&optional (count 1)) (#x20 #x40) "Move the contents of the device left count positions, appearing to scroll left.")
          ((slh set-line-home) (n) (#x20 #x55) "Establish position n of the active line as the line home.")
          ((sll set-line-limit) (n) (#x20 #x56) "Establish position n of the active line as the line limit.")
          ((sls set-line-spacing) (n) (#x20 #x68) "Establish line spacing in terms of SSU.")
          ((sm set-mode) (&rest n) #x68 "Set the device as specified.  See ECMA-48.")
          ((so shift-out) :C0 #x0E "Shift out causes following characters to be interpreted differently.  See ECMA-35.")
          ((soh start-of-heading) :C0 #x01 "Start of heading begins a heading.  See ISO 1745.")
          ((sos start-of-string) :C1 #x58 "Begins a string delimited by STRING TERMINATOR (ST).")
          ((spa start-of-guarded-area) :C1 #x56 "Indicate the beginning of a guarded area.")
          ((spd select-presentation-directions) (&optional (character 0) (effect 0)) (#x20 #x53) "See ECMA-48.")
          ((sph set-page-home) (n) (#x20 #x69) "Establish line position n of the active page as the page home.")
          ((spi spacing-increment) (line character) (#x20 #x47) "Establish line and character spacing in terms of SSU.")
          ((spl set-page-limit) (n) (#x20 #x6A) "Establish line position n of the active page as the page limit.")
          ((spqr select-print-quality-and-rapidity) (&optional (n 0)) (#x20 #x58) "Control speed and quality during printing.  See ECMA-48.")
          ((sr scroll-right) (&optional (count 1)) (#x20 #x41) "Move the contents of the device right count positions, appearing to scroll right.")
          ((srcs set-reduced-character-separation) (&optional (n 0)) (#x20 #x66) "Establish character separation in terms of SSU.")
          ((srs start-reversed-string) (&optional (n 0)) #x5B "Delimit a string of characters of a certain reversed direction.  See ECMA-48.")
          ((ssa start-of-selected-area) :C1 #x46 "Indicate the beginning of a selected area.")
          ((ssu select-size-unit) (&optional (unit 0)) (#x20 #x49) "Define the size unit from several visual units.  See ECMA-48.")
          ((ssw set-space-width) (n) (#x20 #x5B) "Establish space width in terms of SSU.")
          ((ss2 single-shift-two) :C1 #x4E "Cause following characters to be interpreted differently.  See ECMA-35.")
          ((ss3 single-shift-three) :C1 #x4F "Cause following characters to be interpreted differently.  See ECMA-35.")
          ((st string-terminator) :C1 #x5C "Terminate a string.")
          ((stab selective-tabulation) (n) (#x20 #x5E) "Align according to tabulation specified.  See ISO 8613-6.")
          ((sts set-transmit-state) :C1 #x53 "Establish that data transmission is possible.  See ECMA-48.")
          ((stx start-of-text) :C0 #x02 "Start of text begins a text and ends a heading.  See ISO 1745.")
          ((su scroll-up) (&optional (count 1)) #x53 "Move the contents of the device up count positions, appearing to scroll up.")
          ((sub substitute) :C0 #x1A "Substitute for a character that is not to actually be sent.")
          ((svs select-line-spacing) (&optional (spacing 0)) (#x20 #x4C) "Establish line spacing from several visual units.  See ECMA-48.")
          ((syn synchronous-idle) :C0 #x16 "Synchronous idle is used for synchronizing purposes.  See ISO 1745.")
          ((tac tabulation-aligned-centred) (n) (#x20 #x62) "Establish a tabstop used for center alignment.  See ECMA-48.")
          ((tale tabulation-aligned-leading-edge) (n) (#x20 #x61) "Establish a tabstop used for end alignment.  See ECMA-48.")
          ((tate tabulation-aligned-trailing-edge) (n) (#x20 #x60) "Establish a tabstop used for front alignment.  See ECMA-48.")
          ((tbc tabulation-clear) (&optional (n 0)) #x67 "Clear tabstops as specified.  See ECMA-48.")
          ((tcc tabulation-centered-on-character) (line &optional (character 32)) (#x20 #x63) ;oh my
           "Establish a tabstop used for center alignment of the first occurence of character or for front alignment.  See ECMA-48.")
          ((tsr tabulation-stop-remove) (n) (#x20 #x64) "Remove a tabstop at position n of the active line and following lines.")
          ((tss thin-space-specification) (n) (#x20 #x45) "Establish thin space width in terms of SSU.")
          ((vpa line-position-absolute) (&optional (count 1)) #x64 "Move to the nth line position.")
          ((vpb line-position-backward) (&optional (count 1)) #x6B "Move opposite of the normal line progression count times.")
          ((vpr line-position-forward) (&optional (count 1))  #x65 "Move with the normal line progression count times.")
          ((vt line-tabulation) :C0 #x0B "Line tabulation moves to the following tabstop.")
          ((vts line-tabulation-set) :C1 #x4A "Set a line tabstop at the active line."))))
