;; -*- lexical-binding: t -*-
(package "org-preview-impatient"
         "0.1.0"
         "Smooth, impatient Org-mode preview in browser")

(website-url "https://github.com/4honor/org-preview-impatient")
(keywords "org" "preview" "impatient" "html")

(package-file "org-preview-impatient.el")

(source "gnu")
(source "melpa")
(source "nongnu")

(script "test" "echo \"Running tests...\" && eask compile && eask install-deps --dev && eask ert ./tests/test-org-preview-impatient.el ./tests/test-org-preview-impatient-images.el ./tests/test-org-preview-impatient-integration.el ./tests/test-org-preview-impatient-setupfile.el")

(depends-on "emacs" "27.1")
(depends-on "async" "1.9.4")
(depends-on "simple-httpd" "1.5.1")
(depends-on "impatient-mode" "1.1.0")

(development
  (depends-on "f"))
