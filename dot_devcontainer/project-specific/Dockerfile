# The project's layer on top of the template's shared base image.
#
# ensure-base-image.sh builds the base image from .devcontainer/Dockerfile and
# points this project's alias at it, and devcontainer.json passes that alias in
# as BASE_IMAGE. Everything this project needs beyond the template belongs in
# this directory. init.sh seeds this file once and never overwrites it, not
# even with --reset, while the rest of .devcontainer/ except devcontainer.json
# belongs to the template and is replaced on every run.
#
# The build context is this directory, so COPY paths are relative to it.
#
# The base image ends as the node user. Switch to USER root for steps that need
# root, such as installing system packages, and switch back to USER node before
# the end, because the container runs as node.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Add this project's steps above this line.

# Keep this step last. It bakes this project's conf.sh into the image as root,
# which is the only copy the egress firewall reads. Because it comes last, an
# edit to conf.sh rebuilds only this step, not every layer above it.
COPY --chown=root:root --chmod=0644 conf.sh /etc/devcontainer/project-specific/conf.sh
