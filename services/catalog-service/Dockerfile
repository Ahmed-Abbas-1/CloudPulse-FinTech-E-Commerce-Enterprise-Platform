FROM golang:1.22-alpine AS builder

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o /bin/catalog-service main.go

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /bin/catalog-service /catalog-service

USER 65532:65532
EXPOSE 8081
ENTRYPOINT ["/catalog-service"]
