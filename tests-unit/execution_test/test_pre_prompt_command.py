"""Tests for the pre-prompt command custom node."""

import importlib.util
import os
import sys
import types
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
sys.path.insert(0, str(ROOT))


def load_pre_prompt_module():
    comfy_execution = types.ModuleType("comfy_execution")
    cache_provider = types.ModuleType("comfy_execution.cache_provider")

    class CacheProvider:
        pass

    cache_provider.CacheProvider = CacheProvider
    cache_provider.register_cache_provider = lambda provider: None
    sys.modules["comfy_execution"] = comfy_execution
    sys.modules["comfy_execution.cache_provider"] = cache_provider

    path = ROOT / "custom_nodes" / "pre_prompt_command" / "__init__.py"
    spec = importlib.util.spec_from_file_location("pre_prompt_command_prestartup", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestPrePromptCommand(TestCase):
    def test_provider_skips_external_cache_participation(self):
        module = load_pre_prompt_module()
        provider = module.PrePromptCommandProvider()

        self.assertFalse(provider.should_cache(None))

    def test_provider_skips_when_command_is_not_configured(self):
        module = load_pre_prompt_module()
        provider = module.PrePromptCommandProvider()

        def fail_run(*args, **kwargs):
            raise AssertionError("subprocess.run should not be called")

        env = {k: v for k, v in os.environ.items() if k != "COMFYUI_PRE_PROMPT_COMMAND"}
        with patch.dict(os.environ, env, clear=True), patch.object(module.subprocess, "run", fail_run):
            provider.on_prompt_start("prompt-1")

    def test_provider_runs_configured_command_with_timeout(self):
        module = load_pre_prompt_module()
        provider = module.PrePromptCommandProvider()
        calls = []

        class Result:
            returncode = 0

        def fake_run(*args, **kwargs):
            calls.append((args, kwargs))
            return Result()

        env = {
            **os.environ,
            "COMFYUI_PRE_PROMPT_COMMAND": "curl http://host.docker.internal:11434/api/ps",
            "COMFYUI_PRE_PROMPT_COMMAND_TIMEOUT": "2.5",
        }
        with patch.dict(os.environ, env, clear=True), patch.object(module.subprocess, "run", fake_run):
            provider.on_prompt_start("prompt-1")

        self.assertEqual(
            calls,
            [
                (
                    ("curl http://host.docker.internal:11434/api/ps",),
                    {
                        "shell": True,
                        "check": False,
                        "timeout": 2.5,
                        "capture_output": True,
                        "text": True,
                    },
                )
            ],
        )


if __name__ == "__main__":
    main()
