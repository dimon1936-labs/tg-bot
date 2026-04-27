# Birthday Reminder Bot

Telegram бот для нагадувань про дні народження контактів.
Збудований на **Node-RED + PostgreSQL + Together AI** через raw HTTP до Telegram Bot API, без спеціальної Telegram-ноди.

## Можливості

- Реєстрація користувача через Telegram `shareContact`.
- Додавання контактів через FSM: ім'я -> дата -> підтвердження.
- Список контактів, перегляд деталей, видалення тільки власних записів.
- Запити природною мовою через Together AI, наприклад: `коли у Олі ДН?`.
- AI-ідеї подарунків з урахуванням інтересів контакту.
- Нагадування за 7, 3, 1 день і в день народження.
- Audit log для ключових дій і помилок.

## Архітектура

```text
Telegram Bot API <-> Node-RED long polling <-> PostgreSQL
                         |
                         v
                 Together AI REST API
```

DB schema доступна в `db/dbdiagram.dbml`, а ручна перевірка перед здачею описана в `docs/TEST_CASES.md`.

## Quickstart

1. Створи `.env`:

```bash
cp .env.example .env
```

Заповни `TELEGRAM_BOT_TOKEN`, `TOGETHER_API_KEY`, `ADMIN_TELEGRAM_ID`.

2. Підніми інфраструктуру:

```bash
docker-compose up -d --build
```

3. Застосуй міграції:

```powershell
.\apply_migrations.ps1
```

4. Імпортуй або задеплой `flows.json`:

```powershell
.\redeploy.ps1
```

Альтернатива: відкрити http://localhost:1881, Menu -> Import -> `flows.json` -> Deploy.

5. Напиши боту `/start` у Telegram.

## Сервіси

- Node-RED UI: http://localhost:1881
- PostgreSQL: `localhost:5434`
- DB: `birthday_bot`
- DB user: `postgres`

## Як Користуватись Ботом

### 1. Реєстрація

Користувач пише `/start`. Бот просить поділитися контактом через Telegram reply keyboard. Після shareContact бот створює або оновлює запис у `users` і показує головне меню.

Якщо користувач вже зареєстрований, `/start` не просить телефон повторно, а одразу відкриває меню.

### 2. Головне меню

Після реєстрації бот відкриває inline menu:

- Додати контакт
- Контакти
- Найближчі
- Допомога

Меню працює через callback queries і raw Telegram REST methods: `sendMessage`, `sendPhoto`, `editMessageText`, `editMessageMedia`, `answerCallbackQuery`.

### 3. Додавання Контакту

Через кнопку "Додати" бот запускає FSM:

```text
ім'я -> дата народження -> підтвердження -> збереження
```

Через natural language:

```text
додай Олю 15 березня 1990
додай Марію, завтра день народження, їй 21, любить каву і книги
```

AI parser витягує intent, ім'я, дату, вік та інтереси. Перед записом бот показує підтвердження.

### 4. Пошук Дня Народження

Пошук дня народження зроблений як natural language сценарій, без окремої slash-команди.

Приклади:

```text
коли у Олі ДН?
коли день народження у Тараса?
розкажи про Марію
```

Бот шукає тільки контакти поточного користувача.

### 5. Список І Найближчі Дні Народження

Кнопка "Контакти" показує всі збережені контакти з inline кнопками для перегляду, видалення та подарунків.

Кнопка "Найближчі" показує найближчі дні народження на 30 днів.

### 6. Видалення

Видалення доступне з картки контакту або через natural language: `видали Тараса`.

Бот спочатку знаходить контакт і просить підтвердити видалення. SQL запит має `WHERE owner_id=$telegram_id`, тому один користувач не може видалити контакт іншого.

### 7. AI Ідеї Подарунків

Працює з картки контакту або через natural language:

```text
що подарувати Олі?
Петро любить футбол і машини
```

Бот зберігає інтереси контакту, генерує ідеї подарунків через Together AI і може зберегти ідею в `gift_ideas`.

### 8. Скасування

`/cancel` скидає FSM state в `idle` і повертає користувача до меню.

## Демо Сценарій Для Рев'ю

1. `/start` -> shareContact -> меню.
2. Кнопка "Додати" -> `Тарас` -> `15.03.1990` -> підтвердити збереження.
3. Кнопка "Контакти" -> відкрити картку контакту.
4. Написати `коли у Тараса ДН?`.
5. Написати `Тарас любить футбол і техніку`.
6. Написати `що подарувати Тарасу?`.
7. Кнопка "Найближчі".
8. Кнопка видалення з картки контакту або текст `видали Тараса`.

## Структура

```text
telegram-bot/
├── flows.json              Node-RED flow export без secrets
├── docker-compose.yml      Postgres + Node-RED
├── nodered/Dockerfile      Node-RED image з PostgreSQL palette
├── db/
│   ├── schema.sql          базова схема
│   ├── migration_*.sql     міграції для AI/gifts/reminders
│   └── dbdiagram.dbml      ERD для dbdiagram.io
├── docs/
│   └── TEST_CASES.md       ручні сценарії перевірки
├── apply_migrations.ps1
└── redeploy.ps1
```

## База Даних

Після міграцій використовується 10 таблиць:

| Таблиця | Призначення |
| --- | --- |
| `users` | Зареєстровані користувачі Telegram |
| `contacts` | Контакти з днями народження, інтересами і зв'язком з власником |
| `user_sessions` | FSM state і тимчасовий context діалогів |
| `processed_updates` | Idempotency guard для long polling |
| `bot_offset` | Збереження Telegram offset між рестартами |
| `reminders_log` | Історія відправлених нагадувань |
| `gift_ideas` | Збережені AI-ідеї подарунків |
| `ai_prompts` | Системні промпти для AI сценаріїв |
| `audit_log` | Append-only журнал дій |
| `rate_limits` | Зарезервовано під sliding window rate limit |

ER-діаграма: `db/dbdiagram.dbml` -> https://dbdiagram.io/

## Перевірка Перед Здачею

Перевірка виконується вручну в реальному Telegram боті за сценаріями з [docs/TEST_CASES.md](./docs/TEST_CASES.md).

## Команди Бота

| Команда | Опис |
| --- | --- |
| `/start` | Реєстрація через shareContact |
| `/cancel` | Скасувати поточний діалог |
| `/help` | Довідка |
| довільний текст | AI parser природної мови: знайти ДН, додати контакт, оновити інтереси, запропонувати подарунок |

## Security Notes

- SQL запити використовують параметри `$1`, `$2`, без конкатенації user input.
- Telegram HTML повідомлення екранують user input.
- DELETE/UPDATE перевіряють `owner_id`.
- Secrets передаються через environment variables.
- Для production phone numbers варто шифрувати at rest.

## Корисні Команди

```bash
docker-compose logs -f nodered
docker-compose logs -f postgres
docker exec -it birthday-bot-db psql -U postgres -d birthday_bot
```

Повний rebuild зі свіжою БД:

```bash
docker-compose down -v
docker-compose up -d --build
.\apply_migrations.ps1
.\redeploy.ps1
```

**Тестове для Ukrgasbank.** Стек: Node-RED + PostgreSQL + Together AI + Docker.
