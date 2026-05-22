# opencode-mcp-installers

A collection of installer tools that add MCP servers to your OpenCode.

## Downloads

The latest release is always available at the links below. Double-click the downloaded file to install.

| Server | macOS | Windows |
|---|---|---|
| Blender | [install-blender-mcp-macos.zip](https://github.com/abbrechen/opencode-mcp-installers/releases/latest/download/install-blender-mcp-macos.zip) | [install-blender-mcp-windows.zip](https://github.com/abbrechen/opencode-mcp-installers/releases/latest/download/install-blender-mcp-windows.zip) |
| Figma Remote | [install-figma-remote-mcp-macos.zip](https://github.com/abbrechen/opencode-mcp-installers/releases/latest/download/install-figma-remote-mcp-macos.zip) | [install-figma-remote-mcp-windows.zip](https://github.com/abbrechen/opencode-mcp-installers/releases/latest/download/install-figma-remote-mcp-windows.zip) |

## Development

### Adding a new installer

1. Create a directory under `installers/` named after your tool
2. Write `install-<tool>-macos.sh` (macOS) and/or `install-<tool>-windows.ps1` (Windows)
3. Source/dot-source the shared library (`opencode-lib.sh` / `opencode-lib.ps1`)
4. Add a `# Version: X.X` header

### Testing

```bash
# macOS installers
sh dev/test-ci.sh

# Windows installers
pwsh dev/test-ci.ps1
```
