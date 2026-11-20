# website_static

The container image that serves the old documents and pictures of
[verseghy-gimnazium.net](https://verseghy-gimnazium.net) under `/docs` and
`/images`: Red Hat's UBI 9 nginx 1.26 image with those files in its document
root. It is published as `ghcr.io/verseghy/website_static:<commit>`.

## This repository holds no content

The files are not in git, and they are not meant to be. They were built into
a container image once, in January 2022, from a build context that no longer
exists, and that image is the only place they are kept. This repository holds
only the recipe that copies them out of that image into a new one:

| File | Purpose |
|------|---------|
| `Containerfile` | The base image, the copy of the files, and how nginx starts |
| `nginx.d/port-in-redirect.conf` | The one nginx setting added to the base image's configuration (see below) |
| `.tekton/push.yaml` | The production build, run by Pipelines-as-Code on every push to `master` |
| `.gitignore` | Keeps `docs/` and `images/` out of git if a copy is extracted into the checkout |

`git clone` of this repository therefore never downloads the files; `podman
build` (or the production build) does, from the image named below.

## Where the files come from

The source is the image
`docker.io/verseghy/website_static@sha256:a65a68b8ca6fce6473d278fbd6bfed808bd3d3875630168fbd3f39aad9f7bfb5`,
the image that production ran before this one:

- It was built on 2022-01-09 at 14:18 UTC with BuildKit, from the official
  `nginx` image of that time (nginx 1.19.10 on Debian 10 "buster") and one
  layer, `COPY . /usr/share/nginx/html`, of 757 MB (725 MB compressed).
- The build context of that `COPY` no longer exists, and neither does the
  earlier GitHub repository of this name. The image is the only copy of the
  files.
- `/usr/share/nginx/html` holds 681 files in 15 directories, 756 MB in all:
  536 files under `docs/` (PDF, Word and PowerPoint documents, a few
  pictures and one HTML page), 137 pictures under `images/`, the nginx
  image's own `index.html` and `50x.html`, and two leftovers of the original
  build context, `Dockerfile` and an `.idea/` directory of IDE settings.

The `Containerfile` copies the `docs/` and `images/` directories of that
tree, and nothing else of it (see "What is left out"), into the new image's
document root, `/opt/app-root/src`. It runs `cp` on a read-only bind mount of
the old image, named by digest, rather than a `COPY`; the comment above that
step says why. Ownership (`root:root`), modes and modification times stay as
they were, those of `docs/` and `images/` themselves included, so the new
server answers with the same bytes, `Content-Type`, `ETag` and
`Last-Modified` as the old one.

Every image built from this repository carries `docs/` and `images/` as
well, in `/opt/app-root/src`. If the Docker Hub image ever disappears, change
the bind mount's `from=` to an earlier
`ghcr.io/verseghy/website_static:<commit>` image, by digest, and its
`source=` to `/opt/app-root/src`.

## What is left out

Only `docs/` and `images/` are copied. The other eight files of the old
document root are left out on purpose:

| Path | What it is |
|------|------------|
| `/index.html`, `/50x.html` | The welcome page and the error page of the official `nginx` image |
| `/Dockerfile` | The old image's recipe, left over from its build context |
| `/.idea/` (5 files) | IDE settings, left over from the same build context |

No Route publishes them, yet the replaced server handed them out on the
public Routes. The router matches a Route's path (`/docs`, `/images`) against
the request path as the client sent it. nginx resolves `..` segments in that
path only afterwards, percent-encoded ones (`%2e%2e`, `..%2f`) included. So a
request for `https://verseghy-gimnazium.net/docs/../Dockerfile`, sent as
written, passed the `/docs` Route and got the old server's `/Dockerfile`.
Browsers and plain `curl` resolve the `..` before sending; `curl
--path-as-is` does not. `/docs/../.idea/workspace.xml`, `/docs/../index.html`
and `/docs/../50x.html` worked the same way.

None of these files is part of the website's content, and the base image's
`nginx.conf` uses no error page file. This image answers 404 for every one of
them, and 403 for `/`.

## The image

- **Base:** `registry.access.redhat.com/ubi9/nginx-126`, pinned by tag and by
  the digest of the tag's multi-arch index. It is UBI 9 rather than UBI 10
  because UBI 10 needs x86-64-v3 CPUs, which some of the machines that build
  and run this image lack.
- **Configuration:** the base image's `/etc/nginx/nginx.conf` unchanged: one
  server on port 8080, plain HTTP/1.1 (no TLS, no HTTP/2), document root
  `/opt/app-root/src`. One file is added, `nginx.d/port-in-redirect.conf`,
  which the base configuration includes: without it, the redirect from a
  directory URL to the URL with a trailing slash (`/docs/szego` to
  `/docs/szego/`) would name port 8080, which nothing outside the cluster
  answers on.
- **Start:** `nginx -g 'daemon off;'` directly, not the base image's s2i run
  script, which writes to the root filesystem. nginx logs to the container's
  stdout and stderr.
- **User:** any UID in group 0. The files are owned by root and readable by
  everyone, so the server can read but not change them.
- **Writable paths:** nginx writes its pid file to `/run` and creates its
  temporary directories under `/var/lib/nginx/tmp`; both are writable by
  group 0. With a read-only root filesystem, mount an empty directory on each.

Try it locally:

```sh
podman build -t localhost/website_static:dev .
podman run --rm -p 127.0.0.1:8080:8080 localhost/website_static:dev
curl -I http://127.0.0.1:8080/docs/pdf.png
```

## How it is built and deployed

1. A push to `master` (in practice, a merged pull request) makes
   Pipelines-as-Code on the Verseghy hub cluster run `.tekton/push.yaml`. It
   builds the image with Shipwright and pushes
   `ghcr.io/verseghy/website_static:<full commit SHA>`. The Pipelines-as-Code
   `Repository` for this repository is
   `verseghy-website/builds/pac-repository-static.yaml` in
   [website_k8s](https://github.com/Verseghy/website_k8s).
2. Argo CD Image Updater sees the new tag and opens a pull request in
   website_k8s that moves `verseghy-website/static` to it. That pull request
   is reviewed and merged like any other there, and Argo CD rolls the
   Deployment.

website_k8s runs the image as the Deployment `static` under OpenShift's
restricted SCC (an arbitrary UID in group 0), with a read-only root
filesystem and empty directories on `/run` and `/var/lib/nginx/tmp`. Its
Service sends port 80 to the container's port 8080, and two Routes on
verseghy-gimnazium.net send `/docs` and `/images` to it, with TLS ending at
the Routes.

## Moving to a newer base image

The image changes only when the base image does: Red Hat publishes rebuilt
`ubi9/nginx-126` images with security fixes, and nothing else in the recipe
moves. To take one:

```sh
# The newest tags (they have the form 1-<build number>).
skopeo list-tags docker://registry.access.redhat.com/ubi9/nginx-126 | jq -r '.Tags[]' | grep -E '^1-[0-9]+$' | sort -t- -k2 -n | tail -3

# The digest of the tag's index, which the FROM line pins.
skopeo inspect --raw docker://registry.access.redhat.com/ubi9/nginx-126:<tag> | sha256sum

# The nginx build inside it, to compare with the build that Red Hat's
# advisory names as fixed.
podman run --rm --network none --entrypoint rpm registry.access.redhat.com/ubi9/nginx-126:<tag>@sha256:<digest> -q nginx-core
```

Then change the tag and the digest in the `FROM` line of the `Containerfile`
and merge that change to `master`; the build and the website_k8s pull request
follow by themselves.

For example, CVE-2026-123007 (nginx HTTP/2 flow control) is fixed for RHEL 9
nginx 1.26 by RHSA-2026:100745 (nginx-core
`1.26.3-10.module+el9.9.0+25360+9b756829.4`), published on 2026-11-20. The
base image pinned here, `1-1795131511`, built on 2026-11-19, still carries
`1.26.3-10.module+el9.9.0+25249+8b47ea83.1`, which predates that fix. This
server does not enable HTTP/2, the protocol the flaw is in; the next base
image that carries the fixed build is still the one to move to.

Stay on UBI 9: a UBI 10 base image does not run on the hub's CPUs, and the
build runs it there.

## License

The recipe in this repository is licensed under the Mozilla Public License
2.0 (see `LICENSE`), as the other Verseghy website repositories are. The
license does not cover the files that the image serves, which this repository
does not contain.
