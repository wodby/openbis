-include env_make

# An openBIS release, such as 7.0.0. Its first two parts name the release line the image is published for (7.0).
# base-images.mk pins the matching official image.
OPENBIS_VER ?= 7.0.0
OPENBIS_VER_MINOR := $(basename $(OPENBIS_VER))

TAG ?= $(OPENBIS_VER_MINOR)

REPO = wodby/openbis
NAME = openbis-$(OPENBIS_VER_MINOR)

IMAGETOOLS_TAG ?= $(TAG)

ifneq ($(ARCH),)
	override TAG := $(TAG)-$(ARCH)
endif

.PHONY: build test push shell run clean buildx-imagetools-create image-ref

# Resolve the same pinned base image for every local and CI build target.
include base-images.mk

default: build

build:
	docker build --build-arg BASE_IMAGE="$(BASE_IMAGE)" --build-arg OPENBIS_VER="$(OPENBIS_VER)" -t $(REPO):$(TAG) ./

test:
	cd ./tests && IMAGE=$(REPO):$(TAG) NAME=$(NAME) ./run.sh

push:
	docker push $(REPO):$(TAG)

# CI combines the exact architecture images this workflow run pushed; see
# wodby/images arch-image-pins. Per-architecture tags are shared by every run,
# so an overlapping run may already have replaced one of them.
arch-image = $(if $(ARCH_IMAGE_PINS),$(or $(shell cat '$(ARCH_IMAGE_PINS)/$(subst :,_,$(subst /,_,$(1)))' 2>/dev/null),$(error No digest of $(1) was pushed by this workflow run)),$(1))

buildx-imagetools-create:
	docker buildx imagetools create -t $(REPO):$(IMAGETOOLS_TAG) \
				$(call arch-image,$(REPO):$(TAG)-amd64) \
				$(call arch-image,$(REPO):$(TAG)-arm64)

shell:
	docker run --rm --name $(NAME) -i -t $(PORTS) $(VOLUMES) $(ENV) --entrypoint bash $(REPO):$(TAG)

run:
	docker run --rm --name $(NAME) $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG) $(CMD)

clean:
	-docker rm -f $(NAME)

# Print the image make builds and pushes; CI pushes exactly this reference.
image-ref:
	@printf '%s\n' '$(REPO):$(TAG)'
