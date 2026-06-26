import shlex
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNING_JS = ROOT / "static" / "js" / "cookbookRunning.js"
TOOLS_SRC = ROOT / "src" / "tool_implementations.py"


def _between(source, start, end):
    start_idx = source.index(start)
    end_idx = source.index(end, start_idx)
    return source[start_idx:end_idx]


def test_windows_graceful_kill_reuses_recursive_stop_tree_helper():
    source = RUNNING_JS.read_text(encoding="utf-8")
    wrapper = _between(source, "function _winPowerShellCmd(task, ps)", "function _winSessionStopTreePs(task)")
    helper = _between(source, "function _winSessionStopTreePs(task)", "function _tmuxGracefulKill(task)")
    graceful = _between(source, "function _tmuxGracefulKill(task)", "function _shQuote(value)")
    win_session = _between(source, "function _winSessionCmd(task, tmuxArgs)", "function _winPowerShellCmd(task, ps)")

    assert "function Stop-Tree([int]$Id)" in helper
    assert "('ParentProcessId = ' + $Id)" in helper
    assert "Stop-Tree ([int]$p)" in helper
    assert "${_shQuote(command)}" in wrapper
    assert "_winSessionStopTreePs(task)" in win_session
    assert "_winPowerShellCmd(task, ps)" in win_session
    assert "_winSessionStopTreePs(task)" in graceful
    assert "_winPowerShellCmd(task, ps)" in graceful
    assert "Stop-Process -Id $p -Force" not in graceful
    assert '-Filter "ParentProcessId = $Id"' not in helper
    assert 'powershell -Command \\\\"${ps}\\\\"' not in source


def _posix_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


def test_remote_windows_stop_tree_payload_survives_shell_parsing():
    ps = (
        "function Stop-Tree([int]$Id) { "
        "Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $Id) "
        "-ErrorAction SilentlyContinue | ForEach-Object { Stop-Tree ([int]$_.ProcessId) }; "
        "Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue }; "
        "$p = Get-Content '$env:TEMP\\odysseus-sessions\\serve_abc.pid' "
        "-ErrorAction SilentlyContinue; "
        "if ($p -match '^\\d+$') { Stop-Tree ([int]$p) }"
    )
    remote_command = f'powershell -Command "{ps}"'
    shell_command = f"ssh -p 2222 winbox {_posix_quote(remote_command)}"

    argv = shlex.split(shell_command)

    assert argv == ["ssh", "-p", "2222", "winbox", remote_command]
    assert "$Id" in argv[-1]
    assert "$_.ProcessId" in argv[-1]
    assert "$env:TEMP" in argv[-1]
    assert "$p" in argv[-1]


def test_python_win_session_stop_tree_ps_matches_js_helper():
    from routes.cookbook_helpers import win_session_stop_tree_ps

    js_source = RUNNING_JS.read_text(encoding="utf-8")
    js_helper = _between(js_source, "function _winSessionStopTreePs(task)", "function _tmuxGracefulKill(task)")
    ps_local = win_session_stop_tree_ps("cookbook-deadbeef")
    ps_remote = win_session_stop_tree_ps("cookbook-deadbeef", remote_host="winbox")

    assert "function Stop-Tree([int]$Id)" in ps_local
    assert "('ParentProcessId = ' + $Id)" in ps_local
    assert "odysseus-tmux\\cookbook-deadbeef.pid" in ps_local
    assert "odysseus-sessions\\cookbook-deadbeef.pid" in ps_remote
    assert "function Stop-Tree([int]$Id)" in js_helper
    assert "Stop-Tree ([int]$p)" in js_helper


def test_agent_kill_session_local_windows_uses_process_tree_not_tmux():
    source = TOOLS_SRC.read_text(encoding="utf-8")
    kill_block = _between(source, "async def _cookbook_kill_session", "async def do_stop_served_model")

    assert "local_windows = (not remote) and IS_WINDOWS" in kill_block
    assert "win_session_stop_tree_ps" in kill_block
    local_branch = kill_block.split("elif local_windows:")[1].split("else:")[0]
    assert "kill_process_tree" in local_branch
    assert "resolve_cookbook_pid_path" in local_branch
    assert "tmux kill-session" not in local_branch


def test_agent_tail_serve_output_uses_resolve_cookbook_log_path():
    source = TOOLS_SRC.read_text(encoding="utf-8")
    tail_block = _between(source, "async def do_tail_serve_output", "async def do_list_downloads")

    assert "resolve_cookbook_log_path" in tail_block
    assert "if not remote and IS_WINDOWS:" in tail_block
    assert 'f"/tmp/odysseus-tmux/{session_id}.log"' not in tail_block
