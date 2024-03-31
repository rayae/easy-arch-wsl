#!/bin/bash

# 自动更新 Windows 的 DNS 解析配置到 WSL 中
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command '(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses | ForEach-Object { "nameserver $_" }' | tr -d '\r'| tee /etc/resolv.conf > /dev/null

