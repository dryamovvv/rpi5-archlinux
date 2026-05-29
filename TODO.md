# TODO

## Тестирование на живом RPi5 с rollback

- [ ] Залить образ с homectl_feature на RPi5
- [ ] Проверить firstboot flow: homectl create --identity / homectl firstboot
- [ ] Проверить homectl update --member-of=wheel --stop-delay=30 --password-change-now=yes
- [ ] Проверить loginctl enable-linger (tmux survive SSH disconnect)
- [ ] Проверить snapper -c user_home create-config + снапшоты
- [ ] Проверить authorized_keys копирование из /home/.ssh/
- [ ] Проверить swapfile на btrfs
- [ ] Проверить root в AllowUsers (sshd)
- [ ] Отработать цикл: snapper create → правка → проверка → rollback или ок
- [ ] Настроить MCP (arch-ops-server) для удалённой диагностики
