# Les commandes du projet, détaillées dans docs/runbook.md.
SWIFTC = xcrun swiftc -swift-version 6 -default-isolation MainActor \
	-enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
	-target arm64-apple-macos26.0
NOYAU = Cockpit/Store/*.swift Cockpit/Collecte/*.swift
SCRATCH ?= .cache/spm
APP = build/Build/Products/Debug/Cockpit.app

.PHONY: projet build run test essai

projet:
	@test -f Local.xcconfig || (echo "Local.xcconfig manque : lance claude puis /installer, ou écris DEVELOPMENT_TEAM = <ton Team ID> dedans." && exit 1)
	@xcodegen generate --quiet

build: projet
	@xcodebuild -project Cockpit.xcodeproj -scheme Cockpit -configuration Debug -derivedDataPath build -destination "platform=macOS,arch=arm64" -quiet build

run: build
	@pkill -x Cockpit || true
	@open $(APP)

test:
	@swift test --scratch-path $(SCRATCH) --quiet

# Une source seule contre les vraies API, sur .cache/essai.sqlite : make essai SOURCE=PostHog
essai:
	@test -n "$(SOURCE)" || (echo "usage : make essai SOURCE=PostHog" && exit 1)
	@mkdir -p .cache/essai-$(SOURCE)
	@sed 's/SOURCE()/$(SOURCE)()/' outils/essai.swift > .cache/essai-$(SOURCE)/main.swift
	@$(SWIFTC) $(NOYAU) Cockpit/Sources/$(SOURCE).swift $(wildcard Cockpit/Sources/$(SOURCE)+*.swift) \
		.cache/essai-$(SOURCE)/main.swift -o .cache/essai-$(SOURCE)/essai
	@.cache/essai-$(SOURCE)/essai
