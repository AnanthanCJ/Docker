FROM python:3.15-slim-trixie AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install -r requirements.txt

FROM python:3.15-slim-trixie

WORKDIR /app

COPY --from=builder /usr/local/lib/python3.15/site-packages /usr/local/lib/python3.15/site-packages

COPY . .

RUN useradd --create-home appuser
USER appuser

EXPOSE 5000

ENTRYPOINT ["python"]

CMD ["app.py"]