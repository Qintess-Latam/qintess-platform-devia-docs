# architect — mcp-config.json

```json
{
  "mcpServers": {
    "github": {
      "command": "bash",
      "args": [
        "-lc",
        "export GITHUB_PERSONAL_ACCESS_TOKEN=\"$GITHUB_TOKEN\"; exec npx -y @modelcontextprotocol/server-github"
      ]
    },
    "atlassian": {
      "type": "http",
      "url": "http://127.0.0.1:8766/mcp"
    }
  }
}
```
