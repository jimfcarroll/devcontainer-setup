# This project's additions to the template's settings in ../conf.sh.
#
# init.sh seeds this file once and never overwrites it, not even with --reset.
# project-specific/Dockerfile copies it into the image as root, as its last
# step, and the egress firewall sources that copy after the template's. A change
# here therefore reaches the firewall only when the container is rebuilt. The
# file is sourced by bash as root, so it holds plain assignments and nothing
# else.
#
# To let the container reach more hosts, append them:
#
#   FIREWALL_ALLOWED_DOMAINS+=("repo.maven.apache.org" "repo1.maven.org")
#
# To lift the firewall entirely:
#
#   FIREWALL_ALLOW_ALL=true
#
# BASE_IMAGE_VERSION is read from the template's conf.sh alone, so setting it
# here has no effect.
