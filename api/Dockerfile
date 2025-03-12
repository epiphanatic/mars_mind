# Build stage
FROM rust:1.85 AS builder
WORKDIR /usr/src/api
COPY . .
RUN cargo build --release

# Runtime stage
FROM debian:buster-slim
WORKDIR /app
COPY --from=builder /usr/src/api/target/release/api /app/api
RUN chmod +x /app/api  # Ensure the binary is executable
CMD ["/app/api"]