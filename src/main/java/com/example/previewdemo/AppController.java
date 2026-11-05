package com.example.previewdemo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;

@RestController
public class AppController {

    private final String message;
    private final String gitSha;
    private final String environment;

    public AppController(
            @Value("${app.message}") String message,
            @Value("${app.git-sha}") String gitSha,
            @Value("${app.environment}") String environment) {
        this.message = message;
        this.gitSha = gitSha;
        this.environment = environment;
    }

    private String resolveHostname() {
        String envHostname = System.getenv("HOSTNAME");
        if (envHostname != null && !envHostname.isBlank()) {
            return envHostname;
        }
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }

    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public String index() {
        String hostname = resolveHostname();
        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Preview Environment Demo</title>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                        background-color: #f4f6f8;
                        margin: 0;
                        padding: 40px 20px;
                        display: flex;
                        justify-content: center;
                    }
                    .container {
                        background: #ffffff;
                        padding: 32px;
                        border-radius: 10px;
                        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
                        max-width: 540px;
                        width: 100%;
                    }
                    h1 {
                        color: #1976d2;
                        font-size: 24px;
                        margin-top: 0;
                        margin-bottom: 20px;
                        border-bottom: 2px solid #e0e0e0;
                        padding-bottom: 12px;
                    }
                    .row {
                        margin: 12px 0;
                        font-size: 16px;
                    }
                    .label {
                        font-weight: 600;
                        color: #424242;
                        display: inline-block;
                        width: 130px;
                    }
                    .value {
                        color: #212121;
                        font-family: monospace;
                        background: #f1f3f4;
                        padding: 2px 6px;
                        border-radius: 4px;
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>Preview Environment Demo</h1>
                    <div class="row"><span class="label">Message:</span><span class="value">{{message}}</span></div>
                    <div class="row"><span class="label">Git SHA:</span><span class="value">{{gitSha}}</span></div>
                    <div class="row"><span class="label">Environment:</span><span class="value">{{environment}}</span></div>
                    <div class="row"><span class="label">Hostname:</span><span class="value">{{hostname}}</span></div>
                </div>
            </body>
            </html>
            """
            .replace("{{message}}", message)
            .replace("{{gitSha}}", gitSha)
            .replace("{{environment}}", environment)
            .replace("{{hostname}}", hostname);
    }

    @GetMapping(value = "/api/info", produces = MediaType.APPLICATION_JSON_VALUE)
    public AppInfo info() {
        return new AppInfo(message, gitSha, environment, resolveHostname());
    }
}
