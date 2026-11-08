FROM golang:1.23-alpine AS build
WORKDIR /src
COPY app/api/go.mod app/api/go.sum ./
RUN go mod download
COPY app/api/*.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api .

FROM scratch
COPY --from=build /out/api /api
USER 65532:65532
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/api"]
