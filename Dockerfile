FROM golang:1.24-alpine AS build

WORKDIR /app
COPY . .
RUN go build -o web ./cmd/web
RUN go build -o worker ./cmd/worker

FROM alpine:3.21
COPY --from=build /app/web /usr/local/bin/web
COPY --from=build /app/worker /usr/local/bin/worker