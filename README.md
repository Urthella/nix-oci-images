# nix-oci-images

The same small Go server, packaged as an OCI image six ways: with four Dockerfiles and two Nix
builders, plus one of the Dockerfiles built a second way, to be reproducible. CI measures them
side by side: size, layers, files, whether there's a shell, known CVEs, and whether building
again gives the same image.

## Results

Measured 2026-11-10 on x86_64 in [this CI run](https://github.com/Urthella/nix-oci-images/actions/runs/42784189589),
with Go 1.27.3 on both sides and nixpkgs `f4a03c008967`:

| Image | Compressed | Unpacked | Layers | Files | Shell | CVEs (high + critical) | Same image on rebuild | Cold build |
|---|---:|---:|---:|---:|---|---:|---|---:|
| debian | 30.9 MB | 80.8 MB | 2 | 2677 | yes | 187 (48) | no | 27.9 s |
| alpine | 5.9 MB | 13.6 MB | 2 | 83 | yes | 1 (0) | no | 16.2 s |
| distroless | 3.2 MB | 7.8 MB | 14 | 961 | no | 0 (0) | no | 11.5 s |
| distroless-reproducible | 3.2 MB | 7.8 MB | 14 | 961 | no | 0 (0) | yes | 30.5 s |
| scratch | 2.3 MB | 5.6 MB | 1 | 1 | no | 0 (0) | no | 10.5 s |
| nix-dockertools | 3.0 MB | 8.0 MB | 5 | 1211 | no | 0 (0) | yes | 24.2 s |
| nix-nix2container | 3.0 MB | 8.0 MB | 1 | 1211 | no | 0 (0) | yes | 114.4 s |

Every run puts a fresh table in its job summary and uploads the details, including Trivy's
reports and each image's file list.

What stands out:

- **By default, only the Nix images come out the same when rebuilt.** Rebuilding a Dockerfile
  gives a new image ID even when nothing changed, because timestamps end up in the layers and
  the config. A Dockerfile can be reproducible too, but you have to ask for it:
  `distroless-reproducible` is the unchanged distroless Dockerfile, built with
  `SOURCE_DATE_EPOCH=0`, which pins the created time and history, and BuildKit's
  `rewrite-timestamp=true`, which pins the timestamps of files in new layers. It came out
  identical on rebuild. `rewrite-timestamp` needs a `docker-container` builder, not the one
  built into dockerd:

  ```sh
  docker buildx create --name reproducible --driver docker-container
  docker buildx build --builder reproducible --build-arg SOURCE_DATE_EPOCH=0 \
    --output type=docker,name=hello:distroless-reproducible,rewrite-timestamp=true \
    -f docker/distroless.Dockerfile app
  ```
- **The Nix images aren't just the binary.** nixpkgs patches Go's standard library to find time
  zones, `/etc/services` and MIME types at store paths. Those paths are baked into the binary,
  so Nix keeps tzdata, iana-etc and mailcap in the image: 1,210 of its 1,211 files. That puts
  them at distroless's size, which carries tzdata on purpose, rather than scratch's.
- **The CVEs live in the base.** Debian slim brings 187 findings, 48 of them high or critical, in
  packages the server never uses. The images without an OS show none, because Trivy then only
  checks the Go binary.
- **Layers differ by builder.** `dockerTools.buildLayeredImage` makes one layer per store path.
  nix2container puts everything in one layer unless you split it. Distroless inherits 14 layers
  from its base.

## The images

| Image | Built with |
|---|---|
| `debian` | A Dockerfile: `golang:1.27.3-trixie`, then `debian:trixie-slim` |
| `alpine` | A Dockerfile: `golang:1.27.3-alpine3.24`, then `alpine:3.24` |
| `distroless` | A Dockerfile: `golang:1.27.3-trixie`, then `gcr.io/distroless/static-debian13:nonroot` |
| `distroless-reproducible` | The same Dockerfile, built with `SOURCE_DATE_EPOCH=0` and BuildKit's `rewrite-timestamp` |
| `scratch` | A Dockerfile: `golang:1.27.3-trixie`, then `scratch`, the binary alone |
| `nix-dockertools` | nixpkgs' [`dockerTools.buildLayeredImage`](https://nixos.org/manual/nixpkgs/stable/#ssec-pkgs-dockerTools-buildLayeredImage) |
| `nix-nix2container` | [nix2container](https://github.com/nlewo/nix2container)'s `buildImage` |

The binary is built the same way in all of them: Go 1.27, `CGO_ENABLED=0`, `-trimpath` and
`-ldflags "-s -w"`. Every image runs it as user 65532 on port 8080.

## What's measured

- **Compressed:** `docker save | gzip -9`. This is close to what a registry stores and a node
  downloads.
- **Uncompressed:** the size Docker reports for the image.
- **Layers** and **files:** the layer count, and the regular files in `docker export`.
- **Shell:** whether the image contains `/bin/sh` or a similar shell, which an attacker who gets
  in would use.
- **CVEs:** [Trivy](https://trivy.dev) 0.76.2, counting all findings, with high and critical
  ones in brackets. For the Nix images Trivy finds no OS packages, so it only checks the Go
  binary.
- **Same image on rebuild:** each Dockerfile is built again with `--no-cache` and the image IDs
  are compared. Each Nix image is built again with `nix build --rebuild`, which rebuilds the
  derivation and fails if a single byte of the output differs, and the IDs are compared too.
- **Cold build:** the wall time of the first build, including pulling base images or fetching
  Nix's toolchain from the binary cache. It's one run on a shared runner, so read it loosely.

The run fails if any of these don't hold:

- every image answers `GET /healthz` with `ok`;
- the Debian and Alpine images have a shell, which proves the shell check can see one;
- the others don't;
- both Nix images and the reproducible distroless build come out identical when rebuilt.

## Run it

On Linux with Docker and Nix (flakes enabled):

```sh
nix develop --command bash -c 'cd app && go test ./...'
bash bench/run.sh
```

The results land in `results/`.

## Caveats

- The Go patch version can differ between the `golang` image and nixpkgs. Both versions are
  printed above the table.
- Trivy's counts change as its database does; they describe the day of the run.
- The base images are pinned by tag, not by digest, so a later run can pick up updated bases.

## License

MIT
