# syntax=docker/dockerfile:1.3
FROM alpine:latest
WORKDIR /root/
COPY bucket_watcher.elf ./app.elf
CMD ["./app.elf"]  
