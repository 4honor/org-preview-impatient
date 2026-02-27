;;; test-org-preview-impatient.el --- Tests for org-preview-impatient -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-preview-impatient)

(ert-deftest test-org-preview-impatient-custom-port ()
  "Verify the default port is 8888."
  (should (= org-preview-impatient-port 8888)))

(ert-deftest test-org-preview-impatient-setup ()
  "Test if the output buffer is created and httpd-port is set."
  (with-temp-buffer
    (rename-buffer "test-org-file.org")
    (org-mode)
    ;; Mock browse-url to avoid opening real browser during tests
    (cl-letf (((symbol-function 'browse-url) (lambda (url) (message "Browsing to %s" url)))
              ((symbol-function 'httpd-start) (lambda () (message "Httpd started"))))
      (org-preview-impatient-mode 1)
      (unwind-protect
          (progn
            (should org-preview-impatient-mode)
            (should (buffer-live-p org-preview-impatient--output-buffer))
            (should (string-match-p "test-org-file.org" (buffer-name org-preview-impatient--output-buffer)))
            (should (= httpd-port 8888)))
        (org-preview-impatient-mode -1)))))

(ert-deftest test-org-preview-impatient-update-trigger ()
  "Test if editing triggers the debounce timer."
  (with-temp-buffer
    (rename-buffer "test-trigger.org")
    (org-mode)
    (cl-letf (((symbol-function 'browse-url) (lambda (_) nil))
              ((symbol-function 'httpd-start) (lambda () nil)))
      (org-preview-impatient-mode 1)
      (unwind-protect
          (progn
            ;; Verify the hook is added
            (should (memq #'org-preview-impatient--after-change after-change-functions))
            (should-not org-preview-impatient--timer)
            ;; Manually call the hook to simulate a change
            (org-preview-impatient--after-change)
            ;; Check if timer is set
            (should org-preview-impatient--timer)
            (should (timerp org-preview-impatient--timer)))
        (org-preview-impatient-mode -1)))))
