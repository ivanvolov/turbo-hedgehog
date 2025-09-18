# Tests

t:
	clear && python3 cmd/test.py

# Simulations

sim:
	clear && python3 cmd/simulate.py

# Maintenance scripts

build:
	clear && python3 cmd/build.py

# Deploy & verify

deploy:
	clear && python3 cmd/deploy.py

verify:
	clear && python3 cmd/verify.py