---
name: unity-compile-fixer
description: >-
  Diagnose and fix Unity C# compilation errors. Use when compilation fails, CS error codes
  appear, Unity console logs show errors, or the user asks to fix compile errors in a Unity
  project.
---

# Unity Compile Error Fixer

Source: nyosegawa/unity-agent (template/.claude/skills/unity-compile-fixer).

## Workflow
1. Get errors from the Unity console (`Unity_GetConsoleLogs` with error log types, or the MCP console tool).
2. Analyze the error code and message.
3. Read the relevant file to confirm the cause.
4. Fix with an edit.
5. Re-check the console for remaining errors.
6. If errors remain, return to step 2.

## Common Unity-Specific Errors

| Error Code | Cause | Fix |
|:--|:--|:--|
| CS0246 | Type not found | Add `using` directive or assembly reference |
| CS1061 | Member not found | Check Unity version API changes |
| CS0103 | Name not in scope | Check namespace, add `using` |
| CS0234 | Namespace member missing | Update package or add assembly reference |
| CS0029 | Cannot convert type | Check Unity type casting (Vector3 vs Vector2) |
| CS0117 | No member in type | API may have changed in Unity version |
| CS0619 | Member is obsolete | Use recommended replacement |
| CS0428 | Cannot convert method group | Add () for method call |
| CS0118 | Namespace used as type | Use alias: `using UIImage = UnityEngine.UI.Image;` |

## Examples

### Example 1: Missing namespace
```
error CS0246: The type or namespace name 'InputAction' could not be found
```
Fix: Add `using UnityEngine.InputSystem;`

### Example 2: Old Input API
```
error CS0117: 'Input' does not contain a definition for 'GetKey'
```
Fix: Replace `Input.GetKey(KeyCode.Space)` with `Keyboard.current.spaceKey.isPressed`

### Example 3: Deprecated API
```
warning CS0618: 'FindObjectOfType<T>()' is obsolete
```
Fix: Replace with `FindFirstObjectByType<T>()`

### Example 4: Image namespace conflict (CS0118)
```
error CS0118: 'Image' is a namespace but is used like a type
```
Fix: Add alias `using UIImage = UnityEngine.UI.Image;` and use `UIImage` instead of `Image`

## Troubleshooting
- **Error persists**: an .asmdef reference may be missing. Check the Assembly Definition.
- **Package-related errors**: check package versions in `Packages/manifest.json`.
- **Unity version differences**: check the version in `ProjectSettings/ProjectVersion.txt`.
