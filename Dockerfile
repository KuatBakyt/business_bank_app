FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
COPY backend /app/
RUN useradd --create-home bank && mkdir -p /app/private_files /app/staticfiles && chown -R bank:bank /app
USER bank
RUN DJANGO_SECRET_KEY=build-only-not-for-runtime-abcdefghijklmnopqrstuvwxyz DATABASE_URL=postgresql://bank:bank@localhost/bank python manage.py collectstatic --noinput
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "60"]
