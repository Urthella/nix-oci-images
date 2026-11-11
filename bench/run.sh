#!/usr/bin/env bash
# Builds the same server as six OCI images, measures each one, and checks the claims the README
# makes about them. Needs docker, nix (with flakes), jq and curl. Writes results/results.jsonl
# and results/results.md, and exits non-zero if a check fails.
set -euo pipefail
cd "$(dirname "$0")/.."

variants=(debian alpine distroless distroless-reproducible scratch nix-dockertools nix-nix2container)
trivy=aquasec/trivy:0.76.2
mkdir -p results/trivy-cache
: > results/results.jsonl
failed=0
check() {
  if [ "$1" = "$2" ]; then echo "ok    $3"; else echo "FAIL  $3 (got $1, want $2)"; failed=1; fi
}

# Builds one variant into the local docker daemon as hello:<variant>, from scratch each time.
build() {
  case $1 in
    nix-dockertools)
      nix build --quiet "${@:2}" .#image-dockertools -o results/dockertools
      docker load -q < results/dockertools ;;
    nix-nix2container)
      nix build --quiet "${@:2}" .#image-nix2container -o results/nix2container
      nix run --quiet .#image-nix2container.copyToDockerDaemon ;;
    distroless-reproducible)
      # The distroless Dockerfile, unchanged. SOURCE_DATE_EPOCH pins the image's created time
      # and history; rewrite-timestamp pins the timestamps of the files in new layers.
      docker buildx build --quiet --no-cache --builder reproducible --build-arg SOURCE_DATE_EPOCH=0 \
        --output "type=docker,name=hello:$1,rewrite-timestamp=true" -f docker/distroless.Dockerfile app ;;
    *)
      docker build -q --no-cache -f "docker/$1.Dockerfile" -t "hello:$1" app ;;
  esac > /dev/null
}

# rewrite-timestamp needs a BuildKit builder of its own, rather than the one inside dockerd.
docker buildx create --name reproducible --driver docker-container > /dev/null 2>&1 || true

for v in "${variants[@]}"; do
  image="hello:$v"
  start=$(date +%s.%N)
  build "$v"
  seconds=$(awk "BEGIN { printf \"%.1f\", $(date +%s.%N) - $start }")

  id=$(docker image inspect -f '{{.Id}}' "$image")
  layers=$(docker image inspect -f '{{len .RootFS.Layers}}' "$image")

  # Measured from the exported filesystem, the same way for every image. (Docker's own size
  # figure isn't comparable: with the containerd image store it counts pulled layers
  # compressed and loaded ones uncompressed.)
  container=$(docker create "$image")
  docker export "$container" > results/fs.tar
  docker rm "$container" > /dev/null
  compressed=$(gzip -9 -c results/fs.tar | wc -c)
  # Leave out the files Docker adds to every container, which aren't part of the image.
  tar -tvf results/fs.tar | awk '{ print substr($1, 1, 1), $3, $6 }' \
    | grep -Ev ' (\./)?(\.dockerenv|etc/hosts|etc/hostname|etc/resolv\.conf|etc/mtab|dev/console)$' > "results/files-$v.txt" || true
  rm results/fs.tar
  files=$(grep -c '^-' "results/files-$v.txt" || true)
  unpacked=$(awk '$1 == "-" { total += $2 } END { print total + 0 }' "results/files-$v.txt")
  shell=no
  if grep -Eq ' (\./)?(usr/)?bin/(ba|da|a)?sh$' "results/files-$v.txt"; then shell=yes; fi

  # Start it and ask it for /healthz, the way an orchestrator would.
  container=$(docker run -d -p 127.0.0.1::8080 "$image")
  port=$(docker port "$container" 8080/tcp | head -n 1 | sed 's/.*://')
  healthy=no
  for _ in $(seq 1 50); do
    if [ "$(curl -fsS "http://127.0.0.1:$port/healthz" 2> /dev/null)" = ok ]; then healthy=yes; break; fi
    sleep 0.1
  done
  docker rm -f "$container" > /dev/null

  # Build it again: the Dockerfiles from scratch with --no-cache, and Nix with --rebuild, which
  # builds the derivation again and fails if a single output byte differs.
  rebuilt=yes
  if [[ $v == nix-* ]]; then
    nix build --quiet --rebuild .#hello > /dev/null 2>&1 || rebuilt=no
    build "$v" --rebuild || rebuilt=no
  else
    build "$v"
  fi
  reproducible=no
  if [ "$rebuilt" = yes ] && [ "$(docker image inspect -f '{{.Id}}' "$image")" = "$id" ]; then reproducible=yes; fi

  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/results/trivy-cache:/root/.cache/trivy" \
    "$trivy" image --quiet --format json "$image" > "results/trivy-$v.json"
  vulnerabilities=$(jq '[.Results[]?.Vulnerabilities[]?] | length' "results/trivy-$v.json")
  serious=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH" or .Severity == "CRITICAL")] | length' "results/trivy-$v.json")

  jq -cn --arg variant "$v" --arg id "$id" --argjson unpacked "$unpacked" --argjson compressed "$compressed" \
    --argjson layers "$layers" --argjson files "$files" --arg shell "$shell" --arg healthy "$healthy" \
    --arg reproducible "$reproducible" --argjson seconds "$seconds" \
    --argjson vulnerabilities "$vulnerabilities" --argjson serious "$serious" \
    '$ARGS.named' >> results/results.jsonl

  check "$healthy" yes "$v answers /healthz"
  case $v in
    debian | alpine) check "$shell" yes "$v has a shell (so the shell check can see one)" ;;
    *) check "$shell" no "$v has no shell" ;;
  esac
  if [[ $v == nix-* || $v == *-reproducible ]]; then check "$reproducible" yes "$v is the same image when rebuilt"; fi
done

go_docker=$(docker run --rm golang:1.27.3-trixie go version | awk '{ print $3 }')
go_nix=$(nix develop --command go version | awk '{ print $3 }')
nixpkgs=$(jq -r '.nodes.nixpkgs.locked.rev[0:12]' flake.lock)
{
  echo "Measured $(date -u +%Y-%m-%d) on $(uname -m), Go $go_docker in the Dockerfiles and $go_nix from nixpkgs $nixpkgs."
  echo
  echo "| Image | Compressed | Unpacked | Layers | Files | Shell | CVEs (high + critical) | Same image on rebuild | Cold build |"
  echo "|---|---:|---:|---:|---:|---|---:|---|---:|"
  jq -r '"| \(.variant) | \(.compressed / 1048576 * 10 | round / 10) MB | \(.unpacked / 1048576 * 10 | round / 10) MB | \(.layers) | \(.files) | \(.shell) | \(.vulnerabilities) (\(.serious)) | \(.reproducible) | \(.seconds) s |"' results/results.jsonl
} > results/results.md
cat results/results.md
exit "$failed"
