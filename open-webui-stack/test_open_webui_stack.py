"""The bundled frontend and SQLite tag-key migration work with warnings treated as errors."""

from __future__ import annotations

import importlib
import unittest
import warnings
from pathlib import Path
from unittest.mock import patch


class RuntimeTests(unittest.TestCase):
    def test_frontend_is_bundled(self) -> None:
        package = importlib.import_module("open_webui")
        self.assertTrue((Path(str(package.__file__)).parent / "frontend" / "index.html").is_file())

    def test_tag_primary_key_round_trip_preserves_rows_without_warnings(self) -> None:
        sqlalchemy = importlib.import_module("sqlalchemy")
        migration_context = importlib.import_module("alembic.runtime.migration").MigrationContext
        operations = importlib.import_module("alembic.operations").Operations
        migration = importlib.import_module("open_webui.migrations.versions.3ab32c4b8f59_update_tags")
        engine = sqlalchemy.create_engine("sqlite://")
        with engine.begin() as connection:
            connection.exec_driver_sql(
                "CREATE TABLE tag (id VARCHAR PRIMARY KEY, user_id VARCHAR NOT NULL, name VARCHAR)"
            )
            connection.exec_driver_sql("INSERT INTO tag VALUES ('fixture', 'owner', 'retained')")
            with (
                patch.object(migration, "op", operations(migration_context.configure(connection))),
                warnings.catch_warnings(),
            ):
                warnings.simplefilter("error")
                migration.upgrade()
                self.assertEqual(
                    sqlalchemy.inspect(connection).get_pk_constraint("tag")["constrained_columns"], ["id", "user_id"]
                )
                migration.downgrade()
                self.assertEqual(sqlalchemy.inspect(connection).get_pk_constraint("tag")["constrained_columns"], ["id"])
            self.assertEqual(connection.exec_driver_sql("SELECT name FROM tag").scalar_one(), "retained")
        engine.dispose()


if __name__ == "__main__":
    unittest.main()
