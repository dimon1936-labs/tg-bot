# Test Cases

Ручні тести бота. Виконати перед демо.

Всюди далі `psql` = `docker exec -i birthday-bot-db psql -U postgres -d birthday_bot`.

---

## 1. Smoke

### S1. Запуск з нуля
```powershell
docker-compose down -v
docker-compose up -d --build
.\apply_migrations.ps1
.\redeploy.ps1
```
Очікується: контейнери `birthday-bot-db` і `birthday-bot-nodered` healthy. У debug Node-RED — `[INIT] MENU_KB, BACK_KB, HELP_TEXT registered`.

### S2. /start (новий юзер)
В Telegram: `/start`.
Очікується: welcome + reply-keyboard «Поділитись контактом».

### S3. ShareContact
Натиснути «Поділитись контактом».
Очікується: підтвердження реєстрації + меню. `psql -c "SELECT phone_number FROM users;"` — є.

---

## 2. Add Contact

### A1. Natural language
Input: `додай Олю 15 березня 1990`
Очікується: AI intent `add_contact` (conf≥0.7) → confirm UI → натиснути «Зберегти» → запис у `contacts` + `audit_log.action='contact_added'`.

### A2. Age-based date (currentYear=2026)
Input: `є Зоряна 25 квітня їй буде 47 років`
Очікується: date=1979-04-25 (2026−47), confirm показує «47 років».

### A3. «завтра» + interests
Input: `додай Марію, 21 рік, завтра днюха, любить гуляти`
Очікується на 27.04.2026: name=Марія, date=2004-04-28, confirm показує «буде 22 років», interests=«гуляти».

### A4. Refinement у confirm
Після confirm UI: `ні, вона 27 числа`.
Очікується: edit того ж повідомлення з оновленою датою + позначка «Оновлено HH:MM».

### A5. Дубль
Додати ту саму Олю двічі.
Очікується: ON CONFLICT → апдейт існуючого, не дубль у `contacts`.

---

## 3. Gift AI

### G1. Ідеї за інтересами
Контакт з `interests='машини'`. Натиснути «Ідеї подарунків».
Очікується: 4 ідеї різних тірів (≤1k / 1-3k / 3-8k / 8k+). Українською. Конкретні товари, не категорії.

### G2. Gender heuristic
Чоловіче ім'я `Тарас` vs жіноче `Оля`.
Очікується: різні ідеї за gender (без женсько-косметичного для Тараса).

### G3. NL gift request
Input: `що подарувати Петру?`
Очікується: pg_trgm знаходить Петра, AI генерує ідеї.

### G4. Lifecycle save → bought
«Зберегти ідею» → status `saved`. Reminder day-of: «Купив?» → status `bought`.

### G5. Fuzzy lookup
Input: `що купити петрі` (genitive).
Очікується: знайдено Петро через `similarity()`.

---

## 4. Intents (regex pre-filter + AI)

| ID | Input | Intent |
|---|---|---|
| I1 | коли у Олі ДН | query_birthday |
| I2 | петро любить машини | update_interests |
| I3 | видали Петра | delete_contact (regex) |
| I4 | розкажи про Олю | show_contact_detail (regex) |
| I5 | покажи всіх | list_all (regex) |
| I6 | хто скоро | upcoming (regex) |
| I7 | привіт | greet (regex) |
| I8 | поможи | help (regex) |
| I9 | погода сьогодні | unclear (conf<0.5) → fallback |
| I10 | коли у кого ДН | clarify_name FSM → ask name |

---

## 5. Reminders

### R1. Multi-stage 7/3/1/0

Підготовка:
```powershell
psql -c "UPDATE users SET reminder_days_before = ARRAY[7,3,1,0];"
psql -c "TRUNCATE reminders_log;"
psql -c "INSERT INTO contacts (owner_id, name, birthday) SELECT telegram_id, 'TestD0', (CURRENT_DATE - INTERVAL '30 years')::date     FROM users LIMIT 1;"
psql -c "INSERT INTO contacts (owner_id, name, birthday) SELECT telegram_id, 'TestD1', (CURRENT_DATE + 1 - INTERVAL '30 years')::date FROM users LIMIT 1;"
psql -c "INSERT INTO contacts (owner_id, name, birthday) SELECT telegram_id, 'TestD3', (CURRENT_DATE + 3 - INTERVAL '30 years')::date FROM users LIMIT 1;"
psql -c "INSERT INTO contacts (owner_id, name, birthday) SELECT telegram_id, 'TestD7', (CURRENT_DATE + 7 - INTERVAL '30 years')::date FROM users LIMIT 1;"
psql -c "SELECT contact_name, days_before FROM v_due_reminders ORDER BY days_before;"
```
Має повернути 4 рядки (D0/D1/D3/D7).

Тригер: Node-RED → tab 9 `Scheduled Reminders` → клік inject «every 15 min».

Очікується (Telegram): 4 повідомлення.
- TestD0: «Сьогодні ДН у TestD0»
- TestD1: «Завтра ДН у TestD1»
- TestD3: «Через 3 дн. ДН у TestD3»
- TestD7: «Через 7 дн. ДН у TestD7»

### R2. Idempotency
Повторний клік inject. Очікується: нічого не дублюється.
```powershell
psql -c "SELECT COUNT(*) FROM v_due_reminders;"
```
Має бути `0`.

### R3. Unique per stage
```powershell
psql -c "SELECT contact_id, days_before FROM reminders_log WHERE contact_id=(SELECT id FROM contacts WHERE name='TestD0');"
```
Має бути 1 рядок (`days_before=0`). Якщо лог тригернеться знову у наступному `remind_year` — додасться новий, бо UNIQUE по `(contact_id, remind_year, days_before)`.

### R4. Custom lead-time
```powershell
psql -c "UPDATE users SET reminder_days_before = ARRAY[14,0] WHERE telegram_id=<id>;"
```
Очікується: тільки D14 і D0 у view, D1/D3/D7 ігноруються.

### R5. Cleanup
```powershell
psql -c "DELETE FROM contacts WHERE name LIKE 'TestD%';"
psql -c "UPDATE users SET reminder_days_before = ARRAY[7,3,1,0];"
```

---

## 6. Security

### Sec1. SQL injection
Input: `додай Robert'); DROP TABLE contacts;-- 15.03.1990`
Очікується: literal name збережено, таблиця ціла.

### Sec2. HTML escape
Input: `додай <b>Hacker</b> 01.01.1990`
Очікується: name збережений literal, у виводі — escape `&lt;b&gt;`.

### Sec3. Authorization
Один юзер не може видалити контакт іншого (DELETE WHERE owner_id=$telegram_id).

### Sec4. ShareContact own only
Telegram API guarantees `phone_number` із shareContact = власний номер юзера.

---

## 7. Errors

### E1. 429 rate limit
Симулювати масовий send → ретрай по `retry_after`.

### E2. 403 (заблоковано)
Telegram повертає 403 → бот ставить `users.is_active=false`, не шле далі.

### E3. AI down
Невалідний `TOGETHER_API_KEY` → fallback повідомлення «AI тимчасово недоступний».

### E4. DB down
Зупинити `birthday-bot-db` → Node-RED ловить помилку через global catch і шле alert адміну (`ADMIN_TELEGRAM_ID`). Після повернення БД polling продовжує роботу.

---

## 8. Onboarding UX

### U1. Returning /start
Існуючий юзер пише `/start` → personalised welcome з кнопками меню (без shareContact).

### U2. /help
Очікується: HELP_TEXT з прикладами команд.

### U3. /cancel
У будь-якому FSM-стані → reset до idle, повернення в меню.
