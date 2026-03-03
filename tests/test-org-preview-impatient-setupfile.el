;;; test-org-preview-impatient-setupfile.el --- Tests for SETUPFILE -*- lexical-binding: t -*-

(require 'ert)
(require 'org-preview-impatient)
(require 'f)

(ert-deftest test-org-preview-impatient-setupfile-integration ()
  "Test #+SETUPFILE support."
  (skip-unless (executable-find "emacs"))
  (let* ((temp-dir (make-temp-file "org-preview-setupfile-" t))
         (setup-file (expand-file-name "test.theme" temp-dir))
         (org-file (expand-file-name "test.org" temp-dir))
         (port 9999)
         (org-buffer (generate-new-buffer "setupfile.org")))
    
    ;; Create setup file
    (with-temp-file setup-file
      (insert "#+MACRO: greet Hello $1\n")
      (insert "#+HTML_HEAD: <style>.custom { color: red; }</style>\n"))
    
    (with-current-buffer org-buffer
      (insert (format "#+SETUPFILE: %s\n" setup-file))
      (insert "{{{greet(World)}}}\n")
      (insert "#+begin_export html\n<div class=\"custom\">Custom Content</div>\n#+end_export\n")
      (org-mode)
      
      (let ((org-preview-impatient-body-only nil))
        (let ((html (org-preview-impatient--trigger-export-sync)))
          (unwind-protect
              (progn
                (should html)
                (with-temp-buffer
                  (insert html)
                (goto-char (point-min))
                ;; Check if macro expanded
                (should (re-search-forward "Hello World" nil t))
                ;; Check if HTML_HEAD is present
                (goto-char (point-min))
                (should (re-search-forward "<style>.custom" nil t))))
            ;; Cleanup
            (kill-buffer org-buffer)
            (delete-directory temp-dir t)))))))

(ert-deftest test-org-preview-impatient-setupfile-istyle-theme ()
  "Test #+SETUPFILE support with specific ~/GitHub/wiki/static/themes/istyle/istyle.theme path."
  (skip-unless (executable-find "emacs"))
  (let* ((theme-dir (expand-file-name "~/GitHub/wiki/static/themes/istyle/"))
         (theme-file (expand-file-name "istyle.theme" theme-dir))
         (css-file (expand-file-name "istyle.css" theme-dir))
         (org-buffer (generate-new-buffer "istyle-test.org"))
         ;; We will mock the files if they do not exist
         (mocked (not (file-exists-p theme-dir))))
    
    (when mocked
      (make-directory theme-dir t)
      (with-temp-file theme-file
        (insert "#+HTML_HEAD: <link rel=\"stylesheet\" type=\"text/css\" href=\"istyle.css\" />\n"))
      (with-temp-file css-file
        (insert "body { background-color: #f0f0f0; }")))

    (with-current-buffer org-buffer
      (insert (format "#+SETUPFILE: %s\n" theme-file))
      (insert "* Hello iStyle\n")
      (org-mode)
      
      (let ((org-preview-impatient-body-only nil))
        (let ((html (org-preview-impatient--trigger-export-sync)))
          (unwind-protect
              (progn
                (should html)
                (with-temp-buffer
                  (insert html)
                  (goto-char (point-min))
                  ;; Check if the HTML_HEAD from istyle.theme is injected
                  (should (re-search-forward "<link .*href=\"istyle\\.css\"" nil t))))
            ;; Cleanup buffer
            (kill-buffer org-buffer)
            ;; Cleanup mocked files
            (when mocked
              (delete-directory (expand-file-name "~/GitHub/wiki") t))))))))
