---
name: unity-project-init
description: >-
  Initialize a Unity project and configure URP / Post Processing. Use when starting a new
  Unity project, setting up the URP pipeline, configuring post processing, or creating the
  folder structure.
---

# Unity Project Initialization

Source: nyosegawa/unity-agent (template/.claude/skills/unity-project-init).

## URP Pipeline Setup
When starting a project, confirm the URP pipeline is set in GraphicsSettings, and set it if not.

```csharp
internal class CommandScript : IRunCommand
{
    public void Execute(ExecutionResult result)
    {
        // Find an existing URP pipeline asset
        var guids = AssetDatabase.FindAssets("t:UniversalRenderPipelineAsset");
        if (guids.Length == 0)
        {
            result.LogError("URP Pipeline Asset not found. URP package is installed?");
            return;
        }

        var path = AssetDatabase.GUIDToAssetPath(guids[0]);
        var pipelineAsset = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(path);

        // Set it in GraphicsSettings
        GraphicsSettings.defaultRenderPipeline = pipelineAsset;
        QualitySettings.renderPipeline = pipelineAsset;

        result.Log("URP Pipeline set: " + pipelineAsset.name + " from " + path);
    }
}
```
Required usings: `UnityEngine`, `UnityEditor`, `UnityEngine.Rendering`, `UnityEngine.Rendering.Universal`.

**Important**: do not create a new pipeline with `UniversalRenderPipelineAsset.Create()`. Renderer links break easily. Find and reuse the existing asset.

## URP Post Processing Setup
To enable Bloom, Vignette, etc., create a Volume + Profile and enable Post Processing on the camera.

```csharp
// Create Volume
var volumeGO = new GameObject("PostProcessVolume");
var volume = volumeGO.AddComponent<Volume>();
volume.isGlobal = true;
var profile = ScriptableObject.CreateInstance<VolumeProfile>();
AssetDatabase.CreateAsset(profile, "Assets/Settings/PostProcessProfile.asset");
volume.profile = profile;

// Bloom
var bloom = profile.Add<Bloom>();
bloom.threshold.overrideState = true; bloom.threshold.value = 1.0f;
bloom.intensity.overrideState = true; bloom.intensity.value = 0.8f;

// Vignette
var vignette = profile.Add<Vignette>();
vignette.intensity.overrideState = true; vignette.intensity.value = 0.25f;

// Enable Post Processing on the camera
var cam = Camera.main;
var camData = cam.GetComponent<UniversalAdditionalCameraData>();
if (camData == null) camData = cam.gameObject.AddComponent<UniversalAdditionalCameraData>();
camData.renderPostProcessing = true;
```
Required usings: `UnityEngine.Rendering`, `UnityEngine.Rendering.Universal`.

## Folder Structure

For a new project, create this layout. Script grouping follows the feature/domain convention; the
alternative type-based grouping (and the `Assets/_Project/` wrapper) is described in the
`csharp-file-organization` skill — pick one and stay consistent rather than mixing them.

```
Assets/
├── Scripts/
│   ├── Runtime/
│   │   ├── Core/           # GameManager, ServiceLocator
│   │   ├── Gameplay/       # Game mechanics
│   │   ├── UI/             # UI controllers
│   │   └── Data/           # ScriptableObjects
│   └── Editor/
│       └── Tools/          # Custom editor tools
├── Prefabs/
├── Scenes/
├── Materials/
├── Art/
│   ├── Textures/
│   ├── Sprites/
│   └── Models/
├── Audio/
├── Settings/               # URP Asset, Post Process Profile
└── Resources/              # Only for dynamically loaded assets
```

## Examples

### Example 1: Initialize a new 3D project
1. Create the folder structure with `Unity_RunCommand`.
2. Find the URP pipeline asset and set it in GraphicsSettings.
3. Create the Post Processing Volume and configure Bloom and Vignette.
4. Confirm Bloom is active with `Unity_Camera_Capture`.

### Example 2: Confirm URP is enabled in an existing project
1. Search assets with `AssetDatabase.FindAssets("t:UniversalRenderPipelineAsset")`.
2. Set `GraphicsSettings.defaultRenderPipeline` if null.
3. Check the camera has a `UniversalAdditionalCameraData` component.

## Troubleshooting
- **Bloom not working**: check the camera's `renderPostProcessing` is `true`, and the Volume's `isGlobal` is `true`.
- **Screen black / pink**: the URP Pipeline Asset is not set in GraphicsSettings. Set it with the search code above.
- **URP Asset not found**: the URP package may not be installed. Check with the Package Manager tool.
