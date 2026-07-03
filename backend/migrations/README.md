# Migration Alembic

Demo local có thể chạy với `AUTO_CREATE_TABLES=true`. Production nên đặt `false` và dùng Alembic:

```bash
alembic revision --autogenerate -m "initial schema"
alembic upgrade head
```
