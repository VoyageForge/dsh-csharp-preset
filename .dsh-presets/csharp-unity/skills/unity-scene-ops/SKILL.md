---
name: unity-scene-ops
description: >-
  Manage Unity scenes, GameObjects, and components through Unity MCP. Use when building
  scenes, placing objects, setting up hierarchy, creating materials, or when the user asks to
  construct or modify a scene in Unity.
---

# Unity Scene Operations (via Unity MCP)

Source: nyosegawa/unity-agent (template/.claude/skills/unity-scene-ops).

## Prerequisites
Unity Editor must be open with the `com.unity.ai.assistant` package installed and the MCP connection active.

## Quick Reference

### Single Object Operations
- `Unity_ManageScene` — create, load, save, and query scene info
- `Unity_ManageGameObject` — create, move, rotate, scale GameObjects and manage components
- `Unity_ManageAsset` — asset management (including materials)
- `Unity_CreateScript` — create a C# script (prefer this over Write for Unity scripts)

### Batch Scene Building (Unity_RunCommand)
When placing many GameObjects at once:
```csharp
internal class CommandScript : IRunCommand
{
    public void Execute(ExecutionResult result)
    {
        // Create GameObject
        var obj = new GameObject("MyObject");
        var sr = obj.AddComponent<SpriteRenderer>();
        sr.color = Color.red;
        result.RegisterObjectCreation(obj);

        // Add component
        var rb = obj.AddComponent<Rigidbody2D>();
        rb.gravityScale = 0;

        // PhysicsMaterial2D (asset save)
        var mat = new PhysicsMaterial2D("BounceMat");
        mat.bounciness = 1f; mat.friction = 0f;
        AssetDatabase.CreateAsset(mat, "Assets/Materials/BounceMat.asset");

        // Save scene
        EditorSceneManager.MarkSceneDirty(EditorSceneManager.GetActiveScene());
        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene());
        result.Log("Done");
    }
}
```
Required usings: `UnityEngine`, `UnityEditor`, `UnityEditor.SceneManagement`.

### Screenshots (for verification)
- `Unity_Camera_Capture` — capture from the game camera
- `Unity_EditorWindow_CaptureScreenshot` — capture an editor window
- `Unity_SceneView_CaptureMultiAngleSceneView` — multi-angle scene view capture

### Debug
- `Unity_GetConsoleLogs` — check errors
- `Unity_ReadConsole` — read console output

## Examples

### Example 1: Create a new scene and place objects
1. `Unity_ManageScene(Action: "Create", Name: "MyScene", Path: "Assets/Scenes")`
2. `Unity_ManageScene(Action: "Load", Name: "MyScene", Path: "Assets/Scenes")`
3. Batch-place objects with `Unity_RunCommand`
4. Verify with `Unity_Camera_Capture`
5. `Unity_ManageScene(Action: "Save")`

### Example 2: Modify an existing object
1. `Unity_ManageScene(Action: "GetHierarchy")` to inspect the structure
2. `Unity_ManageGameObject(action: "modify", target: "Player", position: [0,1,0])`

## Unity_RunCommand Known Pitfalls

### Image namespace collision (CS0118)
Using `UnityEngine.UI.Image` collides with the `Image` namespace and fails to compile.
```csharp
// NG: CS0118 'Image' is a namespace but is used like a type
using UnityEngine.UI;
var img = obj.AddComponent<Image>();

// OK: avoid the collision with an alias
using UIImage = UnityEngine.UI.Image;
var img = obj.AddComponent<UIImage>();
```

### Getting the TextMeshPro font
`TMP_Settings.defaultFontAsset` can return null. Use `AssetDatabase.FindAssets`:
```csharp
// NG: may throw NullReferenceException
var font = TMP_Settings.defaultFontAsset;

// OK: find the font via asset search
var fontGuids = AssetDatabase.FindAssets("t:TMP_FontAsset");
TMP_FontAsset font = null;
if (fontGuids.Length > 0)
    font = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(AssetDatabase.GUIDToAssetPath(fontGuids[0]));
```

### TMP Essential Resources
TextMeshPro Essential Resources must be imported before using TextMeshPro. If the font is not found, import it first.

## Troubleshooting
- **MCP connection error**: confirm the Unity Editor is running. Edit > Project Settings > AI > Unity MCP.
- **Object not found**: check the name with `Unity_ManageScene(Action: "GetHierarchy")`.
- **Sprite not showing**: the SpriteRenderer's sprite may be null. Check that the texture's Import Settings are set to Sprite (2D and UI).
- **RunCommand failure**: check the `result.LogError()` message; missing `using` is a frequent cause.
- **Image type error (CS0118)**: use the `using UIImage = UnityEngine.UI.Image;` alias.
- **TMP font null**: use `AssetDatabase.FindAssets("t:TMP_FontAsset")` rather than `TMP_Settings.defaultFontAsset`.
