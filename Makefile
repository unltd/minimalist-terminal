.PHONY: build test lint run clean dev

dev:
	npm run dev

build:
	npm run build

test:
	pytest tests/test_mvp_dod.py -v

lint:
	npx tsc -noEmit -skipLibCheck

run:
	@echo "Use: ./scripts/run.sh <vault-path>"

clean:
	rm -f main.js main.js.map
	rm -rf node_modules/
