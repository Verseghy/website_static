# website_static: the files that verseghy-gimnazium.net serves under /docs and
# /images, on Red Hat's UBI 9 nginx 1.26 image. This repository holds the
# recipe only: the files themselves come out of the image that the second RUN
# below mounts, at build time. README.md says where they come from and why
# they are not in git.

# Red Hat's nginx 1.26 on UBI 9, pinned by tag and by the digest of the tag's
# multi-arch index, so a moved tag cannot change what is built. UBI 9, not 10:
# UBI 10 needs x86-64-v3 CPUs, which the hub lacks, and the hub runs this
# build (the RUNs below execute the base image) as well as staging. README.md,
# "Moving to a newer base image", says how to bump it.
FROM registry.access.redhat.com/ubi9/nginx-126:1-1795131511@sha256:c5303082ec29d413cefea933e1bdc46d4c1f8d41fe00b2ff829b0a1b31887b2e

# Set by .tekton/push.yaml to the commit being built.
ARG SOURCE_COMMIT=unknown

# Replace the labels that name Red Hat's nginx-126 image itself, so that an
# inspection of this image does not present it as that image. The labels that
# describe the Red Hat base build (com.redhat.*, cpe, version, release,
# build-date) stay: scanners use them to match RHEL errata.
LABEL name="verseghy/website_static" \
      summary="The /docs and /images files of verseghy-gimnazium.net, served by nginx 1.26" \
      description="Red Hat's UBI 9 nginx 1.26 image with the documents and pictures that verseghy-gimnazium.net serves under /docs and /images." \
      io.k8s.display-name="Verseghy website static files" \
      io.k8s.description="Red Hat's UBI 9 nginx 1.26 image with the documents and pictures that verseghy-gimnazium.net serves under /docs and /images." \
      io.openshift.tags="nginx,static" \
      io.openshift.expose-services="8080:http" \
      usage="podman run --rm -p 127.0.0.1:8080:8080 ghcr.io/verseghy/website_static:<commit>" \
      help="https://github.com/Verseghy/website_static" \
      url="https://github.com/Verseghy/website_static" \
      maintainer="Verseghy" \
      vendor="Verseghy" \
      vcs-type="git" \
      vcs-ref="${SOURCE_COMMIT}" \
      org.opencontainers.image.source="https://github.com/Verseghy/website_static" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}"

# nginx's logs go to the container's stdout and stderr. The image's s2i run
# script makes these links when the container starts, which needs a writable
# root filesystem; made here, they let nginx start directly (CMD below) on a
# read-only one. The base image runs this as its user 1001, which owns
# /var/log/nginx.
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# The image's /etc/nginx/nginx.conf stays as Red Hat ships it (listen 8080,
# root /opt/app-root/src) and includes these files at http level. The one
# file here keeps directory redirects as the replaced server sent them; it
# says why.
COPY nginx.d/ /opt/app-root/etc/nginx.d/

# The files, out of the last image that was built from them, by digest (see
# README.md, "Where the files come from"): its docs/ and images/ directories,
# the two that the Routes publish, and nothing else of its document root. The
# rest of that tree (the nginx image's own index.html and 50x.html, and the
# Dockerfile and .idea/ directory left over from its build context) is left
# out on purpose: the replaced server handed those files out to requests such
# as /docs/../Dockerfile, which the /docs Route accepts (README.md, "What is
# left out").
#
# cp, run as root, keeps the owner (root:root), the mode (0755 for
# directories and files alike) and the modification time of every file and
# directory as they are in that image, docs/ and images/ themselves included.
# Every user can therefore read the files: OpenShift's restricted SCC runs
# nginx under an arbitrary UID in group 0, which can read them but not change
# them. ETag and Last-Modified stay as the replaced server sent them. The
# bind mount is read-only and leaves nothing behind; only the copies land in
# this layer.
#
# A COPY instruction cannot do this. COPY of a directory copies what is in it
# into a new directory, dated at build time. COPY --parents keeps the
# directory as it is, but the buildah of the production build strategy
# (1.43.3; 1.46 does not) also copies the first directory of the source path,
# so the document root would gain an empty usr/.
USER 0
RUN --mount=type=bind,from=docker.io/verseghy/website_static@sha256:a65a68b8ca6fce6473d278fbd6bfed808bd3d3875630168fbd3f39aad9f7bfb5,source=/usr/share/nginx/html,target=/mnt/website_static \
    cp -R --no-dereference --preserve=mode,ownership,timestamps \
      /mnt/website_static/docs /mnt/website_static/images /opt/app-root/src/
# Back to the base image's user. nginx runs as it locally; OpenShift replaces
# it with an arbitrary UID.
USER 1001

# nginx itself in the foreground, not the image's default (a usage message)
# or its s2i run script, which writes to the root filesystem at start. It
# writes only its pid file (/run/nginx.pid) and the temp directories that it
# creates at start under /var/lib/nginx/tmp; both directories are writable by
# group 0. The image's stop signal, SIGQUIT, lets requests in flight finish.
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
