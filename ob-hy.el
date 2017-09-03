;;; ob-hy.el --- org-babel functions for Hy evaluation

;; Copyright (C) 2017 Brantou

;; Author: Brantou <brantou89@gmail.com>
;; URL: https://github.com/brantou/ob-hy
;; Keywords: hy, literate programming, reproducible research
;; Homepage: http://orgmode.org
;; Version:  1.0.0

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; Org-Babel support for evaluating hy-script code.
;;
;; It was created based on the usage of ob-template.
;;

;;; Requirements:
;;
;; - hy :: https://hy-lang.org/
;;

;;; TODO
;;
;; - Provide better error feedback.
;;

;;; Code:
(require 'ob)
(require 'ob-eval)

(defvar org-babel-tangle-lang-exts)
(add-to-list 'org-babel-tangle-lang-exts '("hy" . "hy"))

(defvar org-babel-default-header-args:hy '()
  "Default header arguments for hy code blocks.")

(defcustom org-babel-hy-command "hy"
  "Name of command used to evaluate hy blocks."
  :group 'org-babel
  :version "24.4"
  :package-version '(Org . "8.0")
  :type 'string)

(defcustom org-babel-hy-nil-to 'hline
  "Replace nil in hy tables with this before returning."
  :group 'org-babel
  :version "24.4"
  :package-version '(Org . "8.0")
  :type 'symbol)

(defconst org-babel-hy-wrapper-method
  "
(defn main []
%s)

(with [f (open \"%s\" \"w\")] (.write f (str (main))))")

(defconst org-babel-hy-pp-wrapper-method
  "
(import pprint)
(defn main []
%s)

(with [f (open \"%s\" \"w\")] (.write f (.pformat pprint (main))))")

(defun org-babel-expand-body:hy (body params)
  "Expand BODY according to PARAMS, return the expanded body."
  (let* ((vars (org-babel--get-vars params))
         (body (if (null vars) (org-trim body)
                 (concat
                         (mapconcat
                          (lambda (var)
                            (format "(setv %S (quote %S))" (car var) (cdr var)))
                          vars "\n")
                         "\n" body))))
    body))

(defun org-babel-execute:hy (body params)
  "Execute a block of Hy code with org-babel.
 This function is called by `org-babel-execute-src-block'"
  (message "executing Hy source code block")
  (let* ((org-babel-hy-command
          (or (cdr (assq :hy params))
              org-babel-hy-command))
         (result-params (cdr (assq :result-params params)))
         (result-type (cdr (assq :result-type params)))
         (full-body (org-babel-expand-body:hy body params))
         (result (org-babel-hy-evaluate-external-process
                  full-body result-type result-params)))
    (org-babel-reassemble-table
     result
     (org-babel-pick-name (cdr (assq :colname-names params))
                          (cdr (assq :colnames params)))
     (org-babel-pick-name (cdr (assq :rowname-names params))
                          (cdr (assq :rownames params))))))

(defun org-babel-hy-evaluate-external-process
    (body &optional result-type result-params)
  "Evaluate BODY in external hy process.
If RESULT-TYPE equals `output' then return standard output as a
string.  If RESULT-TYPE equals `value' then return the value of the
last statement in BODY, as elisp."
  (let ((result
             (pcase result-type
               (`output (org-babel-eval
                         (format "%s -c '%s'" org-babel-hy-command body) ""))
               (`value (let ((tmp-file (org-babel-temp-file "hy-")))
                         (org-babel-eval
                        (format
                         "%s -c '%s'"
                         org-babel-hy-command
                         (format
                          (if (member "pp" result-params)
                              org-babel-hy-pp-wrapper-method
                            org-babel-hy-wrapper-method)
                          body
                          (org-babel-process-file-name tmp-file 'noquote))) "")
                         (org-babel-eval-read-file tmp-file))))))
    (org-babel-result-cond result-params
      result
      (org-babel-hy-table-or-string result))))

(defun org-babel-prep-session:hy (_session _params)
  "This function does nothing as hy is a compiled language with no
support for sessions"
  (error "Hy is a compiled language -- no support for sessions"))

(defun org-babel-load-session:hy (_session _body _params)
  "This function does nothing as hy is a compiled language with no
support for sessions"
  (error "Hy is a compiled language -- no support for sessions"))

;; helper functions

(defun org-babel-variable-assignments:hy (params)
  "Return list of hy statements assigning the block's variables."
  (mapcar
   (lambda (pair)
     (format "%s=%s"
             (car pair)
             (org-babel-hy-var-to-hy (cdr pair))))
   (org-babel--get-vars params)))

(defun org-babel-hy-var-to-hy (var)
  "Convert VAR into a hy variable.
Convert an elisp value into a string of hy source code
specifying a variable of the same value."
  (if (listp var)
      (concat "[" (mapconcat #'org-babel-hy-var-to-hy var ", ") "]")
    (if (eq var 'hline)
        org-babel-hy-hline-to
      (format "%S" var))))

(defun org-babel-hy-table-or-string (results)
  "Convert RESULTS into an appropriate elisp value.
If RESULTS look like a table, then convert them into an
Emacs-lisp table, otherwise return the results as a string."
  (let ((res (org-babel-script-escape results)))
    (if (listp res)
        (mapcar (lambda (el) (if (not el)
                                 org-babel-hy-nil-to el))
                res)
      res)))

(defun org-babel-hy-read (results)
  "Convert RESULTS into an appropriate elisp value.
If RESULTS look like a table, then convert them into an
Emacs-lisp table, otherwise return the results as a string."
  (org-babel-read
   (if (and (stringp results)
            (string-prefix-p "[" results)
            (string-suffix-p "]" results))
       (org-babel-read
        (concat "'"
                (replace-regexp-in-string
                 "\\[" "(" (replace-regexp-in-string
                            "\\]" ")" (replace-regexp-in-string
                                       ",[[:space:]]" " "
                                       (replace-regexp-in-string
                                        "'" "\"" results))))))
     results)))

(provide 'ob-hy)
;;; ob-hy.el ends here