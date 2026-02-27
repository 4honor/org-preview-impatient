;;; test-org-preview-impatient-images.el --- Test image embedding -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-preview-impatient)

(ert-deftest test-org-preview-impatient-image-embedding ()
  "Test if images are embedded as base64 in the exported HTML."
  (let* ((temp-dir (file-name-as-directory (make-temp-file "org-img-test-" t)))
         (img-path (concat temp-dir "test.png"))
         (org-content (format "[[file:%s]]" img-path))
         (output-html nil))
    
    ;; Create a dummy tiny PNG (1x1 transparent)
    ;; In a real test we'd use a real PNG, but for embedding verification any content works.
    (with-temp-file img-path
      (insert "dummy-image-content"))
    
    (unwind-protect
        (with-temp-buffer
          (insert org-content)
          (org-mode)
          ;; We need to run the export logic. 
          ;; Since it's normally async, we'll run the core part synchronously for testing.
          (let ((org-html-inline-images t)
                (org-export-with-broken-links t))
            ;; This is what happens inside the async lambda
            (setq output-html (with-current-buffer (org-html-export-as-html nil nil nil t)
                                (buffer-string)))
            ;; Explicitly run the post-processing for verification
            (setq output-html (org-preview-impatient--post-process-html output-html)))
          
          ;; Verification: Check if it contains data:image
          (should (string-match-p "src=\"data:image/png;base64," output-html))
          (should (string-match-p (base64-encode-string "dummy-image-content" t) output-html)))
      
      ;; Cleanup
      (delete-file img-path)
      (delete-directory temp-dir))))
