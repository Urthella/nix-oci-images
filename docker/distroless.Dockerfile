# Google's distroless static base: CA certificates, tzdata and a passwd file, no shell.
FROM golang:1.27.3-trixie AS build
WORKDIR /src
COPY go.mod *.go ./
# The same flags as the Nix build: static, no paths baked in, no symbol table.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hello .

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/hello /usr/local/bin/hello
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hello"]
