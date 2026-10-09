---
name: csharp-file-organization
description: >-
  How to split Unity C# code across files and classes: one MonoBehaviour (or type) per file,
  when and how to break up a large script, editor/runtime assembly split, and member ordering
  inside a MonoBehaviour. Use when writing or restructuring Unity C# scripts, when a script or
  method is too large, when deciding script folder layout, or when the user asks about splitting
  scripts, MonoBehaviour organization, or assembly definitions.
---

# Unity C# File and Class Organization

Source: Unity scripting conventions, justinwasilenko/Unity-Style-Guide, Richard Fu's Unity C# guideline.

## The one rule that matters most

**One public type per file.** Each `MonoBehaviour`, interface, enum, record, and plain C# class
gets its own `.cs` file named after the type: `PlayerController.cs` holds `PlayerController`,
`IDamageable.cs` holds `IDamageable`. Do not stack several MonoBehaviours or unrelated types in
one file.

In Unity, the file name must match the class name **because the `.cs` file name is what the
editor binds to a MonoBehaviour for attaching to GameObjects.** Renaming a class without renaming
the file breaks the reference.

## When to split a MonoBehaviour (it is too big when...)

- **More than one responsibility.** A script that moves the player, manages health, and plays
  sound is three jobs. Split into `PlayerMovement`, `Health`, and an audio component, then compose
  them on one GameObject.
- **More than roughly 150–200 lines.** Unity scripts should stay small; composition is the Unity
  idiom.
- **A method over ~15–20 lines.** Extract private methods first; if the steps are separate
  concerns, move them to their own component or a plain helper class.

How to split a large `PlayerController`:
1. `PlayerMovement` — reads input, moves the Rigidbody.
2. `PlayerHealth` — damage, death, invulnerability.
3. `PlayerAnimator` — reads state from the other two, drives the Animator.
4. Keep `PlayerController` only if it must coordinate the rest; otherwise delete it.

Use `[RequireComponent]` to make dependencies explicit:

```csharp
[RequireComponent(typeof(Rigidbody2D))]
public class PlayerMovement : MonoBehaviour
{
    // ...
}
```

## MonoBehaviour member ordering

Keep a consistent order inside every script (Unity Style Guide):

1. `[SerializeField]` inspector fields
2. Constants / static fields
3. Instance fields
4. `Awake()` / `OnEnable()` / `Start()` / `OnDisable()` / `OnDestroy()`
5. `Update()` / `FixedUpdate()` / `LateUpdate()`
6. Public methods
7. Private methods

## Editor vs runtime code

- **Runtime** scripts live under `Assets/Scripts/...` (grouped by feature/domain) and ship in builds.
- **Editor-only** scripts (custom inspectors, menu items, `[CustomEditor]`) live under
  `Assets/Editor/Scripts/...` and must sit in an `Editor` assembly definition so they are excluded
  from builds.
- Separate them with `.asmdef` files: one for runtime, one for `Assets/Tests/Editor`, one for
  `Assets/Tests/Runtime`.

## Folder layout

Unity's manual fixes only the special folder names (`Editor`, `Resources`, `StreamingAssets`,
`Plugins`) and their compile order; it prescribes nothing about grouping your own files
([Special folders and script compilation order](https://docs.unity3d.com/6000.0/Documentation/Manual/ScriptCompileOrderFolders.html)).
This is the layout to follow — assets flat by type at the `Assets/` root, scripts grouped by
feature/domain under `Scripts/`, and editor-only code under `Editor/Scripts/`:

```
Assets/
  Scenes/            # one flat folder; feature subfolders only when it grows
  Prefabs/
  UI/                # art/sprites/materials for UI
  Art/  Audio/  Textures/  Materials/  Shaders/  Fonts/  Animation/   # siblings of UI
  Scripts/           # runtime code only — never editor-only code
    <Feature>/       # 视觉/, 听觉/, Manager/, Data/, Net/, Tool/, ... by domain
  Editor/
    Scripts/         # editor-only code; mirrors the feature folders it serves
  Resources/         # only assets loaded by string path at runtime
  StreamingAssets/
  Plugins/           # third-party, do not edit
  Settings/          # URP asset, post-process profile
```

Rules that follow from it:

- **Editor-only assets go under `Assets/Editor/`** — editor scripts, inspectors, `EditorWindow`s,
  gizmo drawers. Unity treats any folder named `Editor` as editor-only at any depth, so keeping
  exactly one at the root is a choice for clarity, not a requirement; what matters is that runtime
  code never references editor-only code and vice versa, enforced with `.asmdef` files. A runtime
  folder called `Scripts/Runtime/` only earns its extra level when runtime and editor trees really
  mirror one another; otherwise `Scripts/` **is** the runtime tree and the mirror of `Editor/Scripts/`.
- Script folders group **by domain**, not by type: a new attention-game script belongs in the
  attention feature folder, not in a `Controllers/` bucket. Type-based buckets (`Managers/`,
  `Controllers/`, `Utils/`) rot into dumping grounds once the project has real systems.
- A feature that outgrows its folder graduates to a top-level `Assets/<Feature>/` folder instead of
  gaining another level of nesting. Keep the existing tree instead of rebuilding it when adding one
  file, and do not introduce a second name for a folder that already exists — a project with both
  `Scenes/` and `SceneFiles/`, or both `Art/` and `Textures/`, is drift worth flagging rather than
  imitating.
- Assets stay flat by type at the root rather than nested behind a wrapper such as `_Project/`.
  The wrapper's only benefit is sorting first in the Project window; it costs a level in every path
  and is not used here.

Folder path mirrors the namespace when you use namespaces.

## Example: the right way to add a second type

```csharp
// PlayerMovement.cs
using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(Rigidbody2D))]
public class PlayerMovement : MonoBehaviour
{
    [SerializeField] private float _moveSpeed = 5f;
    private Rigidbody2D _rb;

    private void Awake() => _rb = GetComponent<Rigidbody2D>();

    private void FixedUpdate()
    {
        // New Input System — correct only when the project has it active.
        // For a legacy Input Manager project the equivalent is:
        //   float horizontal = Input.GetAxis("Horizontal");
        // Confirm the project's input solution first (see unity-coding-standards).
        float horizontal = Keyboard.current == null ? 0f
            : (Keyboard.current.dKey.isPressed ? 1f : 0f) - (Keyboard.current.aKey.isPressed ? 1f : 0f);
        _rb.linearVelocity = new Vector2(horizontal * _moveSpeed, _rb.linearVelocity.y);
    }
}
```

```csharp
// PlayerHealth.cs
using UnityEngine;

public class PlayerHealth : MonoBehaviour
{
    [SerializeField] private int _maxHealth = 100;
    private int _currentHealth;

    private void Awake() => _currentHealth = _maxHealth;

    public void TakeDamage(int amount)
    {
        _currentHealth -= amount;
        if (_currentHealth <= 0) Die();
    }

    private void Die()
    {
        // ... death logic
    }
}
```

Each script is one file, one responsibility, attached separately — instead of one `Player.cs`
with movement, health, and audio jammed together.

## What not to do

- Do not put multiple MonoBehaviours in one `.cs` file.
- Do not put editor code (`#if UNITY_EDITOR` blocks, custom inspectors) inside a runtime script.
- Do not keep a `Player.cs` that grows to 400 lines — compose components instead.
- Do not nest unrelated types just to avoid a new file.
