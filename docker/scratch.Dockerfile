# Nothing but the binary.
FROM golang:1.27.3-trixie AS build
WORKDIR /src
COPY go.mod *.go ./
# The same flags as the Nix build: static, no paths baked in, no symbol table.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hello .

FROM scratch
COPY --from=build /out/hello /hello
USER 65532
EXPOSE 8080
ENTRYPOINT ["/hello"]
