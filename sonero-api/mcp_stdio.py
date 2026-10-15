"""
Sonero MCP server over stdio, for MCP clients that launch the server process
themselves (e.g. Claude Desktop). It reads the same local database as the API,
so the backend doesn't need to be running.

    venv/bin/python mcp_stdio.py

stdout carries the MCP protocol: nothing else may print to it.
"""

import contextlib
import os
import sys

# Run from any working directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.getcwd())

with contextlib.redirect_stdout(sys.stderr):
    from init_db import init_db
    from services.mcp_server import mcp

    init_db()

if __name__ == "__main__":
    mcp.run("stdio")
