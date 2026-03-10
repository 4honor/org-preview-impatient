.PHONY: test compile clean

test:
	eask install-deps --dev
	eask test ert tests/test-*.el

compile:
	eask compile

setup-ellsp:
	eask install ellsp --dev
	find .eask -type f -name "install-ellsp" -exec bash {} \;

clean:
	eask clean
