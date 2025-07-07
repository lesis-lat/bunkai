FROM perl:5.36-slim AS builder

WORKDIR /app

RUN cpanm App::cpanminus

COPY cpanfile /app/
RUN cpanm --notest --installdeps .

FROM perl:5.36-slim

WORKDIR /app

COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5
COPY --from=builder /usr/local/bin/cpanm /usr/local/bin/

COPY lib /app/lib
COPY bunkai.pl /app/bunkai.pl

ENTRYPOINT ["perl", "/app/bunkai.pl"]
CMD ["--help"]