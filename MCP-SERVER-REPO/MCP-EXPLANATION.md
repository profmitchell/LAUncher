# How MCP Works - Complete Guide

## Understanding the Two Interaction Methods

### Method 1: **Your App UI** (Direct Control ✅)
When you click "MCP Tools" in your app:
- The UI calls `session.randomizeParameters()` directly
- This sets parameters on the actual plugin using `param.setValue()`
- **The synth parameters ARE changing** (you can see it in logs)
- **The audio IS changing** (you should hear it)
- **BUT**: Some plugin UIs don't update their knobs automatically

**Why knobs don't move:**
- Many AU plugins only update their UI when:
  - User interacts directly with the UI
  - The plugin receives a specific notification format
  - The plugin's view controller explicitly refreshes
  
- **The parameters ARE changing** - check by:
  - Listening to the audio (sound should change)
  - Looking at the console logs (shows parameter values)
  - Using "Get Parameters" in MCP Tools to see current values

### Method 2: **Via Cursor AI (Me!)** 🤖
When you chat with me:
- I can call the MCP server tools
- Currently uses **mock data** (not connected to your real app)
- Once connected to your app's HTTP API, I can:
  - See your actual plugin parameters
  - Control your synth in real-time
  - Randomize parameters while you watch/listen

## Current Status

✅ **Your App UI:**
- Randomize function works - parameters ARE changing
- Audio changes are applied immediately
- Plugin UI knobs may not visually update (this is a plugin limitation)

⚠️ **MCP Server:**
- All tools implemented
- Uses mock data (not connected to real app)
- Ready to connect when HTTP API is added

## Can I Move the Knobs?

**Short answer:** I can try, but it depends on the plugin.

**What's happening:**
1. Parameters ARE being set (`param.setValue()`)
2. Audio IS changing (you should hear it)
3. Plugin UI may not update visually

**Why plugin UIs don't always update:**
- Some plugins only update UI from user input
- Some need specific notification formats
- Some use custom view hierarchies that don't respond to parameter changes

**Solutions to try:**
1. ✅ Already doing: Using `setValue:originator:` instead of direct assignment
2. ✅ Already doing: Forcing view updates
3. ✅ Already doing: Updating subviews recursively
4. **New:** Try using parameter address directly (see below)

## Testing Steps

1. **Load a plugin** (e.g., Vital, ANA 2)
2. **Start audio engine**
3. **Play a note** (MIDI input or musical typing)
4. **Open MCP Tools** → Randomize Parameters
5. **Click Randomize**
6. **Listen** - you should hear the sound change
7. **Check console** - you'll see parameter values changing
8. **Check plugin UI** - knobs may or may not move (plugin-dependent)

## Future: Making Knobs Move

To make knobs move reliably, we need:
1. Plugin-specific parameter notification (some plugins use custom systems)
2. View controller refresh hooks (if plugin supports it)
3. HTTP API integration so MCP can control real plugin

**The good news:** Even if knobs don't move, **the parameters ARE changing and the audio IS changing!**
