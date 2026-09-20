"""Application configuration objects."""
import os
from pathlib import Path

from sqlalchemy.pool import StaticPool

BASE_DIR = Path(__file__).resolve().parent.parent
INSTANCE_DIR = BASE_DIR / "instance"


def _as_bool(value, default=False):
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _as_list(value, default):
    if not value:
        return default
    return [item.strip() for item in str(value).split(",") if item.strip()]


class BaseConfig:
    SECRET_KEY = os.getenv("SECRET_KEY", "air-monitor-dev-secret")

    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL") or (
        "sqlite:///" + (INSTANCE_DIR / "air_monitor.db").as_posix()
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}

    CORS_ORIGINS = _as_list(os.getenv("CORS_ORIGINS"), ["*"])
    TIMEZONE = os.getenv("TIMEZONE", "Asia/Shanghai")
    LIMIT_POLICY = "GB 3095-2012 环境空气质量标准(二级)"

    DEFAULT_PAGE_SIZE = 20
    MAX_PAGE_SIZE = 200
    MAX_BATCH_SIZE = 500
    MAX_EXPORT_ROWS = 20000

    AUTO_INIT_DB = _as_bool(os.getenv("AUTO_INIT_DB"), True)
    AUTO_SEED = _as_bool(os.getenv("AUTO_SEED"), True)


class DevelopmentConfig(BaseConfig):
    DEBUG = True


class ProductionConfig(BaseConfig):
    DEBUG = False
    AUTO_INIT_DB = _as_bool(os.getenv("AUTO_INIT_DB"), False)
    AUTO_SEED = _as_bool(os.getenv("AUTO_SEED"), False)


class TestingConfig(BaseConfig):
    TESTING = True
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.getenv("TEST_DATABASE_URL", "sqlite://")
    SQLALCHEMY_ENGINE_OPTIONS = {
        "poolclass": StaticPool,
        "connect_args": {"check_same_thread": False},
    }
    AUTO_INIT_DB = False
    AUTO_SEED = False


CONFIG_MAP = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}


def get_config(name=None):
    key = (name or os.getenv("FLASK_ENV") or "development").lower()
    return CONFIG_MAP.get(key, DevelopmentConfig)
