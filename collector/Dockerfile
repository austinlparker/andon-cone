FROM golang:1.26-bookworm AS build

WORKDIR /src/collector
COPY collector/go.mod collector/go.sum* ./
RUN go mod download

COPY collector ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/andon-history-collector .

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=build /out/andon-history-collector /app/andon-history-collector

ENV SQLITE_PATH=/data/andon-history.sqlite3 \
    POLL_INTERVAL=1m

CMD ["/app/andon-history-collector"]
