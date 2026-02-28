;;; test-org-preview-impatient-integration.el --- Integration tests for org-preview-impatient -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-preview-impatient)
(require 'url)

(ert-deftest test-org-preview-impatient-html-content ()
  "Test if the exported HTML content is served correctly via httpd."
  (let* ((org-buffer (generate-new-buffer "integration-test.org"))
         (port 8896)
         (org-preview-impatient-port port))
    
    (with-current-buffer org-buffer
      (insert "* Integration Test Header\nThis is a test body.")
      (org-mode)
      
      (cl-letf (((symbol-function 'browse-url) (lambda (&rest _args) nil)))
        (setq httpd-port port)
        (org-preview-impatient-mode 1)
        (org-preview-impatient-update t) ; Force sync update
        
        (unwind-protect
            (progn
              (should org-preview-impatient-mode)
              (should (buffer-live-p org-preview-impatient--output-buffer))
                
              ;; Fetch raw buffer content from impatient-mode
              (let* ((url (format "http://localhost:%d/imp/buffer/%s"
                                 port
                                 (url-hexify-string (buffer-name org-preview-impatient--output-buffer))))
                     (url-request-method "GET")
                     (response-buffer (url-retrieve-synchronously url)))
                
                (should response-buffer)
                (with-current-buffer response-buffer
                  (goto-char (point-min))
                  (should (re-search-forward "HTTP/1.1 200 OK" nil t))
                  (should (re-search-forward "Integration Test Header" nil t))
                  (should (re-search-forward "This is a test body" nil t))
                  ;; Verify it's NOT wrapped in <pre> (meaning correctly served as HTML)
                  (goto-char (point-min))
                  (should-not (re-search-forward "<pre>" nil t)))
                
                (when (buffer-live-p response-buffer)
                  (kill-buffer response-buffer))))
          
          ;; Cleanup
          (org-preview-impatient-mode -1)
          (httpd-stop)
          (kill-buffer org-buffer))))))

(ert-deftest test-org-preview-impatient-plantuml-integration ()
  "Test if PlantUML output is correctly served and embedded."
  (skip-unless (executable-find "plantuml"))
  (let* ((org-buffer (generate-new-buffer "plantuml-integration.org"))
         (port 8899)
         (org-preview-impatient-port port)
         (temp-dir (file-name-as-directory (make-temp-file "org-puml-int" t)))
         (output-image (expand-file-name "test.png" temp-dir)))
    
    (with-current-buffer org-buffer
      (insert "#+begin_src plantuml :file " output-image "\n@startuml\nA -> B\n@enduml\n#+end_src\n")
      (org-mode)
      
      ;; Setup
      (require 'ob-plantuml)
      (require 'subr-x)
      (setq org-confirm-babel-evaluate nil)
      (setq org-babel-load-languages '((plantuml . t)))
      (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages)
      
      ;; Try to find jar if on Mac with homebrew
      (when (eq system-type 'darwin)
        (let ((jar (string-trim (shell-command-to-string "find /opt/homebrew/Cellar/plantuml/ -name plantuml.jar | head -n 1"))))
          (when (and jar (not (string-empty-p jar)))
            (setq org-plantuml-jar-path jar)
            (setq org-plantuml-exec-mode 'jar))))
      
      (cl-letf (((symbol-function 'browse-url) (lambda (&rest _args) nil)))
        (setq httpd-port port)
        (org-preview-impatient-mode 1)
        (org-preview-impatient-update t) ; Sync update
        
        (unwind-protect
            (progn
              (should (file-exists-p output-image))
              (let* ((url (format "http://localhost:%d/imp/buffer/%s"
                                 port
                                 (url-hexify-string (buffer-name org-preview-impatient--output-buffer))))
                     (response-buffer (url-retrieve-synchronously url)))
                (should response-buffer)
                (with-current-buffer response-buffer
                  (goto-char (point-min))
                  (should (re-search-forward "<img src=\"data:image/png;base64," nil t)))
                (when (buffer-live-p response-buffer)
                  (kill-buffer response-buffer))))
          ;; Cleanup
          (org-preview-impatient-mode -1)
          (httpd-stop)
          (kill-buffer org-buffer)
          (delete-directory temp-dir t))))))

(ert-deftest test-org-preview-impatient-plantuml-async-integration ()
  "Test if PlantUML output is correctly generated via ASYNC process."
  (skip-unless (executable-find "plantuml"))
  (let* ((org-buffer (generate-new-buffer "plantuml-async.org"))
         (port 8900)
         (org-preview-impatient-port port)
         (org-preview-impatient-extra-packages '(ob-plantuml))
         (temp-dir (file-name-as-directory (make-temp-file "org-puml-async" t)))
         (output-image (expand-file-name "test-async.png" temp-dir)))
    
    (with-current-buffer org-buffer
      (insert "#+begin_src plantuml :file " output-image " :exports results\n@startuml\nA -> B: Async\n@enduml\n#+end_src\n")
      (org-mode)
      
      ;; Setup
      (require 'ob-plantuml)
      (require 'subr-x)
      (setq org-confirm-babel-evaluate nil)
      (setq org-babel-load-languages '((plantuml . t)))
      (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages)
      
      ;; Try to find jar if on Mac with homebrew
      (when (eq system-type 'darwin)
        (let ((jar (string-trim (shell-command-to-string "find /opt/homebrew/Cellar/plantuml/ -name plantuml.jar | head -n 1"))))
          (when (and jar (not (string-empty-p jar)))
            (setq org-plantuml-jar-path jar)
            (setq org-plantuml-exec-mode 'jar))))
      
      (cl-letf (((symbol-function 'browse-url) (lambda (&rest _args) nil)))
        (setq httpd-port port)
        (org-preview-impatient-mode 1)
        (org-preview-impatient-update) ; ASYNC update
        
        (unwind-protect
            (let ((start-time (current-time))
                  (timeout 15)
                  (found nil))
              (while (and (not found)
                          (< (float-time (time-since start-time)) timeout))
                (when (buffer-live-p org-preview-impatient--output-buffer)
                  (with-current-buffer org-preview-impatient--output-buffer
                    (goto-char (point-min))
                    (when (re-search-forward "data:image/png;base64," nil t)
                      (setq found t))))
                (unless found (sleep-for 1)))
              
              (should found)
              (should (file-exists-p output-image)))
          ;; Cleanup
          (org-preview-impatient-mode -1)
          (httpd-stop)
          (kill-buffer org-buffer)
          (delete-directory temp-dir t))))))
