# Decisions

| # | Decision | Reason |
|---|----------|--------|
| 1 | The broker binds explicitly to `127.0.0.1:1883`. | Hard safety rule: local only. The phone uses `adb reverse`. |
| 2 | Both the deny list and .gitignore block `.env` files. | Prevents accidental secret reads or commits. |
