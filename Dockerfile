FROM  debian:buster-slim
USER bumper

LABEL org.opencontainers.image.title="bump-by-label"
LABEL org.opencontainers.image.description="A short description of the action."
LABEL org.opencontainers.image.url="https://github.com/https://github.com/herogold/bump-by-label.git"
LABEL org.opencontainers.image.documentation="https://github.com/https://github.com/herogold/bump-by-label.git"
LABEL org.opencontainers.image.source="https://github.com/https://github.com/herogold/bump-by-label.git"
LABEL org.opencontainers.image.revision="v0.0.0"
LABEL org.opencontainers.image.vendor="herogold"
LABEL org.opencontainers.image.authors="herogold"

COPY ./entrypoint.sh /usr/bin/entrypoint.sh

RUN chmod +x /usr/bin/entrypoint.sh


ENTRYPOINT [ "/usr/bin/entrypoint.sh" ]