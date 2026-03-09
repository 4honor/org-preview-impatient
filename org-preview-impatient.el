;;; org-preview-impatient.el --- Smooth, impatient Org-mode preview in browser -*- lexical-binding: t; -*-

;; Author: binz
;; URL: https://github.com/4honor/org-preview-impatient
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (async "1.9.4") (simple-httpd "1.5.1") (impatient-mode "1.1.0"))
;; Keywords: org, preview, impatient, html

;;; Commentary:

;; org-preview-impatient provides a near zero-latency HTML preview of Org files
;; using an asynchronous export process and a lightweight web server.

;;; Code:

(require 'org)
(require 'ox-html)
(require 'async)
(require 'simple-httpd)
(require 'impatient-mode)

(defvar async-prompt-for-password)

(defgroup org-preview-impatient nil
  "Fluent Org-mode preview in browser."
  :group 'org
  :prefix "org-preview-impatient-")

(defcustom org-preview-impatient-debounce-interval 0.5
  "Interval in seconds to wait after the last change.
This delay happens before triggering a preview update."
  :type 'number
  :group 'org-preview-impatient)

(defcustom org-preview-impatient-port 8888
  "Port for the simple-httpd server."
  :type 'integer
  :group 'org-preview-impatient)

(defcustom org-preview-impatient-extra-packages '(org-excalidraw)
  "Extra packages to load in the async export process."
  :type '(repeat symbol)
  :group 'org-preview-impatient)

(defcustom org-preview-impatient-body-only t
  "Whether to export only the body of the Org file.
Set to nil if you want to include HTML head (styles, etc.) from #+SETUPFILE."
  :type 'boolean
  :group 'org-preview-impatient)

(defcustom org-preview-impatient-default-setupfile nil
  "Default SETUPFILE to use for preview, if any.
This file will be injected at the top of the exported Org buffer."
  :type '(choice (const :tag "None" nil) string)
  :group 'org-preview-impatient)

;;; Variables

(defvar-local org-preview-impatient--timer nil
  "Timer for debouncing preview updates.")

(defvar-local org-preview-impatient--output-buffer nil
  "The buffer containing the HTML output for impatient-mode.")

(defvar-local org-preview-impatient--async-process nil
  "The current active async export process.")

(defvar org-preview-impatient--mode-line-string " OrgImp"
  "String to display in the mode line.")

;;; Public Commands

(defun org-preview-impatient-show-html-buffer ()
  "Display the hidden HTML output buffer."
  (interactive)
  (if (buffer-live-p org-preview-impatient--output-buffer)
      (switch-to-buffer-other-window org-preview-impatient--output-buffer)
    (message "No active preview buffer for this buffer.")))

;;; Excalidraw Support

(defun org-preview-impatient-setup-excalidraw ()
  "Setup excalidraw link handling via org-excalidraw."
  ;; Reference: https://github.com/4honor/org-excalidraw
  ;; This ensures the async process can handle excalidraw:// links.
  )

;;; Core Logic

(defun org-preview-impatient--export-callback (html-content output-buffer)
  "Callback for the async export task.
HTML-CONTENT is the generated HTML string.
OUTPUT-BUFFER is the buffer to update."
  (when (buffer-live-p output-buffer)
    (with-current-buffer output-buffer
      (erase-buffer)
      (insert (or html-content ""))
      (set-buffer-modified-p nil))))

(defun org-preview-impatient--post-process-html (html &optional out-buf-name)
  "Post-process exported HTML to embed images and more."
  (with-temp-buffer
    (insert html)
    (goto-char (point-min))
    ;; Inject base tag to fix relative assets paths inside impatient-mode iframe
    (when (and out-buf-name
               (re-search-forward "<head>" nil t))
      (insert (format "\n<base href=\"/imp/live/%s/\">" (url-hexify-string out-buf-name))))
    (goto-char (point-min))
    ;; Embed local images as Base64
    (while (re-search-forward "<img src=\"\\([^\"]+\\)\"" nil t)
      (let* ((match-beg (match-beginning 0))
             (match-end (match-end 0))
             (src (match-string 1))
             (path (substring-no-properties src)))
        ;; Remove file:// prefix if present
        (when (string-match "^file:/*\\(/.*\\)" path)
          (setq path (match-string 1 path)))
        ;; Handle path normalization
        (unless (file-name-absolute-p path)
          (let ((abs-path (expand-file-name path)))
            (if (file-exists-p abs-path)
                (setq path abs-path)
              (when (file-exists-p (concat "/" path))
                (setq path (concat "/" path))))))
        
        (when (file-exists-p path)
          (let ((data (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally path)
                        (base64-encode-region (point-min) (point-max) t)
                        (buffer-string)))
                (ext (file-name-extension path)))
            (goto-char match-beg)
            (delete-region match-beg match-end)
            (insert (format "<img src=\"data:image/%s;base64,%s\"" (or ext "png") data))))))
    (buffer-string)))

(defun org-preview-impatient--trigger-async-export (buffer-content)
  "Start an asynchronous export of BUFFER-CONTENT."
  (let ((async-prompt-for-password nil)
        (lp load-path)
        (ep exec-path)
        (dir default-directory)
        (file buffer-file-name)
        (extra-pkgs org-preview-impatient-extra-packages)
        (out-buf org-preview-impatient--output-buffer)
        (out-buf-name (and (buffer-live-p org-preview-impatient--output-buffer)
                           (buffer-name org-preview-impatient--output-buffer)))
        (body-only org-preview-impatient-body-only)
        (def-setupfile org-preview-impatient-default-setupfile)
        ;; Safely capture variables to pass to the async worker
        (babel-langs (when (boundp 'org-babel-load-languages) org-babel-load-languages))
        (confirm-babel (when (boundp 'org-confirm-babel-evaluate) org-confirm-babel-evaluate))
        (puml-jar (when (boundp 'org-plantuml-jar-path) org-plantuml-jar-path))
        (puml-exec (when (boundp 'org-plantuml-executable-path) org-plantuml-executable-path))
        (puml-mode (when (boundp 'org-plantuml-exec-mode) org-plantuml-exec-mode)))
    (setq org-preview-impatient--async-process
          (async-start
           `(lambda ()
              (setq load-path ',lp)
              (setq exec-path ',ep)
              (require 'org)
              (require 'ox-html)
              (require 'org-preview-impatient)
              (condition-case err
                  (let ((org-html-inline-images t)
                        (org-export-with-broken-links t)
                        (buffer-content ,buffer-content)
                        (export-body-only ,body-only)
                        (temp-output-file (make-temp-file "org-preview-async-html-"))
                        (def-setup-file ,def-setupfile))
                    (with-temp-buffer
                      (setq default-directory ,dir)
                      (setq buffer-file-name ,file)
                      (when def-setup-file
                        (insert (format "#+SETUPFILE: %s\n" def-setup-file)))
                      (insert buffer-content)
                      ;; Load extra packages FIRST so variables are defined
                      (dolist (pkg ',extra-pkgs)
                        (require pkg nil t))
                      
                      ;; Setup plantuml variables
                      (when ',puml-jar (setq org-plantuml-jar-path ',puml-jar))
                      (when ',puml-exec (setq org-plantuml-executable-path ',puml-exec))
                      (when ',puml-mode (setq org-plantuml-exec-mode ',puml-mode))
                      
                      (org-mode)

                      ;; Setup babel languages
                      (when ',babel-langs
                        (setq org-babel-load-languages ',babel-langs)
                        (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages))
                      (when (boundp 'org-confirm-babel-evaluate)
                        (setq org-confirm-babel-evaluate ',confirm-babel))
                      
                      (let ((html (org-export-as 'html nil nil export-body-only)))
                        (with-temp-file temp-output-file
                          (insert (org-preview-impatient--post-process-html html ,out-buf-name)))
                        ;; Return the temp file path instead of the huge string
                        temp-output-file)))
                (error (format "ERROR: %S" err))))
           (lambda (result-file)
             ;; In case of error string returned
             (if (and (stringp result-file)
                      (string-prefix-p "ERROR:" result-file))
                 (message "org-preview-impatient async failed: %s" result-file)
               (when (and (stringp result-file) (file-exists-p result-file))
                 (let ((html-content (with-temp-buffer
                                       (insert-file-contents result-file)
                                       (buffer-string))))
                   (org-preview-impatient--export-callback html-content out-buf)
                   (delete-file result-file)))))))))

(defun org-preview-impatient--trigger-export-sync ()
  "Force a synchronous export of the current buffer."
  (let ((org-html-inline-images t)
        (org-export-with-broken-links t)
        (dir default-directory)
        (file buffer-file-name)
        (buffer-content (buffer-substring-no-properties (point-min) (point-max))))
    (with-temp-buffer
      (setq default-directory dir)
      (setq buffer-file-name file)
      (when org-preview-impatient-default-setupfile
        (insert (format "#+SETUPFILE: %s\n" org-preview-impatient-default-setupfile)))
      (insert buffer-content)
      (org-mode)
      (let ((html (org-export-as 'html nil nil org-preview-impatient-body-only)))
        (org-preview-impatient--post-process-html html (buffer-name org-preview-impatient--output-buffer))))))

(defun org-preview-impatient-update (&optional sync)
  "Trigger an update of the preview.
If SYNC is non-nil, perform the export synchronously."
  (if sync
      (let ((result (org-preview-impatient--trigger-export-sync)))
        (org-preview-impatient--export-callback result org-preview-impatient--output-buffer))
    (let ((buffer-content (buffer-substring-no-properties (point-min) (point-max))))
      (org-preview-impatient--trigger-async-export buffer-content))))

;;; Minor Mode

(defun org-preview-impatient--after-change (&rest _args)
  "Hook for buffer changes."
  (when org-preview-impatient--timer
    (cancel-timer org-preview-impatient--timer))
  (setq org-preview-impatient--timer
        (run-with-idle-timer org-preview-impatient-debounce-interval
                             nil
                             #'org-preview-impatient-update)))

;;;###autoload
(define-minor-mode org-preview-impatient-mode
  "Minor mode for impatient Org-mode preview."
  :lighter org-preview-impatient--mode-line-string
  (if org-preview-impatient-mode
      (let ((source-file buffer-file-name)
            (source-dir default-directory))
        (setq org-preview-impatient--output-buffer
              (get-buffer-create (format "org-preview-%s" (buffer-name))))
        (with-current-buffer org-preview-impatient--output-buffer
          (setq default-directory source-dir)
          (when source-file
            ;; Impatient-mode uses buffer-file-name to serve relative assets (e.g. from setupfile theme CSS)
            (setq buffer-file-name (concat source-file ".html")))
          (if (fboundp 'mhtml-mode)
              (mhtml-mode)
            (html-mode))
          (impatient-mode 1))
        (add-hook 'after-change-functions #'org-preview-impatient--after-change nil t)
        (require 'simple-httpd)
        (setq httpd-port org-preview-impatient-port)
        (httpd-start)
        (org-preview-impatient-update)
        (let ((url (format "http://localhost:%d/imp/live/%s"
                           org-preview-impatient-port
                           (url-hexify-string (buffer-name org-preview-impatient--output-buffer)))))
          (browse-url url)
          (message "Org Preview Impatient started at %s" url)))
    (progn
      (remove-hook 'after-change-functions #'org-preview-impatient--after-change t)
      (when org-preview-impatient--timer
        (cancel-timer org-preview-impatient--timer)
        (setq org-preview-impatient--timer nil))
      (when (buffer-live-p org-preview-impatient--output-buffer)
        (kill-buffer org-preview-impatient--output-buffer)))))

(provide 'org-preview-impatient)

;;; org-preview-impatient.el ends here