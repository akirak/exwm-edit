;;; exwm-edit.el --- Edit mode for EXWM -*- lexical-binding: t; -*-

;; Author: Ag Ibragimov
;; URL: https://github.com/agzam/exwm-edit
;; Created: 2018-05-16
;; Keywords: convenience
;; License: GPL v3
;; Package-Requires: ((emacs "24.4"))
;; Version: 0.0.1

;;; Commentary:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Similar to atomic-chrome https://github.com/alpha22jp/atomic-chrome
;; except this package is made to work with EXWM https://github.com/ch11ng/exwm
;; and it works with any editable element of any app
;;
;; The idea is very simple - when you press the keybinding,
;; it simulates [C-a (select all) + C-c (copy)],
;; then opens a buffer and yanks (pastes) the content so you can edit it,
;; after you done - it grabs (now edited text) and pastes back to where it's started
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(require 'exwm)

(defvar exwm-edit--last-exwm-buffer nil
  "Last buffer that invoked `exwm-edit'.")

(defvar exwm-edit-last-kill nil
  "Used to check if the text box is empty.
If this is the same value as (car KILL-RING) returns after copying the text-box,
the text box might be empty (because empty text boxes don't add to the KILL-RING).")

(defvar exwm-edit-yank-delay 0.3
  "The delay to use when yanking into the Emacs buffer.
It takes a while for copy in exwm to transfer to Emacs yank.
If this is too low an old yank may be used instead.")

(defvar exwm-edit-paste-delay 0.05
  "The delay to use when pasting text back into the exwm buffer.
If this is too low the text might not be pasted into the exwm buffer")

(defcustom exwm-edit-split-below nil
  "If non-nil `exwm-edit--compose' splits the window below.
Otherwise split the window to the right."
  :type 'boolean
  :group 'exwm-edit)

(defcustom exwm-edit-bind-default-keys t
  "If non-nil bind default keymaps on load."
  :type 'boolean
  :group 'exwm-edit)

(defcustom exwm-edit-compose-hook nil
  "Customizable hook, runs after `exwm-edit--compose' buffer created."
  :type 'hook
  :group 'exwm-edit)

(defcustom exwm-edit-compose-minibuffer-hook nil
  "Customizable hook, runs after `exwm-edit--compose-minibuffer' buffer created."
  :type 'hook
  :group 'exwm-edit)

(defcustom exwm-edit-before-finish-hook nil
  "Customizable hook, runs before `exwm-edit--finish'."
  :type 'hook
  :group 'exwm-edit)

(defcustom exwm-edit-before-cancel-hook nil
  "Customizable hook, runs before `exwm-edit--cancel'."
  :type 'hook
  :group 'exwm-edit)

(defun exwm-edit--finish ()
  "Called when done editing buffer created by `exwm-edit--compose'."
  (interactive)
  (run-hooks 'exwm-edit-before-finish-hook)
  (let ((text (buffer-substring-no-properties
	       (point-min)
	       (point-max))))
    (kill-buffer-and-window)
    (exwm-edit--send-to-exwm-buffer text)))

(defun exwm-edit--send-to-exwm-buffer (text)
  "Sends TEXT to the exwm window."
  (let ((select-enable-clipboard t))
    (gui-select-text text))
  (exwm-input--set-focus exwm-edit--last-exwm-buffer)
  (run-with-timer exwm-edit-paste-delay nil (lambda () (exwm-input--fake-key ?\C-v)))
  (setq exwm-edit--last-exwm-buffer nil))

(defun exwm-edit--cancel ()
  "Called to cancell editing in a buffer created by `exwm-edit--compose'."
  (interactive)
  (run-hooks 'exwm-edit-before-cancel-hook)
  (kill-buffer-and-window)
  (switch-to-buffer exwm-edit--last-exwm-buffer)
  (exwm-input--set-focus (exwm--buffer->id (window-buffer (selected-window))))
  (exwm-input--fake-key 'right)
  (setq exwm-edit--last-exwm-buffer nil))

(defvar exwm-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c '") 'exwm-edit--finish)
    (define-key map (kbd "C-c C-'") 'exwm-edit--finish)
    (define-key map (kbd "C-c C-c") 'exwm-edit--finish)
    (define-key map [remap save-buffer] 'exwm-edit--finish)
    (define-key map (kbd "C-c C-k") 'exwm-edit--cancel)
    map)
  "Keymap for minor mode `exwm-edit-mode'.")

(define-minor-mode exwm-edit-mode
  "Minor mode enabled in `exwm-edit--compose' buffer"
  :init-value nil
  :lighter " exwm-edit"
  :keymap exwm-edit-mode-map)

(defun exwm-edit--buffer-title (str)
  "`exwm-edit' buffer title based on STR."
  (concat "*exwm-edit " str " *"))

(defun exwm-edit--turn-on-edit-mode ()
  "Turn on `exwm-edit-mode' if the buffer was created by `exwm-edit--compose'."
  (when (string= (exwm-edit--buffer-title exwm-edit--last-exwm-buffer)
                 (buffer-name (current-buffer)))
    (exwm-edit-mode t)))

(define-global-minor-mode global-exwm-edit-mode
  exwm-edit-mode exwm-edit--turn-on-edit-mode
  :require 'exwm-edit)

(defun exwm-edit--yank ()
  "Yank text to Emacs buffer with check for empty strings."
  (run-with-timer exwm-edit-yank-delay nil
                  (lambda ()
                    (when-let ((text (gui-selection-value)))
                      (insert text)
                      (run-hooks 'post-command-hook)))))

;;;###autoload
(defun exwm-edit-compose (&optional no-copy)
  "Edit text in an EXWM app.
If NO-COPY is non-nil, don't copy over the contents of the exwm text box"
  (interactive)
  (let* ((title (exwm-edit--buffer-title (buffer-name)))
         (existing (get-buffer title))
         (inhibit-read-only t)
         (selection-coding-system 'utf-8))             ; required for multilang-support
    (when (derived-mode-p 'exwm-mode)
      (setq exwm-edit--last-exwm-buffer (buffer-name))
      (unless (bound-and-true-p global-exwm-edit-mode)
        (global-exwm-edit-mode 1))
      (if existing
          (switch-to-buffer-other-window existing)
        (progn
	  (exwm-input--fake-key ?\C-a)
	  (exwm-input--fake-key ?\C-c)
	  (let ((buffer (get-buffer-create title)))
	    (with-current-buffer buffer
	      (run-hooks 'exwm-edit-compose-hook)
	      (exwm-edit-mode 1)
	      (select-window
	       (if exwm-edit-split-below
		   (split-window-below)
		 (split-window-right)))
	      (switch-to-buffer (get-buffer-create title))
	      (setq-local header-line-format
			  (substitute-command-keys
			   "Edit, then exit with `\\[exwm-edit--finish]' or cancel with \ `\\[exwm-edit--cancel]'"))
	      (unless no-copy
		(exwm-edit--yank)))))))))

(defun exwm-edit--compose-minibuffer (&optional completing-read-entries no-copy)
  "Edit text in an EXWM app.
If COMPLETING-READ-ENTRIES is non-nil, feed that list into the collection
parameter of `completing-read'
If NO-COPY is non-nil, don't copy over the contents of the exwm text box"
  (interactive)
  (let* ((title (exwm-edit--buffer-title (buffer-name)))
         (inhibit-read-only t)
         (selection-coding-system 'utf-8))             ; required for multilang-support
    (when (derived-mode-p 'exwm-mode)
      (setq exwm-edit--last-exwm-buffer (buffer-name))
      (unless (bound-and-true-p global-exwm-edit-mode)
        (global-exwm-edit-mode 1))
      (progn
        (exwm-input--fake-key ?\C-a)
	(unless no-copy
	  (exwm-input--fake-key ?\C-c)
	  (exwm-edit--yank))
	(run-hooks 'exwm-edit-compose-minibuffer-hook)
	(exwm-edit--send-to-exwm-buffer
	 (completing-read "exwm-edit: " completing-read-entries))))))

(when exwm-edit-bind-default-keys
  (exwm-input-set-key (kbd "C-c '") #'exwm-edit-compose)
  (exwm-input-set-key (kbd "C-c C-'") #'exwm-edit-compose))

(provide 'exwm-edit)

;;; exwm-edit.el ends here
