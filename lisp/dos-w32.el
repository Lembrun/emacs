;;; dos-w32.el --- Functions shared among MS-DOS and W32 (NT/95) platforms

;; Copyright (C) 1996 Free Software Foundation, Inc.

;; Maintainer: Geoff Voelker (voelker@cs.washington.edu)
;; Keywords: internal

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Parts of this code are duplicated functions taken from dos-fns.el
;; and winnt.el.

;;; Code:

;;; Add %t: into the mode line format just after the open-paren.
(let ((tail (member "   %[(" mode-line-format)))
  (setcdr tail (cons (purecopy "%t:")
		     (cdr tail))))

;; Use ";" instead of ":" as a path separator (from files.el).
(setq path-separator ";")

;; Set the null device (for compile.el).
(setq grep-null-device "NUL")

;; Set the grep regexp to match entries with drive letters.
(setq grep-regexp-alist
  '(("^\\(\\([a-zA-Z]:\\)?[^:( \t\n]+\\)[:( \t]+\\([0-9]+\\)[:) \t]" 1 3)))

;; For distinguishing file types based upon suffixes.
(defvar file-name-buffer-file-type-alist
  '(
    ("[:/].*config.sys$" . nil)		; config.sys text
    ("\\.elc$" . t)			; emacs stuff
    ("\\.\\(obj\\|exe\\|com\\|lib\\|sys\\|chk\\|out\\|bin\\|ico\\|pif\\)$" . t)
					; MS-Dos stuff
    ("\\.\\(arc\\|zip\\|pak\\|lzh\\|zoo\\)$" . t)
					; Packers
    ("\\.\\(a\\|o\\|tar\\|z\\|gz\\|taz\\)$" . t)
					; Unix stuff
    ("\\.tp[ulpw]$" . t)
					; Borland Pascal stuff
    ("[:/]tags$" . t)
					; Emacs TAGS file
    )
  "*Alist for distinguishing text files from binary files.
Each element has the form (REGEXP . TYPE), where REGEXP is matched
against the file name, and TYPE is nil for text, t for binary.")

;; Return the pair matching filename on file-name-buffer-file-type-alist,
;; or nil otherwise.
(defun find-buffer-file-type-match (filename)
  (let ((alist file-name-buffer-file-type-alist)
	(found nil))
    (let ((case-fold-search t))
      (setq filename (file-name-sans-versions filename))
      (while (and (not found) alist)
	(if (string-match (car (car alist)) filename)
	    (setq found (car alist)))
	(setq alist (cdr alist)))
      found)))

(defun find-buffer-file-type (filename)
  ;; First check if file is on an untranslated filesystem, then on the alist.
  (if (untranslated-file-p filename)
      t ; for binary
    (let ((match (find-buffer-file-type-match filename))
	  (code))
      (if (not match)
	  default-buffer-file-type
	(setq code (cdr match))
	(cond ((memq code '(nil t)) code)
	      ((and (symbolp code) (fboundp code))
	       (funcall code filename)))))))

(defun find-buffer-file-type-coding-system (command args)
  "Choose a coding system for a file operation.
If COMMAND is 'insert-file-contents', the coding system is chosen based
upon the filename, the contents of 'untranslated-filesystem-list' and
'file-name-buffer-file-type-alist', and whether the file exists:

  If it matches in 'untranslated-filesystem-list':	'no-conversion'
  If it matches in 'file-name-buffer-file-type-alist':
    If the match is t (for binary):			'no-conversion'
    If the match is nil (for text):			'emacs-mule-dos'
  Otherwise:
    If the file exists:					'undecided'
    If the file does not exist:				'emacs-mule-dos'

If COMMAND is 'write-region', the coding system is chosen based
upon the value of 'buffer-file-type': If t, the coding system is
'no-conversion', otherwise it is 'emacs-mule-dos'."
  (let ((op (nth 0 command))
	(target)
	(binary)
	(undecided nil))
    (cond ((eq op 'insert-file-contents) 
	   (setq target (nth 1 command))
	   (setq binary (find-buffer-file-type target))
	   (if (not binary)
	       (setq undecided 
		     (and (file-exists-p target)
			  (not (find-buffer-file-type-match target))))))
	  ((eq op 'write-region) 
	   (setq binary buffer-file-type)))
    (cond (binary '(no-conversion . no-conversion))
	  (undecided '(undecided . undecided))
	  (t '(emacs-mule-dos . emacs-mule-dos)))))

(modify-coding-system-alist 'file "" 'find-buffer-file-type-coding-system)

(defun find-file-binary (filename) 
  "Visit file FILENAME and treat it as binary."
  (interactive "FFind file binary: ")
  (let ((file-name-buffer-file-type-alist '(("" . t))))
    (find-file filename)))

(defun find-file-text (filename) 
  "Visit file FILENAME and treat it as a text file."
  (interactive "FFind file text: ")
  (let ((file-name-buffer-file-type-alist '(("" . nil))))
    (find-file filename)))

(defun find-file-not-found-set-buffer-file-type ()
  (save-excursion
    (set-buffer (current-buffer))
    (setq buffer-file-type (find-buffer-file-type (buffer-file-name))))
  nil)

;;; To set the default file type on new files.
(add-hook 'find-file-not-found-hooks 'find-file-not-found-set-buffer-file-type)


;;; To accomodate filesystems that do not require CR/LF translation.
(defvar untranslated-filesystem-list nil
  "List of filesystems that require no CR/LF translation when reading 
and writing files.  Each filesystem in the list is a string naming
the directory prefix corresponding to the filesystem.")

(defun untranslated-canonical-name (filename)
  "Return FILENAME in a canonicalized form for use with the functions
dealing with untranslated filesystems."
  (if (memq system-type '(ms-dos windows-nt))
      ;; The canonical form for DOS/W32 is with A-Z downcased and all
      ;; directory separators changed to directory-sep-char.
      (let ((name nil))
	(setq name (mapconcat 
		    '(lambda (char) 
		       (if (and (<= ?A char) (<= char ?Z))
			   (char-to-string (+ (- char ?A) ?a))
			 (char-to-string char)))
		    filename nil))
	;; Use expand-file-name to canonicalize directory separators, except
	;; with bare drive letters (which would have the cwd appended).
	(if (string-match "^.:$" name)
	    name
	  (expand-file-name name)))
    filename))

(defun untranslated-file-p (filename)
  "Return t if FILENAME is on a filesystem that does not require 
CR/LF translation, and nil otherwise."
  (let ((fs (untranslated-canonical-name filename))
	(ufs-list untranslated-filesystem-list)
	(found nil))
    (while (and (not found) ufs-list)
      (if (string-match (concat "^" (car ufs-list)) fs)
	  (setq found t)
	(setq ufs-list (cdr ufs-list))))
    found))

(defun add-untranslated-filesystem (filesystem)
  "Add FILESYSTEM to the list of filesystems that do not require
CR/LF translation.  FILESYSTEM is a string containing the directory
prefix corresponding to the filesystem.  For example, for a Unix 
filesystem mounted on drive Z:, FILESYSTEM could be \"Z:\"."
  (interactive "fUntranslated file system: ")
  (let ((fs (untranslated-canonical-name filesystem)))
    (if (member fs untranslated-filesystem-list)
	untranslated-filesystem-list
      (setq untranslated-filesystem-list
	    (cons fs untranslated-filesystem-list)))))

(defun remove-untranslated-filesystem (filesystem)
  "Remove FILESYSTEM from the list of filesystems that do not require 
CR/LF translation.  FILESYSTEM is a string containing the directory
prefix corresponding to the filesystem.  For example, for a Unix 
filesystem mounted on drive Z:, FILESYSTEM could be \"Z:\"."
  (interactive "fUntranslated file system: ")
  (setq untranslated-filesystem-list 
	(delete (untranslated-canonical-name filesystem)
		untranslated-filesystem-list)))

;; Process I/O decoding and encoding.

(defun find-binary-process-coding-system (op args)
  "Choose a coding system for process I/O.
The coding system for decode is 'no-conversion' if 'binary-process-output'
is non-nil, and 'emacs-mule-dos' otherwise.  Similarly, the coding system 
for encode is 'no-conversion' if 'binary-process-input' is non-nil,
and 'emacs-mule-dos' otherwise."
  (let ((decode 'emacs-mule-dos)
	(encode 'emacs-mule-dos))
    (if binary-process-output
	(setq decode 'no-conversion))
    (if binary-process-input
	(setq encode 'no-conversion))
    (cons decode encode)))

(modify-coding-system-alist 'process "" 'find-binary-process-coding-system)


(provide 'dos-w32)

;;; dos-w32.el ends here
