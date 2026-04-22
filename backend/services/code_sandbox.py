"""
backend/services/code_sandbox.py
RiseUp Code Sandbox — v1.0

Runs user/APEX code in isolated Docker containers.
Supports: Python, Node.js, HTML/CSS/JS, Bash.
Auto-cleans containers after execution.

Install: Docker must be available on the backend server.
"""
import asyncio
import logging
import os
import tempfile
import uuid
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

SUPPORTED_LANGUAGES = {
    "python":     {"image": "python:3.11-slim", "cmd": "python",    "ext": "py"},
    "javascript": {"image": "node:20-slim",      "cmd": "node",      "ext": "js"},
    "nodejs":     {"image": "node:20-slim",      "cmd": "node",      "ext": "js"},
    "bash":       {"image": "ubuntu:22.04",      "cmd": "bash",      "ext": "sh"},
    "html":       {"image": "python:3.11-slim",  "cmd": "_serve",    "ext": "html"},
}

TIMEOUT_SECONDS  = 30
MAX_OUTPUT_CHARS = 8000


class CodeSandbox:
    """Runs code in isolated Docker containers, streams output."""

    _docker_available: Optional[bool] = None

    @classmethod
    async def _check_docker(cls) -> bool:
        if cls._docker_available is not None:
            return cls._docker_available
        try:
            proc = await asyncio.create_subprocess_exec(
                "docker", "info",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            cls._docker_available = proc.returncode == 0
        except FileNotFoundError:
            cls._docker_available = False
        return cls._docker_available

    async def execute(
        self,
        code: str,
        language: str = "python",
        stdin_data: str = "",
        packages: Optional[list] = None,
    ) -> Dict[str, Any]:
        """
        Execute code in a Docker sandbox.

        Returns:
            {
                "success": bool,
                "output": str,
                "error": str | None,
                "exit_code": int,
                "language": str,
                "truncated": bool,
            }
        """
        language = language.lower()
        if language not in SUPPORTED_LANGUAGES:
            return {
                "success": False,
                "output": "",
                "error": f"Language '{language}' not supported. Use: {', '.join(SUPPORTED_LANGUAGES.keys())}",
                "exit_code": 1,
                "language": language,
                "truncated": False,
            }

        if not await self._check_docker():
            # Fallback: safe eval for simple Python (no imports, no disk access)
            if language == "python":
                return await self._python_fallback(code)
            return {
                "success": False,
                "output": "",
                "error": "Code execution sandbox not available on this server. Contact support.",
                "exit_code": 1,
                "language": language,
                "truncated": False,
            }

        cfg = SUPPORTED_LANGUAGES[language]

        with tempfile.TemporaryDirectory() as tmpdir:
            # Write code file
            code_file = os.path.join(tmpdir, f"main.{cfg['ext']}")
            with open(code_file, "w") as f:
                f.write(code)

            container_name = f"riseup-sandbox-{uuid.uuid4().hex[:8]}"

            if language == "html":
                # Just return the HTML for the frontend to render in WebView
                return {
                    "success": True,
                    "output": code,
                    "error": None,
                    "exit_code": 0,
                    "language": "html",
                    "truncated": False,
                    "render_type": "html",
                }

            # Build docker command
            docker_cmd = [
                "docker", "run", "--rm",
                "--name", container_name,
                "--network", "none",          # No internet inside sandbox
                "--memory", "256m",
                "--cpus", "0.5",
                "--read-only",
                "--tmpfs", "/tmp:size=64m",
                "-v", f"{tmpdir}:/workspace:ro",
                "-w", "/workspace",
                cfg["image"],
                cfg["cmd"], f"main.{cfg['ext']}",
            ]

            # Install packages if requested (Python only for now)
            if packages and language == "python":
                install_cmd = f"pip install -q {' '.join(packages)} && python main.py"
                docker_cmd = [
                    "docker", "run", "--rm",
                    "--name", container_name,
                    "--network", "bridge",     # Need network only for pip install
                    "--memory", "512m",
                    "--cpus", "0.5",
                    "-v", f"{tmpdir}:/workspace",
                    "-w", "/workspace",
                    cfg["image"],
                    "sh", "-c", install_cmd,
                ]

            try:
                proc = await asyncio.create_subprocess_exec(
                    *docker_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    stdin=asyncio.subprocess.PIPE if stdin_data else None,
                )

                stdin_bytes = stdin_data.encode() if stdin_data else None

                try:
                    stdout, stderr = await asyncio.wait_for(
                        proc.communicate(input=stdin_bytes),
                        timeout=TIMEOUT_SECONDS,
                    )
                except asyncio.TimeoutError:
                    try:
                        await asyncio.create_subprocess_exec("docker", "kill", container_name)
                    except Exception:
                        pass
                    return {
                        "success": False,
                        "output": "",
                        "error": f"Execution timed out after {TIMEOUT_SECONDS}s.",
                        "exit_code": 124,
                        "language": language,
                        "truncated": False,
                    }

                out    = stdout.decode("utf-8", errors="replace")
                err    = stderr.decode("utf-8", errors="replace")
                success = proc.returncode == 0

                combined = out + ("\n" + err if err else "")
                truncated = len(combined) > MAX_OUTPUT_CHARS
                if truncated:
                    combined = combined[:MAX_OUTPUT_CHARS] + "\n... [output truncated]"

                return {
                    "success":   success,
                    "output":    combined,
                    "error":     err if not success else None,
                    "exit_code": proc.returncode,
                    "language":  language,
                    "truncated": truncated,
                }

            except Exception as e:
                logger.error("CodeSandbox.execute: %s", e)
                return {
                    "success": False, "output": "", "error": str(e),
                    "exit_code": 1, "language": language, "truncated": False,
                }

    @staticmethod
    async def _python_fallback(code: str) -> Dict[str, Any]:
        """Minimal safe Python execution without Docker (for simple scripts)."""
        import sys
        from io import StringIO
        import contextlib

        # Block dangerous imports
        dangerous = ["import os", "import sys", "import subprocess", "open(", "__import__",
                     "exec(", "eval(", "import socket", "import shutil"]
        for d in dangerous:
            if d in code:
                return {
                    "success": False, "output": "",
                    "error": "This code requires the full sandbox (Docker) which is not available.",
                    "exit_code": 1, "language": "python", "truncated": False,
                }

        out_buf = StringIO()
        try:
            with contextlib.redirect_stdout(out_buf):
                exec(compile(code, "<sandbox>", "exec"), {"__builtins__": {"print": print, "range": range, "len": len, "str": str, "int": int, "float": float, "list": list, "dict": dict, "sum": sum, "max": max, "min": min, "sorted": sorted, "enumerate": enumerate, "zip": zip}})
            output = out_buf.getvalue()
            return {"success": True, "output": output, "error": None, "exit_code": 0, "language": "python", "truncated": False}
        except Exception as e:
            return {"success": False, "output": out_buf.getvalue(), "error": str(e), "exit_code": 1, "language": "python", "truncated": False}


code_sandbox = CodeSandbox()
