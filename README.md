# Business Bank API

[![Backend checks](https://github.com/KuatBakyt/business_bank_app/actions/workflows/backend.yml/badge.svg)](https://github.com/KuatBakyt/business_bank_app/actions/workflows/backend.yml)

Учебный банковский кабинет для ИП и малого бизнеса. Только тестовые средства и вымышленные данные. На этом этапе реализуется **backend**, фронтенда нет.

Python 3.12 · Django REST Framework · PostgreSQL 16 · JWT · Celery · Redis · Docker.

## Возможности

- Пользователи по email, JWT с ротацией refresh и blacklist.
- Компании, владелец, бухгалтер и наблюдатель; изоляция компаний.
- Счета KZT с внутренними номерами DEMO, закрытие пустых счетов.
- Черновики платежей, отправка, одобрение, отклонение и отмена.
- Двойная запись, Decimal, блокировки PostgreSQL, идемпотентные запросы.
- Ограничительные триггеры БД: баланс проводок, сверка кеша, неизменяемость истории.
- CSV/PDF выписки через Celery; закрытая выдача, срок хранения 24 часа.
- Аудит, Swagger, seed_demo, reconcile, CI с настоящей PostgreSQL.

## Запуск на Windows

Нужны Git и Docker Desktop. В PowerShell:

```powershell
git clone https://github.com/KuatBakyt/business_bank_app.git
cd business_bank_app
Copy-Item .env.example .env
```

В `.env` задайте случайный `DJANGO_SECRET_KEY`, собственный `POSTGRES_PASSWORD` и такой же пароль в `DATABASE_URL`. Если пароль содержит специальные символы URL, закодируйте их в DATABASE_URL. Задайте `DEMO_PASSWORD` не короче 8 символов для учебных пользователей.

```powershell
docker compose build
docker compose up -d db redis
docker compose run --rm api python manage.py migrate
docker compose run --rm api python manage.py seed_demo
docker compose up -d
```

- Swagger: http://localhost:8000/api/docs/
- OpenAPI: http://localhost:8000/api/schema/
- ReDoc: http://localhost:8000/api/redoc/
- Состояние: http://localhost:8000/health/ready/

На Linux/macOS вместо Copy-Item используйте `cp .env.example .env`.

Учебные пользователи: `owner@demo.example`, `accountant@demo.example`, `viewer@demo.example`, `partner@demo.example`. Пароль — ваш DEMO_PASSWORD. Повтор seed_demo не меняет пароли и не пополняет повторно. Счета: `DEMO-KUAT-001` и `DEMO-VECTOR-001`, начальное пополнение по 1 000 000 KZT.

## Первый перевод через Swagger

1. `POST /api/v1/auth/login/`: email и password. Скопируйте access в Authorize (схема JWT).
2. `GET /api/v1/companies/` — UUID компании. `GET /api/v1/companies/{id}/accounts/` — UUID своего счёта.
3. `POST /api/v1/recipients/resolve/` с `{"number":"DEMO-VECTOR-001"}` — UUID счёта получателя.
4. `POST /api/v1/companies/{id}/payments/` с source, destination, amount `"10000.00"`, purpose. Укажите новый `Idempotency-Key`.
5. `POST /api/v1/payments/{id}/submit/`, затем `approve/` под владельцем. Тело `{}`; для каждого действия свой ключ.
6. Откройте операции обоих счетов под соответствующими пользователями. Вызовите reconcile.

Повтор с тем же ключом и телом возвращает прежний успешный результат. Иное тело — 409. Деньги списываются при одобрении, ожидающий платёж их не резервирует. Владелец вправе одобрить собственный платёж.

## Проверки

```powershell
docker compose run --rm api python -m pytest
```

Либо локально из корня репозитория:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DJANGO_SECRET_KEY='local-test-only-secret-abcdefghijklmnopqrstuvwxyz'
$env:DATABASE_URL='postgresql://bank:your-password@localhost:5432/bank_test'
pytest
ruff check .
ruff format --check .
python backend/manage.py makemigrations --check --dry-run
```

Локальная PostgreSQL должна быть доступна; роль тестов должна иметь CREATEDB. Compose не публикует PostgreSQL наружу. SQLite не поддерживается: приложение намеренно требует PostgreSQL и её ограничительные триггеры.

```powershell
docker compose run --rm api python manage.py reconcile
docker compose logs -f api worker beat
docker compose down
```

Не добавляйте `-v` к down, если нужно сохранить учебные данные. Запускайте только один beat. Выписки попадают в очередь БД; beat подбирает их раз в минуту, worker генерирует файл. Скачивание доступно через авторизованный API, папка private_files не публикуется как media.

## Документация

- [Архитектура](docs/architecture.md)
- [Денежная модель](docs/money-model.md)
- [Сценарий демонстрации](docs/demo.md)
- [Измерения производительности](docs/performance.md)

Это учебный backend, без реальных банковских подключений, KYC, эквайринга и фронтенда. HTTPS staging не развёрнут. Фактическую проверку смотрите в CI, показатели производительности ещё не измерены.
