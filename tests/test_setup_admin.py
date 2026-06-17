import json
import os
from pathlib import Path
from unittest import mock

import setup


def test_create_default_admin_uses_launcher_defaults(tmp_path):
    auth_path = tmp_path / "auth.json"
    with mock.patch.object(setup, "AUTH_FILE", str(auth_path)):
        with mock.patch.object(setup.sys, "stdin") as stdin_mock:
            stdin_mock.isatty.return_value = True
            with mock.patch.dict(os.environ, {"ODYSSEUS_LAUNCHER_MODE": "1"}, clear=False):
                result = setup.create_default_admin()

    assert result == "created"
    assert auth_path.exists()
    data = json.loads(auth_path.read_text(encoding="utf-8"))
    assert data["users"]
    assert next(iter(data["users"].values()))["is_admin"] is True
