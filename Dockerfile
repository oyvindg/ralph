FROM alpine:3.23

RUN apk add --no-cache bash git curl npm

# Install codex CLI (adjust if install method changes)
RUN npm install -g @openai/codex

WORKDIR /workspace

COPY ralph.sh /usr/local/bin/ralph
RUN chmod +x /usr/local/bin/ralph

ENTRYPOINT ["ralph"]
