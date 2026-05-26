# IMAGER_REPO_URL — проверка на реальном RPi5

## Проблема
`IMAGER_REPO_URL` не работает — Network Install показывает старый список ОС (без Arch Linux ARM).

## Что проверить на RPi5
```bash
# 1. Текущий EEPROM-конфиг
rpi-eeprom-config

# 2. Версия bootloader
vcgencmd bootloader_version
```

## Если IMAGER_REPO_URL есть в конфиге, но список старый
→ обновить EEPROM:
```bash
sudo rpi-eeprom-update -a && sudo reboot
```

## Если IMAGER_REPO_URL нет в конфиге
→ применить принудительно:
```bash
echo 'IMAGER_REPO_URL=https://github.com/dryamovvv/archlinux-rpi5-aarch64/releases/latest/download/os_list.json' | sudo tee -a /etc/default/rpi-eeprom-update
sudo rpi-eeprom-config --apply /etc/default/rpi-eeprom-update
sudo reboot
```

После ребута: Space → N → должен появиться "Arch Linux ARM for Raspberry Pi 5"
