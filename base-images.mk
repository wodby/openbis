# Base image inputs shared by local builds and CI.
# The digest identifies the complete multi-platform image index of the official openBIS image.
BASE_IMAGE_REPOSITORY := openbis/openbis-app
BASE_IMAGE_TAG := 7.0.0
BASE_IMAGE_DIGEST := sha256:81fe770b2f0c30c8bb617a8b4d5f985637e0943bb34c6653a3746fab8adf476e

BASE_IMAGE = $(BASE_IMAGE_REPOSITORY):$(BASE_IMAGE_TAG)@$(BASE_IMAGE_DIGEST)
