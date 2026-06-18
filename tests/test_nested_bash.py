#!/usr/bin/env python
import subprocess

print("Test 1: Nested bash with single quotes and variables")
cmd1 = "bash -c 'VAR=hello; echo Result: $VAR'"
print(f"Command: {repr(cmd1)}\n")

result = subprocess.run(["bash", "-c", cmd1], capture_output=True, text=True)
print(f"Return code: {result.returncode}")
print(f"Stdout: {repr(result.stdout)}")
print(f"Stderr: {repr(result.stderr)}")
print()

print("Test 2: Nested bash with double quotes and variables")  
cmd2 = 'bash -c "VAR=hello; echo Result: $VAR"'
print(f"Command: {repr(cmd2)}\n")

result = subprocess.run(["bash", "-c", cmd2], capture_output=True, text=True)
print(f"Return code: {result.returncode}")
print(f"Stdout: {repr(result.stdout)}")
print(f"Stderr: {repr(result.stderr)}")
