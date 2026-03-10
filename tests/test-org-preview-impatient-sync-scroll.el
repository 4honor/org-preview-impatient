;;; test-org-preview-impatient-sync-scroll.el --- Tests for sync scroll -*- lexical-binding: t -*-

(require 'ert)
(require 'org-preview-impatient)
(require 'f)

(ert-deftest test-org-preview-impatient-sync-scroll-injection ()
  "Test if sync scroll HTML snippets and scripts are injected properly."
  (let* ((org-buffer (generate-new-buffer "sync-scroll-test.org"))
         (org-preview-impatient-sync-scroll t)
         (org-preview-impatient-mode t))
    (with-current-buffer org-buffer
      (insert "* Heading 1\nSome paragraph text.\n\n#+begin_src elisp\n(message \"hello\")\n#+end_src\n")
      (org-mode)
      (setq org-preview-impatient--output-buffer (generate-new-buffer "*html-out*"))
      
      (let ((html (org-preview-impatient--trigger-export-sync)))
        (unwind-protect
            (progn
              (should html)
              (with-temp-buffer
                (insert html)
                (goto-char (point-min))
                ;; Check if script is injected
                (should (re-search-forward "/org-preview-impatient/scroll/" nil t))
                
                ;; Check if headline has CUSTOM_ID as org-line
                (goto-char (point-min))
                (should (re-search-forward "id=\"org-line-1\"" nil t))
                
                ;; Check if paragraph has data-line
                (goto-char (point-min))
                (should (re-search-forward "<a data-line=\"2\" id=\"org-line-2\"></a>" nil t))
                
                ;; Check if src block has data-line
                (goto-char (point-min))
                (should (re-search-forward "<a data-line=\"4\" id=\"org-line-4\"></a>" nil t))))
          
          ;; Cleanup
          (kill-buffer org-buffer)
          (kill-buffer org-preview-impatient--output-buffer))))))

