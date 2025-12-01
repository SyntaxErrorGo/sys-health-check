# sys-health-check

Простой bash-скрипт для регулярной проверки состояния Linux-сервера.

Проверяет:

- нагрузку на систему (load average, с учётом количества CPU);
- использование памяти;
- заполнение дисков;
- статус заданных сервисов (systemd);
- опционально отправляет отчёт в Telegram.

Отчёт сохраняется в текстовый файл в `/var/log/sys-health-check`.

## Структура

- `sys-health-check.sh` — основной скрипт проверки.
- `sys-health-check.conf` — конфигурация.
- `install.sh` — установка скрипта и systemd unit/timer.
- `README.md` — описание проекта.

## Установка

```bash
git clone https://github.com/SyntaxErrorGo/sys-health-check.git
cd sys-health-check

chmod +x install.sh sys-health-check.sh
sudo ./install.sh
