import logging
import os
import subprocess

from comfy_execution.cache_provider import CacheProvider, register_cache_provider


COMMAND_ENV = "COMFYUI_PRE_PROMPT_COMMAND"
TIMEOUT_ENV = "COMFYUI_PRE_PROMPT_COMMAND_TIMEOUT"
DEFAULT_TIMEOUT = 10.0

NODE_CLASS_MAPPINGS = {}

logger = logging.getLogger(__name__)


def _configured_command() -> str:
    return os.environ.get(COMMAND_ENV, "").strip()


def _configured_timeout() -> float:
    value = os.environ.get(TIMEOUT_ENV, "").strip()
    if not value:
        return DEFAULT_TIMEOUT
    try:
        timeout = float(value)
    except ValueError:
        logger.warning("%s must be a number, using %.1f seconds", TIMEOUT_ENV, DEFAULT_TIMEOUT)
        return DEFAULT_TIMEOUT
    if timeout <= 0:
        logger.warning("%s must be greater than zero, using %.1f seconds", TIMEOUT_ENV, DEFAULT_TIMEOUT)
        return DEFAULT_TIMEOUT
    return timeout


class PrePromptCommandProvider(CacheProvider):
    async def on_lookup(self, context):
        return None

    async def on_store(self, context, value) -> None:
        return None

    def should_cache(self, context, value=None) -> bool:
        return False

    def on_prompt_start(self, prompt_id: str) -> None:
        command = _configured_command()
        if not command:
            return

        timeout = _configured_timeout()
        try:
            result = subprocess.run(
                command,
                shell=True,
                check=False,
                timeout=timeout,
                capture_output=True,
                text=True,
            )
        except subprocess.TimeoutExpired:
            logger.warning("Pre-prompt command timed out after %.1f seconds", timeout)
            return
        except OSError as err:
            logger.warning("Pre-prompt command could not start: %s", err)
            return

        if result.returncode != 0:
            logger.warning("Pre-prompt command exited with code %s", result.returncode)


register_cache_provider(PrePromptCommandProvider())
