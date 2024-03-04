# SPDX-FileCopyrightText: 2024 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Building multiarch Docker images turns out to be really annoying if you
# don't want to cycle everything through an external registry, and also if you
# need to run a build in emulation.
#
# Therefore `make` is set up to build and push the local architecture by
# default, as $REGISTRY/demo-external-base:$(VERSION)-$$(uname -m). You MUST
# set $REGISTRY to use this Makefile, and note that only amd64 and arm64 have
# been tested.
#
# `make multi` will build arm64 and amd64 images, push them both as
# $LOCAL_REGISTRY/demo-external-base:$(VERSION)-{platform}, and then use
# `docker manifest` to combine them into a multiplatform manifest pushed to
# $LOCAL_REGISTRY/demo-external-base:$(VERSION).
#
# `make push-multi` will retag the images built by `make multi` to use
# $REGISTRY instead of $LOCAL_REGISTRY, then push all three of them.
#
# The easy way to have a local registry on localhost:5000, as used for
# $LOCAL_REGISTRY by default, is:
#
# docker run --rm --name registry -p 5000:5000 registry:3.0.0-alpha.1

LOCAL_REGISTRY ?= localhost:5000
VERSION ?= 0.2.0
PROXY_VERSION ?= edge-24.2.5

all: single

registry-check:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "REGISTRY must be set (e.g. REGISTRY=docker.io/myregistry)" >&2 ;\
		exit 1 ;\
	fi
.PHONY: registry-check

# `make single` builds the image for the local architecture and pushes it to
# $REGISTRY/demo-external-base:$(VERSION)-$$(uname -m). This is the default
# target, but is arguably less useful than `make multi`.
single: registry-check
	docker buildx build \
		--build-arg VERSION=$(VERSION) \
		--build-arg PROXY_VERSION=$(PROXY_VERSION) \
		--push \
		-f Dockerfile.demo-external-base -t $(REGISTRY)/demo-external-base:$(VERSION)-$$(uname -m) \
		.

# `make multi` builds the image for both arm64 and amd64, pushes them to
# $LOCAL_REGISTRY/demo-external-base:$(VERSION)-{platform}, and then uses
# `docker manifest` to combine them into a multiplatform manifest pushed to
# $LOCAL_REGISTRY/demo-external-base:$(VERSION).
multi:
	docker buildx build \
		--build-arg VERSION=$(VERSION) \
		--build-arg PROXY_VERSION=$(PROXY_VERSION) \
		--push --platform=linux/arm64 \
		-f Dockerfile.demo-external-base -t $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-arm64 \
		.
	docker buildx build \
		--build-arg VERSION=$(VERSION) \
		--build-arg PROXY_VERSION=$(PROXY_VERSION) \
		--push --platform=linux/amd64 \
		-f Dockerfile.demo-external-base -t $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-amd64 \
		.
	-docker manifest rm $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)
	docker manifest create --insecure --amend $(LOCAL_REGISTRY)/demo-external-base:$(VERSION) \
		$(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-amd64 \
		$(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-arm64
	docker manifest inspect $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)
	docker manifest push --insecure $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)

# `make push-multi` retags the images built by `make multi` to use $REGISTRY
# instead of $LOCAL_REGISTRY, then pushes all three of them.
push-multi:
	docker tag $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-arm64 $(REGISTRY)/demo-external-base:$(VERSION)-arm64
	docker push $(REGISTRY)/demo-external-base:$(VERSION)-arm64
	docker tag $(LOCAL_REGISTRY)/demo-external-base:$(VERSION)-amd64 $(REGISTRY)/demo-external-base:$(VERSION)-amd64
	docker push $(REGISTRY)/demo-external-base:$(VERSION)-amd64
	docker manifest create --amend $(REGISTRY)/demo-external-base:$(VERSION) \
		$(REGISTRY)/demo-external-base:$(VERSION)-amd64 \
		$(REGISTRY)/demo-external-base:$(VERSION)-arm64
	docker manifest inspect $(REGISTRY)/demo-external-base:$(VERSION)
	docker manifest push $(REGISTRY)/demo-external-base:$(VERSION)
