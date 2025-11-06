# LAUncher MCP Server

A Model Context Protocol (MCP) server that exposes tools for controlling and analyzing Audio Unit (AU) plugin patches in the LAUncher macOS app.

## Overview

The LAUncher MCP server provides programmatic access to plugin parameters, patch snapshots, and musical analysis through a standardized JSON-RPC 2.0 interface. This allows AI assistants and other tools to interact with your synth plugins.

## Installation

1. **Ensure Node.js is installed** (v14 or higher)
   ```bash
   node --version
   ```

2. **Configure Cursor** by editing `~/.cursor/mcp.json`:
   ```json
   {
     "mcpServers": {
       "launcher": {
         "command": "node",
         "args": ["/Users/Shared/CohenConcepts/LAUncher/LAUncher/dev/mcp/launcher-server.js"]
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
Provides musical analysis: overview, timbre, and usage notes.

**Arguments:**
- `snapshotId` (optional): Use specific snapshot (null = current)
- `targetUse` (optional): Hint for analysis (e.g., "bass / dnb")

**Returns:**
```json
{
  "summary": "Short, snappy bass pluck...",
  "timbre": {
    "brightness": 0.7,
    "warmth": 0.5,
    "roughness": 0.2,
    "space": 0.3
  },
  "coreIngredients": [...],
  "usageNotes": [...]
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

**Current:** Mock implementation with in-memory data
- All tools work with mock plugin data
- Patch library stored in memory

**Future:** HTTP API integration
- Replace mock data with calls to LAUncher HTTP API
- Persistent patch library storage
- Real-time parameter updates

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

## See Also

- [MCP-PRD.md](../MCP-PRD.md) - Full specification
- [LAUncher README](../README.md) - Main app documentation

