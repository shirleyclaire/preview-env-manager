package com.example.previewdemo;

public record AppInfo(
    String message,
    String gitSha,
    String environment,
    String hostname
) {
}

