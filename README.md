# Make It Nice

A macOS **menu bar** app that rewrites your text through [Ollama](https://ollama.com) so it reads more natural and human. The app does not show in the Dock; you control it from the **bolt** icon in the menu bar.

---

## What you need

- **macOS** (project targets a recent macOS SDK).
- A running **Ollama** backend, either:
  - **Local:** [Ollama](https://ollama.com) installed on your machine (default API: `http://127.0.0.1:11434`), or  
  - **Cloud:** [Ollama Cloud](https://ollama.com) with an API key from [ollama.com/settings/keys](https://ollama.com/settings/keys).

---

## Open the app

1. Launch **Make It Nice** (from Xcode or by opening the built `.app`).
2. Look for the **lightning bolt** icon in the **menu bar** (top right).
3. The main window does **not** have to stay open; you can close it and use the menu or global shortcut.

**Menu bar menu**

| Action | What it does |
|--------|----------------|
| **Open** | Brings the Make It Nice window to the front. |
| **Grab selection & rewrite (⌘F)** | Same workflow as the global shortcut below (synthetic copy → open window → rewrite). |
| **Quit** | Exits the app. |

Because the app is a menu bar utility, there is **no Dock icon**. Use **Open** from the menu (or the shortcut) whenever you want the window back.

---

## Connection (local vs cloud)

Open the window → expand **Connection**:

| Setting | Local Ollama | Ollama Cloud |
|--------|----------------|--------------|
| **Base URL** | `http://127.0.0.1:11434` (default) | `https://ollama.com` (use **Use Ollama Cloud** to fill this) |
| **API key** | Leave **empty** | Paste your key from [API keys](https://ollama.com/settings/keys) |
| **Model** | Choose from the list after **Refresh models**, or type a model name | Same |

Press **Refresh models** to load names from your server. If the list is empty, you can still type a model name manually.

---

## Using the main window

1. **Draft** — Put the text you want rewritten here (or get it via **⌘F** / **Grab selection & rewrite**, see below).  
2. **Rewrite** — Sends the draft to Ollama and streams the result into **Results**.  
3. **Results** — Read the rewritten text; you can select and copy, or rely on automatic clipboard copy (below).

**Keyboard shortcuts (when the window is focused)**

- **⌘↩ (Command + Return)** — Run **Rewrite** (same as the button).

**Automatic behavior**

- After you stop typing for about **650 ms**, the app runs **Rewrite** again on the current Draft (debounced).  
- After each **successful** rewrite, the **rewritten text is copied to the clipboard** automatically (if the result is non-empty).

**Other buttons**

- **Copy** — Copies the current result to the clipboard.  
- **Clear** — Clears Draft, Results, and error state.

---

## Global shortcut: ⌘F (grab selection → rewrite)

While **any app** is focused, **⌘F** (Command + F) runs this pipeline:

1. Sends a **synthetic ⌘C** so the **current selection** is copied to the clipboard (same idea as you pressing Copy).  
2. Reads that text from the clipboard.  
3. Opens the Make It Nice window and **pastes it into Draft**.  
4. Runs **Rewrite** and, on success, **copies the result to the clipboard**.

You can trigger the same flow from the menu: **Grab selection & rewrite (⌘F)**.

**Important**

- Select text **before** pressing ⌘F.  
- ⌘F may **conflict** with “Find” in some apps; if nothing happens or the wrong thing happens, that app may be using ⌘F first.  
- Synthetic **⌘C** may require macOS **Accessibility** or **Input Monitoring** permission for Make It Nice (System Settings → Privacy & Security). If selection is never captured, enable those for this app and try again.

---

## Building from source

1. Open `MakeItNice.xcodeproj` in Xcode.  
2. Select the **MakeItNice** scheme and **My Mac**.  
3. **Product → Run** (or **⌘R**).

---

## Privacy note

Connection settings (including the **Ollama Cloud API key**) are stored in the app’s **UserDefaults** (same storage class as other macOS preferences). If you need Keychain storage instead, that would be a separate enhancement.

---

## Troubleshooting

| Issue | Things to try |
|-------|----------------|
| No models in the picker | Confirm Ollama is running (local) or base URL + API key are correct (cloud). Tap **Refresh models**. |
| Rewrite errors | Check the red message under the Draft section; verify model name and network. |
| ⌘F doesn’t grab selection | Grant **Accessibility** / **Input Monitoring**; ensure text is selected; watch for ⌘F conflicts with the frontmost app. |
| High API usage | Debounced rewrites run after you pause typing; clear Draft or adjust usage if needed. |
