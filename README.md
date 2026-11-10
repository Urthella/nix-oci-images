# nix-oci-images

The same small Go server, packaged as an OCI image six ways: with four Dockerfiles and two Nix
builders. CI measures them side by side: size, layers, files, whether there's a shell, known
CVEs, and whether building again gives the same image.

## Results

RESULTS

The numbers come from one CI run (`bash bench/run.sh`); every run puts a fresh table in its job
summary and uploads the details, including Trivy's reports and each image's file list.

## The six images

| Image | Built with |
|---|---|
| `debian` | A Dockerfile: `golang:1.27.3-trixie`, then `debian:trixie-slim` |
| `alpine` | A Dockerfile: `golang:1.27.3-alpine3.24`, then `alpine:3.24` |
| `distroless` | A Dockerfile: `golang:1.27.3-trixie`, then `gcr.io/distroless/static-debian13:nonroot` |
| `scratch` | A Dockerfile: `golang:1.27.3-trixie`, then `scratch`, the binary alone |
| `nix-dockertools` | nixpkgs' [`dockerTools.buildLayeredImage`](https://nixos.org/manual/nixpkgs/stable/#ssec-pkgs-dockerTools-buildLayeredImage) |
| `nix-nix2container` | [nix2container](https://github.com/nlewo/nix2container)'s `buildImage` |

The binary is built the same way in all six: Go 1.27, `CGO_ENABLED=0`, `-trimpath` and
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
- the other four don't;
- both Nix images come out identical when rebuilt.

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
