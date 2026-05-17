# LAUncher MCP Server

A Model Context Protocol (MCP) server that provides AI-powered tools for controlling and analyzing Audio Unit (AU) plugin patches in the LAUncher macOS application.

## Overview

The LAUncher MCP server enables AI assistants and other tools to interact with your synth plugins through a standardized JSON-RPC 2.0 interface. It exposes tools for parameter control, patch snapshots, musical analysis, and more.

## Features

- **Parameter Control** - Get and set plugin parameters programmatically
- **Patch Snapshots** - Capture and restore patch states
- **Musical Analysis** - Analyze patches for timbre, brightness, and usage notes
- **Parameter Explanation** - Get musical explanations of what parameters do
- **Patch Library** - Save and organize patches with metadata

## Installation

1. **Ensure Node.js is installed** (v14 or higher)
   ```bash
   node --version
   ```

2. **Install dependencies** (if any):
   ```bash
   npm install
   ```

3. **Configure your MCP client** (e.g., Cursor) by editing `~/.cursor/mcp.json`:
   ```json
   {
     "mcpServers": {
       "launcher": {
         "command": "node",
         "args": ["/path/to/launcher-server.js"]
       }
     }
   }
   ```

4. **Restart your MCP client** to load the server

## Usage

See [README.md](mcp/README.md) for detailed usage examples and API documentation.

## Available Tools

1. `get_parameters` - Retrieve plugin parameters
2. `set_parameters` - Batch update parameter values
3. `get_patch_snapshot` - Capture current patch state
4. `set_patch_snapshot` - Restore a patch
5. `save_patch_to_library` - Save patches with metadata
6. `analyze_patch` - Get musical analysis
7. `explain_parameters` - Explain parameters in musical terms
8. `randomize_parameters` - Intelligently randomize parameters

## Protocol

The server implements JSON-RPC 2.0 over stdin/stdout:
- **Methods:** `tools/list`, `tools/call`
- **Transport:** stdio (stdin/stdout)
- **Error Codes:** Standard JSON-RPC 2.0 codes

## VS Code extension

The **LAUncher MCP** setup UI (activity bar panel, MCP install/remove, smoke test) is in [vscode-launcher-mcp/](vscode-launcher-mcp/). From this repo:

```bash
cd vscode-launcher-mcp && npm install && npm run compile
```

Open that folder in VS Code and press **F5** to run the extension in a development host.

## Documentation

- [MCP-PRD.md](MCP-PRD.md) - Complete product requirements and specification
- [MCP-SERVER-STATUS.md](MCP-SERVER-STATUS.md) - Implementation status
- [MCP-EXPLANATION.md](MCP-EXPLANATION.md) - How MCP works with LAUncher
- [mcp/README.md](mcp/README.md) - Server implementation details

## Development

To test the server directly:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node mcp/launcher-server.js
```

## License

See LICENSE file in the main LAUncher repository.

## Credits

**Mitchell Cohen**  
Professor of Sound Design & Production @ Berklee College of Music  
2025 Newton, MA

All Rights Reserved

