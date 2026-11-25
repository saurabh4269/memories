# Memories: convenience targets. Commands mirror server/README.md and deploy/README.md.
# deploy targets assume keys are loaded (`source deploy/env.sh`) and SSH access to the VM.
.PHONY: help server-dev server-test deploy-ml surge app-sync app-run-android app-build-apk

APP_DIR := app/mobile

help:
	@grep -E '^[a-z-]+:' Makefile | cut -d: -f1

server-dev:            ## run the director API locally on :8000 (env: server/.env.example)
	cd server && uv sync && uv run uvicorn memories.api:app --port 8000

server-test:
	cd server && uv run pytest -q

deploy-ml:             ## (re)deploy Immich ML to the k3s cluster on the VM
	cd deploy && k8s/apply-ml.sh

surge:                 ## Diwali-night surge loop: burst -> OOM -> NudgeBee -> approval -> Flagsmith -> restore
	cd deploy && surge/run.sh

app-sync:              ## copy the Flutter fork from knowledge-dump into app/ (maintainers only)
	scripts/sync_app.sh

app-run-android:       ## run the Flutter app on a connected Android device/emulator
	@echo "TODO: confirm app run steps in app docs (codegen may be needed: lib/generated is gitignored upstream)"
	cd $(APP_DIR) && flutter pub get && flutter run

app-build-apk:
	@echo "TODO: confirm release signing/flavor in app docs"
	cd $(APP_DIR) && flutter pub get && flutter build apk --release
