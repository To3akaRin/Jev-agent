"""通过不回显输入把测试 key 写入本机 Keychain。"""

import getpass
import subprocess
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    binary = root / ".runtime/keychain-helper"
    binary.parent.mkdir(exist_ok=True)
    subprocess.run(["swiftc", str(root / "scripts/keychain.swift"), "-o", str(binary)], check=True)
    secret = getpass.getpass("TypeSafe key (stored only in macOS Keychain): ")
    subprocess.run([str(binary), "store"], input=secret.encode(), check=True)
    print("Keychain entry stored. No key was written to project files.")


if __name__ == "__main__":
    main()
