# The app on Alpine: small, but still a shell and apk.
FROM golang:1.27.3-alpine3.24 AS build
WORKDIR /src
COPY go.mod *.go ./
# The same flags as the Nix build: static, no paths baked in, no symbol table.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hello .

FROM alpine:3.24
COPY --from=build /out/hello /usr/local/bin/hello
USER 65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hello"]
