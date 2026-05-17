# LAUncher MCP Server

A Model Context Protocol (MCP) server that exposes tools for controlling and analyzing Audio Unit (AU) plugin patches in the LAUncher macOS app.

## Overview

The LAUncher MCP server provides programmatic access to plugin parameters, patch snapshots, and musical analysis through a standardized JSON-RPC 2.0 interface. This allows AI assistants and other tools to interact with your synth plugins.

## How to run (read this first)

There are **two different processes**. Only one of them is something you “run” from Terminal yourself.

### 1. LAUncher HTTP API (port `5555`) — **required for real plugin data**

This is **inside the LAUncher macOS app**, not a separate terminal command.

1. Open **LAUncher** (from Xcode, Finder, or `open` on your built `.app`).
2. **Load a plugin** (Audio Unit). The in-app MCP HTTP server starts with the session and listens on **`http://127.0.0.1:5555`**.
3. Check from Terminal:

```bash
curl -sS http://127.0.0.1:5555/health
```

You should see `OK`. If you get “Connection refused”, the app is not running or the MCP server has not started yet (load a plugin).

### 2. Node MCP (`launcher-server.js`) — **used by Cursor / VS Code**

This script speaks **JSON-RPC over stdin/stdout**. **You do not keep it running in Terminal** for normal use: **Cursor starts** `node …/launcher-server.js` when your MCP config loads and the agent uses that server.

**Optional — one-off smoke test in Terminal** (sends one line, process exits):

```bash
cd /Users/Shared/CohenConcepts/LAUncher/MCP-SERVER-REPO/mcp
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node launcher-server.js
```

To test that LAUncher is reachable from the script (will error if step 1 is not done):

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"toolName":"get_parameters","arguments":{}}}' | node launcher-server.js
```

**Why there is no `npm start`:** this folder is not a Node service that stays open on its own; the MCP **client** (Cursor) is responsible for spawning and feeding stdin.

### 3. Point Cursor at this script

Edit `~/.cursor/mcp.json` and set `args` to the **absolute path** of `launcher-server.js` (see Installation below). Restart Cursor.

---

## Installation

1. **Ensure Node.js is installed** (v14 or higher)
   ```bash
   node --version
   ```

2. **Configure Cursor** by editing `~/.cursor/mcp.json` (use the real path to this file on your machine):
   ```json
   {
     "mcpServers": {
       "launcher": {
         "command": "node",
         "args": ["/Users/Shared/CohenConcepts/LAUncher/MCP-SERVER-REPO/mcp/launcher-server.js"]
       }
     }
   }
   ```

3. **Restart Cursor** to load the MCP server

## Usage

### Getting Parameters

Query current plugin parameters:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "get_parameters",
    "arguments": {
      "filter": {
        "pathPrefix": "Filter",
        "onlyAutomatable": true
      }
    }
  }
}
```

### Setting Parameters

Batch update parameter values:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "set_parameters",
    "arguments": {
      "changes": [
        { "id": "filter_cutoff", "value": 800.0 },
        { "id": "env1_attack", "value": 0.05 }
      ]
    }
  }
}
```

### Getting Patch Snapshots

Capture the current patch state:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "get_patch_snapshot",
    "arguments": {
      "verbosity": "full",
      "includeRawParameters": true
    }
  }
}
```

### Applying Patches

Load a patch by ID or inline object:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "set_patch_snapshot",
    "arguments": {
      "snapshotId": "2025-11-06T23:14:10Z_abc123"
    }
  }
}
```

### Saving to Library

Save current patch with metadata:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "save_patch_to_library",
    "arguments": {
      "label": "Minimal Pluck 01",
      "tags": ["dnb", "minimal", "pluck"],
      "notes": "Good for midrange plucks, slightly hollow."
    }
  }
}
```

### Analyzing Patches

Get musical analysis:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "analyze_patch",
    "arguments": {
      "targetUse": "bass / dnb"
    }
  }
}
```

### Explaining Parameters

Get musical explanations for parameters:

```json
{
  "method": "tools/call",
  "params": {
    "toolName": "explain_parameters",
    "arguments": {
      "parameterIds": ["filter_cutoff", "filter_resonance", "env1_attack"]
    }
  }
}
```

## Available Tools

### 1. `get_parameters`
Returns a machine-friendly list of parameters from the current plugin.

**Arguments:**
- `filter.pathPrefix` (optional): Filter parameters by path prefix
- `filter.onlyAutomatable` (optional): Return only automatable parameters

**Returns:**
```json
{
  "plugin": "Vital",
  "parameters": [
    {
      "id": "filter_cutoff",
      "path": "Filter/Cutoff",
      "address": 1024,
      "displayName": "Cutoff",
      "min": 20.0,
      "max": 20000.0,
      "unit": "Hz",
      "value": 1200.0
    }
  ]
}
```

### 2. `set_parameters`
Batch update parameter values.

**Arguments:**
- `changes`: Array of `{id, value}` objects

**Returns:**
```json
{
  "result": "ok",
  "applied": [
    { "id": "filter_cutoff", "value": 800.0 }
  ]
}
```

### 3. `get_patch_snapshot`
Returns a structured musical snapshot of the current patch.

**Arguments:**
- `verbosity` (optional): "brief" | "full" (default: "brief")
- `includeRawParameters` (optional): Include raw parameter data (default: false)

**Returns:**
```json
{
  "plugin": "Vital",
  "name": "Untitled Patch",
  "categoryGuess": "Bass / Pluck",
  "snapshotId": "2025-11-06T23:14:10Z_abc123",
  "oscillators": [...],
  "filter": {...},
  "ampEnv": {...},
  "modulationOverview": {...}
}
```

### 4. `set_patch_snapshot`
Recall/apply a patch snapshot by ID or inline object.

**Arguments:**
- `snapshotId` (optional): ID of saved patch
- `patch` (optional): Inline patch object

**Returns:**
```json
{
  "result": "ok",
  "appliedSnapshotId": "2025-11-06T23:14:10Z_abc123"
}
```

### 5. `save_patch_to_library`
Save current patch to local library.

**Arguments:**
- `label` (required): Patch name
- `tags` (optional): Array of tag strings
- `notes` (optional): Description/notes

**Returns:**
```json
{
  "result": "ok",
  "libraryPath": "~/Library/Application Support/LAUncher/PatchLibrary.json",
  "entryId": "patch_001234"
}
```

### 6. `analyze_patch`
Live snapshot analysis (no separate snapshot store): refreshes internal routing heuristics used by MCP chat, runs a short heuristic summary, and returns **curated** parameter highlights (not the full AU list — use `get_parameters` for that).

**HTTP:** `POST /api/analyze_patch` with body `{}` (extra fields ignored).

**Arguments (MCP):**
- `snapshotId` (optional): Ignored; always analyzes current plugin state.
- `targetUse` (optional): For your notes only; not sent to LAUncher.

**Returns (MCP / HTTP JSON body):**
```json
{
  "result": "ok",
  "analysis": {
    "plugin": "Serum 2",
    "presetName": "My Preset",
    "summary": "Warm pad with gentle attack...",
    "timbre": { "brightness": 0.5, "warmth": 0.5, "roughness": 0.2, "space": 0.3 },
    "routing": {
      "detectedPluginType": "Serum",
      "oscillatorLevelParameterIds": ["..."],
      "filterCutoffParameterIds": ["..."],
      "modulationMatrixSlotCount": 0
    },
    "highlights": [
      { "id": "0", "displayName": "Main Vol", "value": 0.5, "min": 0, "max": 1 }
    ],
    "highlightCount": 42,
    "totalParameterCount": 2622
  }
}
```

### 7. `explain_parameters`
Explains what selected parameters do in musical terms.

**Arguments:**
- `parameterIds`: Array of parameter IDs

**Returns:**
```json
{
  "explanations": [
    {
      "id": "filter_cutoff",
      "label": "Filter Cutoff",
      "description": "Controls where the lowpass filter starts to roll off..."
    }
  ]
}
```

## Implementation Status

**Current (launcher-server.js):** Live **LAUncher HTTP API** only (`http://127.0.0.1:5555` by default — **not** `localhost`, because LAUncher listens on IPv4 only and `localhost` often resolves to `::1` on macOS). Override with `LAUNCHER_HTTP_URL`. There is **no mock fallback** — if the app is not running or no plugin is loaded, tool calls return a JSON-RPC error.

- **Wired:** `get_parameters`, `set_parameters`, `randomize_parameters`, `get_patch_snapshot` (from live AU params), `set_patch_snapshot` (inline `rawParameters` → `set_parameters`), `explain_parameters` (from live AU metadata).
- **Not on HTTP yet:** `save_patch_to_library` — calls fail with a clear “not implemented” message until Swift adds a route. **`analyze_patch`** is implemented as `POST /api/analyze_patch` (see below).

**Requirements:** LAUncher running with the in-app MCP HTTP server active (starts with `PluginHostSession`) and a **plugin loaded** so `/api/get_parameters` returns data.

## Protocol

The server implements JSON-RPC 2.0 over stdin/stdout:

- **Methods:** `tools/list`, `tools/call`
- **Error Codes:** Standard JSON-RPC 2.0 codes
- **Transport:** stdio (stdin/stdout)

## Development

To test the server directly:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node launcher-server.js
```

## Troubleshooting

1. **Server not loading:** Check `~/.cursor/mcp.json` path is correct
2. **Node not found:** Ensure Node.js is installed and in PATH
3. **Permission denied:** Run `chmod +x launcher-server.js`
4. **Connection errors:** Restart Cursor after configuration changes
5. **"LAUncher HTTP API not reachable":** Open LAUncher, load a plugin, then test **`curl -sS http://127.0.0.1:5555/health`** (prefer **`127.0.0.1`** over `localhost` on macOS). If you set `LAUNCHER_HTTP_URL`, avoid `http://localhost:5555` unless you know IPv6 is listening. **If `curl` still cannot connect:** rebuild LAUncher after pulling changes — **App Sandbox** requires the **`com.apple.security.network.server`** entitlement for the MCP socket to bind; without it, the server never listens (check Xcode console for `❌ MCP HTTP server failed to start`). Confirm nothing else owns the port: `lsof -nP -iTCP:5555 -sTCP:LISTEN`.

6. **`curl localhost:5555` fails but `curl 127.0.0.1:5555` works:** Use IPv4. The Node script defaults to `127.0.0.1` for the same reason.

## See Also

- [MCP-PRD.md](../MCP-PRD.md) - Full specification
- [LAUncher README](../README.md) - Main app documentation

