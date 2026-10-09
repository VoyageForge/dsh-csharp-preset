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

- **Runtime** scripts live in `Assets/Scripts/Runtime/...` and ship in builds.
- **Editor-only** scripts (custom inspectors, menu items, `[CustomEditor]`) live in
  `Assets/Scripts/Editor/...` and must sit in an `Editor` assembly definition so they are excluded
  from builds.
- Separate them with `.asmdef` files: one for runtime, one for `Tests/Editor`, one for
  `Tests/Runtime`.

## Folder layout

Two layouts are both defensible; pick by project size and stay consistent. Unity's manual fixes only
the special folder names (`Editor`, `Resources`, `StreamingAssets`, `Plugins`) and their compile
order — it prescribes nothing about how to group your own scripts
([Special folders and script compilation order](https://docs.unity3d.com/6000.0/Documentation/Manual/ScriptCompileOrderFolders.html)).

**By feature/domain — preferred once a project has real gameplay systems**, because one feature's
code stays together and the tree keeps growing sideways instead of into ever-deeper type buckets:

```
Assets/Scripts/
  Runtime/
    Core/        # GameManager, ServiceLocator
    Gameplay/    # player, enemies, mechanics
    UI/          # UI controllers
    Data/        # ScriptableObjects, data types
  Editor/
    Tools/       # custom editor tools, inspectors
```

**By type — fine for small projects and prototypes**, and the more common convention in Chinese-language
Unity projects, which usually also wrap first-party content in an `_Project/` folder so the leading
underscore sorts it above imported Asset Store and plugin assets:

```
Assets/
  _Project/              # first-party content; underscore keeps it on top
    Scenes/
    Scripts/
      Core/              # lifecycle, events
      Managers/          # global managers, singletons
      Controllers/       # per-feature behaviour
      Systems/           # physics, networking, AI
      UI/
      Utilities/
      Data/
  Plugins/               # third-party
  Editor/                # editor-only extensions
```

Either way: `Runtime/` and `Editor/` stay apart (with `.asmdef` files), folder path mirrors the
namespace when you use namespaces, and a feature that outgrows its folder graduates to its own
top-level folder rather than gaining another level of nesting.

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
