# A typical first image: the app on a slim Debian, with its shell and package manager.
FROM golang:1.27.3-trixie AS build
WORKDIR /src
COPY go.mod *.go ./
# The same flags as the Nix build: static, no paths baked in, no symbol table.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hello .

FROM debian:trixie-slim
COPY --from=build /out/hello /usr/local/bin/hello
USER 65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hello"]
