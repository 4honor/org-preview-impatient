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

(defgroup org-preview-impatient nil
  "Fluent Org-mode preview in browser."
  :group 'org
  :prefix "org-preview-impatient-")

(defcustom org-preview-impatient-debounce-interval 0.5
  "Interval in seconds to wait after the last change before triggering a preview update."
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

;;; Variables

(defvar-local org-preview-impatient--timer nil
  "Timer for debouncing preview updates.")

(defvar-local org-preview-impatient--output-buffer nil
  "The buffer containing the HTML output for impatient-mode.")

(defvar-local org-preview-impatient--async-process nil
  "The current active async export process.")

;;; Excalidraw Support

(defun org-preview-impatient-setup-excalidraw ()
  "Setup excalidraw link handling via org-excalidraw."
  ;; Reference: https://github.com/4honor/org-excalidraw
  ;; This ensures the async process can handle excalidraw:// links.
  )

;;; Core Logic

(defun org-preview-impatient--export-callback (html-content)
  "Callback for the async export task.
HTML-CONTENT is the generated HTML string."
  (when (buffer-live-p org-preview-impatient--output-buffer)
    (with-current-buffer org-preview-impatient--output-buffer
      (erase-buffer)
      (insert html-content)
      (set-buffer-modified-p nil))))

(defun org-preview-impatient--post-process-html (html)
  "Post-process exported HTML to embed images and more."
  (with-temp-buffer
    (insert html)
    (goto-char (point-min))
    ;; Embed local images as Base64
    (while (re-search-forward "<img src=\"\\([^\"]+\\)\"" nil t)
      (let* ((src (match-string 1))
             (path (substring-no-properties src)))
        (save-match-data
          ;; Remove file:// prefix if present
          (when (string-match "^file:/*\\(.*\\)" path)
            (setq path (match-string 1 path)))
          ;; On some systems we might need to add a leading slash back
          (unless (file-name-absolute-p path)
            (let ((abs-path (expand-file-name path)))
              (if (file-exists-p abs-path)
                  (setq path abs-path)
                ;; Try adding / if it looks like a Unix absolute path originally
                (when (file-exists-p (concat "/" path))
                  (setq path (concat "/" path)))))))
        (when (file-exists-p path)
          (let ((data (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally path)
                        (base64-encode-region (point-min) (point-max) t)
                        (buffer-string)))
                (ext (file-name-extension path)))
            (replace-match (format "<img src=\"data:image/%s;base64,%s\"" (or ext "png") data) t t)))))
    (buffer-string)))

(defun org-preview-impatient--trigger-async-export (buffer-content)
  "Start an asynchronous export of BUFFER-CONTENT."
  (let ((lp load-path)
        (extra-pkgs org-preview-impatient-extra-packages))
    (setq org-preview-impatient--async-process
          (async-start
           `(lambda ()
              (setq load-path ',lp)
              (require 'org)
              (require 'ox-html)
              (require 'org-preview-impatient)
              ;; Load extra packages
              (dolist (pkg ',extra-pkgs)
                (require pkg nil t))
              
              (with-temp-buffer
                (insert ,buffer-content)
                (org-mode)
                (let ((org-html-inline-images t)
                      (org-export-with-broken-links t))
                  (let ((html (with-current-buffer (org-html-export-as-html nil nil nil t)
                                (buffer-string))))
                    (org-preview-impatient--post-process-html html)))))
           (lambda (result)
             (org-preview-impatient--export-callback result))))))

(defun org-preview-impatient-update ()
  "Trigger an update of the preview."
  (let ((buffer-content (buffer-substring-no-properties (point-min) (point-max))))
    (org-preview-impatient--trigger-async-export buffer-content)))

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
  :lighter " OrgImp"
  (if org-preview-impatient-mode
      (progn
        (setq org-preview-impatient--output-buffer
              (get-buffer-create (format " *org-preview-%s*" (buffer-name))))
        (with-current-buffer org-preview-impatient--output-buffer
          (impatient-mode 1))
        (add-hook 'after-change-functions #'org-preview-impatient--after-change nil t)
        (setq httpd-port org-preview-impatient-port)
        (httpd-start)
        (org-preview-impatient-update)
        (let ((url (format "http://localhost:%d/imp/live/%s"
                           org-preview-impatient-port
                           (buffer-name org-preview-impatient--output-buffer))))
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
