;;; test-org-preview-impatient-password.el --- Tests for password prompt issue -*- lexical-binding: t -*-

(require 'ert)
(require 'org-preview-impatient)
(require 'async)

(defvar test-pwd-prompt-called nil)

(defun test-mock-read-passwd (&rest _args)
  (setq test-pwd-prompt-called t)
  (error "read-passwd was unexpectedly called!"))

(ert-deftest test-org-preview-impatient-no-password-prompt-async ()
  "Test that body-only nil with setupfile doesn't trigger password prompt in async mode."
  (skip-unless (executable-find "emacs"))
  (let* ((theme-dir (make-temp-file "org-preview-pwd-temp-" t))
         (theme-file (expand-file-name "pwd.theme" theme-dir))
         (org-buffer (generate-new-buffer "pwd-test.org"))
         (output-buffer (generate-new-buffer "pwd-out.html")))
    
    (with-temp-file theme-file
      (insert "#+HTML_HEAD: <style>.org-outline-1 { color: #0000ff; } window.location.href=\"Password:\"</style>\n"))

    (with-current-buffer org-buffer
      (insert (format "#+SETUPFILE: %s\n" theme-file))
      (insert "* Hello Pwd\n")
      (org-mode)
      
      (setq test-pwd-prompt-called nil)
      (advice-add 'read-passwd :override #'test-mock-read-passwd)
      
      (unwind-protect
          (let ((org-preview-impatient-body-only nil)
                (org-preview-impatient--output-buffer output-buffer))
            (org-preview-impatient--trigger-async-export (buffer-substring-no-properties (point-min) (point-max)))
            ;; Wait for async process to finish
            (let ((timeout 10) (waited 0))
              (while (and (not test-pwd-prompt-called)
                          (process-live-p org-preview-impatient--async-process)
                          (< waited timeout))
                (accept-process-output org-preview-impatient--async-process 0.5)
                (setq waited (+ waited 0.5))))
            
            (should-not test-pwd-prompt-called))
        (advice-remove 'read-passwd #'test-mock-read-passwd)
        (kill-buffer org-buffer)
        (kill-buffer output-buffer)
        (delete-directory theme-dir t)))))

(provide 'test-org-preview-impatient-password)
