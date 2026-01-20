FROM perl:5.42-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

RUN cpanm App::cpanminus

COPY cpanfile /app/
RUN cpanm --notest --installdeps .

FROM perl:5.42-slim

WORKDIR /app

COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5
COPY --from=builder /usr/local/bin/cpanm /usr/local/bin/

COPY lib /app/lib
COPY bunkai.pl /app/bunkai.pl
COPY action-entrypoint.sh /app/action-entrypoint.sh

RUN chmod +x /app/action-entrypoint.sh

ENTRYPOINT ["perl", "/app/bunkai.pl"]
CMD ["--help"]
