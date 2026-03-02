.PHONY: test compile clean

test:
	eask install-deps --dev
	eask test ert tests/test-*.el

compile:
	eask compile

clean:
	eask clean
