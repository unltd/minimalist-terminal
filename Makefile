.PHONY: build test lint run clean dev

dev:
	npm run dev

build:
	npm run build

test:
	gauge run tests/specs/ || true
	pytest tests/ -v

lint:
	npx tsc -noEmit -skipLibCheck

run:
	@echo "Use: ./scripts/run.sh <vault-path>"

clean:
	rm -f main.js main.js.map
	rm -rf node_modules/
