"""Application factory."""
import os

from flask import Flask

from .api import register_blueprints
from .commands import register_commands
from .config import get_config
from .errors import register_error_handlers
from .extensions import cors, db

__all__ = ["create_app"]


def create_app(config_name=None):
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_object(get_config(config_name))
    app.json.ensure_ascii = False
    app.json.sort_keys = False

    os.makedirs(app.instance_path, exist_ok=True)

    db.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}})

    register_error_handlers(app)
    register_blueprints(app)
    register_commands(app)

    from .seed import ensure_bootstrap

    ensure_bootstrap(app)
    return app
