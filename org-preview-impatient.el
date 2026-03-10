;;; org-preview-impatient.el --- Smooth, impatient Org-mode preview in browser -*- lexical-binding: t; -*-

;; Author: binz
;; URL: https://github.com/4honor/org-preview-impatient
;; Version: 1.0.0
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

(defcustom org-preview-impatient-sync-scroll t
  "If non-nil, synchronize scroll positions between Emacs and browser."
  :type 'boolean
  :group 'org-preview-impatient)

(defcustom org-preview-impatient-sync-scroll-bidirectional nil
  "If non-nil, scrolling in the browser also scrolls Emacs."
  :type 'boolean
  :group 'org-preview-impatient)

;;; Variables

(defvar-local org-preview-impatient--timer nil
  "Timer for debouncing preview updates.")

(defvar-local org-preview-impatient--output-buffer nil
  "The buffer containing the HTML output for impatient-mode.")

(defvar-local org-preview-impatient--async-process nil
  "The current active async export process.")

(defvar-local org-preview-impatient--scroll-clients nil
  "List of httpd client processes waiting for a scroll update.")

(defvar-local org-preview-impatient--last-line 0
  "The last line number synced.")

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
  "Setup excalidraw link handling via org-excalidraw.
This ensures the async process can gracefully handle `excalidraw://` links
by stripping the leading slashes before passing to `org-excalidraw'."
  (when (require 'org-excalidraw nil t)
    (let ((default-export (plist-get (cdr (assoc "excalidraw" org-link-parameters)) :export)))
      (org-link-set-parameters
       "excalidraw"
       :export (lambda (link desc backend)
                 (let ((clean-link (if (string-match "^//+\\(.*\\)" link)
                                       (match-string 1 link)
                                     link)))
                   (if default-export
                       (funcall default-export clean-link desc backend)
                     ;; Fallback gracefully if somehow missing export
                     (org-export-string-as (format "[[file:%s]]" clean-link) backend t))))))))

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
    ;; Inject base tag and JS
    (when out-buf-name
      (goto-char (point-min))
      (if (re-search-forward "<head>" nil t)
          (progn
            (insert (format "\n<base href=\"/imp/live/%s/\">" (url-hexify-string out-buf-name)))
            (when org-preview-impatient-sync-scroll
              (insert "\n" org-preview-impatient--sync-js "\n")))
        (goto-char (point-max))
        (when org-preview-impatient-sync-scroll
          (insert "\n" org-preview-impatient--sync-js "\n"))))
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
            (let ((mime-type (pcase (downcase (or ext "png"))
                               ("svg" "svg+xml")
                               ("jpg" "jpeg")
                               (other other))))
              (goto-char match-beg)
              (delete-region match-beg match-end)
              (insert (format "<img src=\"data:image/%s;base64,%s\"" mime-type data)))))))
    (buffer-string)))

(defconst org-preview-impatient--sync-js "
<script>
(function() {
  if (!window.location.pathname.startsWith('/imp/live/')) return;
  var bufNameRaw = window.location.pathname.split('/')[3];
  if (!bufNameRaw) return;
  var bufName = unescape(bufNameRaw);
  var isAutoScrolling = false;

  function getScrollEndpoint() { return '/org-preview-impatient/scroll/' + encodeURIComponent(bufName); }
  function getScrolledEndpoint(line) { return '/org-preview-impatient/scrolled/' + encodeURIComponent(bufName) + '?line=' + line; }

  function pollScroll() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', getScrollEndpoint(), true);
    xhr.onreadystatechange = function() {
      if (xhr.readyState == 4) {
        if (xhr.status == 200) {
          var line = parseInt(xhr.responseText);
          if (!isNaN(line)) {
            var el = document.getElementById('org-line-' + line);
            if (!el) {
              var elements = document.querySelectorAll('[data-line]');
              var closest = null; var minDiff = 999999;
              for (var i = 0; i < elements.length; i++) {
                var elLine = parseInt(elements[i].getAttribute('data-line'));
                var diff = line - elLine;
                if (diff >= 0 && diff < minDiff) { minDiff = diff; closest = elements[i]; }
              }
              el = closest;
            }
            if (el) {
              isAutoScrolling = true;
              el.scrollIntoView({behavior: 'auto', block: 'start', inline: 'nearest'});
              setTimeout(function(){ isAutoScrolling = false; }, 300);
            }
          }
        }
        setTimeout(pollScroll, 200);
      }
    };
    xhr.onerror = function() { setTimeout(pollScroll, 2000); };
    xhr.send();
  }

  var scrollTimeout;
  window.addEventListener('scroll', function() {
    if (isAutoScrolling) return;
    clearTimeout(scrollTimeout);
    scrollTimeout = setTimeout(function() {
      var elements = document.querySelectorAll('[data-line]');
      var topEl = null;
      for (var i = 0; i < elements.length; i++) {
        var rect = elements[i].getBoundingClientRect();
        if (rect.top >= 0 && rect.top < window.innerHeight / 2) { topEl = elements[i]; break; }
      }
      if (topEl) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', getScrolledEndpoint(topEl.getAttribute('data-line')), true);
        xhr.send();
      }
    }, 150);
  });
  pollScroll();
})();
</script>")

(defun org-preview-impatient--sync-line-number-filter (tree backend _info)
  "Inject line numbers into HTML elements for sync scroll."
  (when (and org-preview-impatient-sync-scroll (org-export-derived-backend-p backend 'html))
    (let ((headlines (org-element-map tree 'headline #'identity))
          (blocks (org-element-map tree '(paragraph quote-block table item src-block) #'identity)))
      (dolist (hl headlines)
        (let* ((begin (org-element-property :begin hl)))
          (when begin
            (let ((line (line-number-at-pos begin)))
              (unless (org-element-property :CUSTOM_ID hl)
                (org-element-put-property hl :CUSTOM_ID (format "org-line-%d" line)))))))
      (dolist (el blocks)
        (let* ((begin (org-element-property :begin el)))
          (when (and begin
                     (not (eq 'item (org-element-type (org-element-property :parent el)))))
            (let* ((line (line-number-at-pos begin))
                   (snippet (list 'export-snippet
                                  (list :back-end "html"
                                        :value (format "<a data-line=\"%d\" id=\"org-line-%d\"></a>" line line)
                                        :post-blank 0))))
              (if (org-element-contents el)
                  (org-element-set-contents 
                   el
                   (cons snippet (org-element-contents el)))
                (org-element-insert-before snippet el))))))))
  tree)

(defun org-preview-impatient--trigger-async-export (buffer-content)
  "Start an asynchronous export of BUFFER-CONTENT."
  (let ((lp load-path)
        (ep exec-path)
        (dir default-directory)
        (file buffer-file-name)
        (extra-pkgs org-preview-impatient-extra-packages)
        (out-buf org-preview-impatient--output-buffer)
        (out-buf-name (and (buffer-live-p org-preview-impatient--output-buffer)
                           (buffer-name org-preview-impatient--output-buffer)))
        (body-only org-preview-impatient-body-only)
        (def-setupfile org-preview-impatient-default-setupfile)
        (temp-input-file (make-temp-file "org-preview-async-in-"))
        (sync-scroll org-preview-impatient-sync-scroll)
        (sync-bidirectional org-preview-impatient-sync-scroll-bidirectional)
        ;; Safely capture variables to pass to the async worker
        (babel-langs (when (boundp 'org-babel-load-languages) org-babel-load-languages))
        (confirm-babel (when (boundp 'org-confirm-babel-evaluate) org-confirm-babel-evaluate))
        (puml-jar (when (boundp 'org-plantuml-jar-path) org-plantuml-jar-path))
        (puml-exec (when (boundp 'org-plantuml-executable-path) org-plantuml-executable-path))
        (puml-mode (when (boundp 'org-plantuml-exec-mode) org-plantuml-exec-mode)))
    
    (with-temp-file temp-input-file
      (insert buffer-content))

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
                        (org-preview-impatient-sync-scroll ,sync-scroll)
                        (org-preview-impatient-sync-scroll-bidirectional ,sync-bidirectional)
                        (export-body-only ,body-only)
                        (temp-output-file (make-temp-file "org-preview-async-html-"))
                        (def-setup-file ,def-setupfile)
                        (input-file ,temp-input-file))
                    (with-temp-buffer
                      (setq default-directory ,dir)
                      (setq buffer-file-name ,file)
                      (when def-setup-file
                        (insert (format "#+SETUPFILE: %s\n" def-setup-file)))
                      (insert-file-contents input-file)
                      ;; Load extra packages FIRST so variables are defined
                      (dolist (pkg ',extra-pkgs)
                        (require pkg nil t))
                      
                      ;; Ensure excalidraw override is active
                      (org-preview-impatient-setup-excalidraw)

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
                      
                      (let* ((org-export-filter-parse-tree-functions '(org-preview-impatient--sync-line-number-filter))
                             (html (org-export-as 'html nil nil export-body-only)))
                        (with-temp-file temp-output-file
                          (insert (org-preview-impatient--post-process-html html ,out-buf-name)))
                        ;; Return the temp file path instead of the huge string
                        temp-output-file)))
                (error (format "ERROR: %S" err))))
           (lambda (result-file)
             (ignore-errors (delete-file temp-input-file))
             ;; In case of error string returned
             (if (and (stringp result-file)
                      (string-prefix-p "ERROR:" result-file))
                 (message "org-preview-impatient async failed: %s" result-file)
               (when (and (stringp result-file) (file-exists-p result-file))
                 (let ((html-content (with-temp-buffer
                                       (insert-file-contents result-file)
                                       (buffer-string))))
                   (org-preview-impatient--export-callback html-content out-buf)
                   (delete-file result-file)))))))
    
    ;; Suppress any erroneous password scanning on this process by async.el
    (when (process-live-p org-preview-impatient--async-process)
      (with-current-buffer (process-buffer org-preview-impatient--async-process)
        (set (make-local-variable 'tramp-password-prompt-regexp) nil)))))

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
      (org-preview-impatient-setup-excalidraw)
      (org-mode)
      (let* ((org-export-filter-parse-tree-functions '(org-preview-impatient--sync-line-number-filter))
             (html (org-export-as 'html nil nil org-preview-impatient-body-only)))
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

(defun org-preview-impatient--on-window-scroll (window display-start)
  "Hook to capture Emacs window scroll and push to browser.
WINDOW is the scrolled window, DISPLAY-START is the new start position."
  (let ((buf (window-buffer window)))
    (when (buffer-local-value 'org-preview-impatient-mode buf)
      (with-current-buffer buf
        (when org-preview-impatient-sync-scroll
          (let ((line (line-number-at-pos display-start)))
            (unless (equal line org-preview-impatient--last-line)
              (setq org-preview-impatient--last-line line)
              (org-preview-impatient--notify-scroll line))))))))

(defun org-preview-impatient--notify-scroll (line)
  "Notify long-polling clients to scroll to LINE."
  (while org-preview-impatient--scroll-clients
    (let ((proc (pop org-preview-impatient--scroll-clients)))
      (condition-case nil
          (with-temp-buffer
            (insert (number-to-string line))
            (httpd-send-header proc "text/plain" 200 :Cache-Control "no-cache"))
        (error nil)))))

(defun httpd/org-preview-impatient/scroll (proc path query &rest _)
  "Long polling endpoint for receiving scroll updates."
  (let* ((decoded (url-unhex-string path))
         (parts (cdr (split-string decoded "/")))
         (buffer-name (nth 2 parts))
         (buffer (get-buffer buffer-name)))
    (if (and buffer (buffer-local-value 'org-preview-impatient-mode buffer))
        (with-current-buffer buffer
          (push proc org-preview-impatient--scroll-clients))
      (httpd-error proc 404 "Buffer not found or preview mode not enabled."))))

(defun httpd/org-preview-impatient/scrolled (proc path _query &rest _)
  "Endpoint called by browser when it scrolls."
  (let* ((decoded (url-unhex-string path))
         (parts (cdr (split-string decoded "/")))
         (buffer-name (nth 2 parts))
         (buffer (get-buffer buffer-name))
         (line-str (cadr (assoc "line" _query))))
    (if (and buffer line-str
             (buffer-local-value 'org-preview-impatient-mode buffer)
             (buffer-local-value 'org-preview-impatient-sync-scroll-bidirectional buffer))
        (with-current-buffer buffer
           (let ((line (string-to-number line-str)))
             (setq org-preview-impatient--last-line line)
             (when (get-buffer-window buffer)
               (with-selected-window (get-buffer-window buffer)
                 (goto-char (point-min))
                 (forward-line (1- line))
                 (recenter 0))))
           (with-temp-buffer
             (insert "OK")
             (httpd-send-header proc "text/plain" 200 :Cache-Control "no-cache")))
      (when proc
         (with-temp-buffer
           (insert "Ignored")
           (httpd-send-header proc "text/plain" 200 :Cache-Control "no-cache"))))))

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
        (add-hook 'window-scroll-functions #'org-preview-impatient--on-window-scroll nil t)
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
      (while org-preview-impatient--scroll-clients
        (let ((proc (pop org-preview-impatient--scroll-clients)))
          (ignore-errors (delete-process proc))))
      (remove-hook 'after-change-functions #'org-preview-impatient--after-change t)
      (remove-hook 'window-scroll-functions #'org-preview-impatient--on-window-scroll t)
      (when org-preview-impatient--timer
        (cancel-timer org-preview-impatient--timer)
        (setq org-preview-impatient--timer nil))
      (when (buffer-live-p org-preview-impatient--output-buffer)
        (kill-buffer org-preview-impatient--output-buffer)))))

(provide 'org-preview-impatient)

;;; org-preview-impatient.el ends here