---
name: isaac-sim-person-simulation
description: Reference guide for simulating human characters in Isaac Sim 5.1+ (pip install, conda env) using omni.anim.people + IRA (isaacsim.replicator.agent). Use when writing scripts to spawn characters, drive movement via GoTo/Idle commands, inject commands at runtime, or configure navigation. All API details are verified against extscache source code.
---

# Isaac Sim Person Simulation

## Environment (pip install, not standalone)

| Item | Value |
|---|---|
| Version | Isaac Sim 5.1.0.0 |
| Conda env | `isaaclab` |
| Python | 3.11 |
| Package root | `/home/leo/miniconda/envs/isaaclab/lib/python3.11/site-packages/isaacsim` |
| extscache | `<package_root>/extscache/` |

> **Critical**: `python.sh` does NOT exist in pip installs. Launch with `conda activate isaaclab && python script.py`.
> Extension source paths depend on the install method — for pip installs, all ext source lives under `extscache/` inside the site-packages.

**Verified extension versions (pip install)**

| Extension | extscache directory |
|---|---|
| `omni.anim.people` | `omni.anim.people-0.7.9+107.3.3/` |
| `isaacsim.replicator.agent.core` | `isaacsim.replicator.agent.core-0.7.28+107.3.3/` |
| `isaacsim.replicator.agent.ui` | `isaacsim.replicator.agent.ui-0.7.11+107.3.3/` |

---

## Key Source Files (for debugging / reading internals)

All paths are relative to the corresponding extscache directory.

| File | Role |
|---|---|
| `omni/anim/people/scripts/character_behavior.py` | BehaviorScript host; `on_update` drives the command loop |
| `omni/anim/people/scripts/commands/base_command.py` | Base class; `walk()` sets the three AnimGraph variables |
| `omni/anim/people/scripts/commands/goto.py` | `GoTo` command implementation |
| `omni/anim/people/scripts/navigation_manager.py` | Path generation and dynamic avoidance |
| `omni/anim/people/settings.py` | All `carb.settings` key constants (`PeopleSettings`, `AgentEvent`) |
| `isaacsim/replicator/agent/core/agent_manager.py` | `AgentManager` singleton; `inject_command` entry point |
| `isaacsim/replicator/agent/core/stage_util.py` | `CharacterUtil`: spawn / attach scripts / attach anim graph |
| `isaacsim/replicator/agent/core/settings.py` | `AssetPaths`, `PrimPaths`, `BehaviorScriptPaths` key constants |

---

## Architecture: How a Character Moves (verified)

```
World.step(render=True)
  └─ omni.kit.scripting tick
       └─ CharacterBehavior.on_update(current_time, delta_time)   [character_behavior.py:537]
            │
            ├─ [frame 1, self.character is None]
            │     init_character()                                  [line 544]
            │       → ag.get_character(prim_path)
            │       → load commands from file into self.commands
            │       → append GoTo(spawn_pos) if number_of_loop > 0  (closes the loop)
            │     register_to_agent_manager()                       [line 548, sibling call — NOT inside init_character]
            │       → carb.eventdispatcher.dispatch_event(AgentEvent.AgentRegistered, payload)
            │
            └─ [subsequent frames]
                  execute_command(self.commands, delta_time)        [line 553]
                    └─ GoTo.execute(dt) → walk(dt)                 [base_command.py:160]
                          character.set_variable("Action", "Walk")
                          character.set_variable("PathPoints", nav_mgr.get_path_points())
                          character.set_variable("Walk", actual_walk_speed)  # blended 0→1
                         [on destination reached]
                          character.set_variable("Action", "None")
```

> **Important**: `register_to_agent_manager()` is called by `on_update` directly after `init_character()` returns True. It is NOT a nested call inside `init_character()`.

---

## AnimGraph Variables (low-level interface)

```python
import omni.anim.graph.core as ag

# Only valid AFTER simulation starts (runtime)
character = ag.get_character(prim_path_str)

# Read/write world transform
pos = carb.Float3(0, 0, 0)
rot = carb.Float4(0, 0, 0, 1)
character.get_world_transform(pos, rot)
character.set_world_transform(pos, rot)   # use only for snap/rotate, NOT for locomotion

# Drive the AnimGraph state machine
character.set_variable("Action", "Walk")                         # enter walk state
character.set_variable("PathPoints", [carb.Float3(x, y, z)])    # AnimGraph moves the prim AND drives animation
character.set_variable("Walk", 1.0)                              # blend weight 0~1 (fade in/out)
character.set_variable("Action", "None")                         # stop
```

> Setting `PathPoints` causes AnimGraph to **simultaneously** update the character's transform AND animation.
> Do NOT manually move the prim while AnimGraph is driving it.
> `set_world_transform` is only for rotation alignment or forced teleport.

---

## Command System (high-level interface)

### Command string format
```
"{character_prim_name} {CommandName} [params...]"
```

### Built-in commands (verified from character_behavior.py:452-483 + official docs)
| Command | Syntax | Notes |
|---|---|---|
| `GoTo` | `GoTo x y z angle\|_` | `_` = no forced final rotation |
| `Idle` | `Idle <seconds>` | Stand in place for given duration, e.g. `Idle 10` |
| `LookAround` | `LookAround <seconds>` | Head sway for given duration, e.g. `LookAround 10` |
| `Sit` | `Sit <seat_prim_path> <seconds>` | Walk to seat prim and sit, e.g. `Sit /World/Chair 5`. Seat prim needs `walk_to_offset` and `interact_offset` child xforms. |
| `GoToSection` | `GoToSection ...` | |
| `GoToObject` | `GoToObject ...` | |
| `Queue` / `Dequeue` | `Queue name` / `Dequeue name` | Multi-character queuing |

> More commands exist via dynamic import (e.g., `Talk`, `TalkWith`).

### `inject_command` via AgentManager

```python
from isaacsim.replicator.agent.core.agent_manager import AgentManager

AgentManager.get_instance().inject_command(
    agent_name="Character",          # must match character prim name under /World/Characters
    command_list=["Character GoTo 3.0 0.0 0.0 _"],
    force_inject=False,              # True → interrupts current command first
    instant=True,                    # True → insert at queue[1]; False → append to end
    on_finished=("cb_id", lambda cb_id, agent_name: print(f"{agent_name} arrived")),
)
```

**`on_finished` mechanism** (verified from character_behavior.py:349-352):
- A sentinel `COMMAND_CALLBCAK_CHECKPOINT` (note: typo in source — "CALLBCAK") is appended to the **injected command array**.
- When `instant=True`, the array is inserted at index 1 in the queue (current command finishes first).
- The sentinel fires the callback when the injected commands complete.
- Chain the next command inside the callback to build sequential or looping routes.

---

## AgentRegistered Event

```python
import carb.eventdispatcher
from omni.anim.people.settings import AgentEvent
# AgentEvent.AgentRegistered == "omni.anim.people/REGISTER_AGENT"

def on_agent_ready(event):
    # Access payload as attribute, then dict key (verified from agent_manager.py:175-181)
    payload = event.payload
    agent_name = payload["agent_name"]
    prim_path  = payload["prim_path"]
    # Safe to call inject_command or ag.get_character() from here

sub = carb.eventdispatcher.get_eventdispatcher().observe_event(
    event_name=AgentEvent.AgentRegistered,
    on_event=on_agent_ready,
    observer_name="my_unique_observer_name",
)
# MUST wait for this event before calling inject_command or ag.get_character()
```

---

## Navigation Settings

```python
s = carb.settings.get_settings()

# Straight-line path (no navmesh)
s.set("/exts/omni.anim.people/navigation_settings/navmesh_enabled", False)

# Obstacle-avoiding path (uses navmesh.query_shortest_path, agent_radius=0.5)
s.set("/exts/omni.anim.people/navigation_settings/navmesh_enabled", True)

# Multi-character velocity-prediction avoidance (NavigationManager.update_path)
s.set("/exts/omni.anim.people/navigation_settings/dynamic_avoidance_enabled", True)
```

---

## Static Command File Loop Mode

```python
s = carb.settings.get_settings()
s.set("/exts/omni.anim.people/command_settings/command_file_path", "/abs/path/to/commands.txt")
s.set("/exts/omni.anim.people/command_settings/number_of_loop", "inf")
# "inf" is parsed as math.inf in character_behavior.py:94-95
# init_character() automatically appends GoTo(spawn_pos) at the end to close the loop
```

**Command file format** (one command per line, first token = prim name):
```
Character GoTo 3.0 0.0 0.0 _
Character Idle 5
Character LookAround 3
Character GoTo -3.0 0.0 0.0 90
Character Sit /World/Chair 5
# lines starting with # are comments
```

---

## Character Spawn Standard Flow

```python
from isaacsim.replicator.agent.core.stage_util import CharacterUtil

# Step 1 — Load Biped_Setup.usd template (creates /World/Characters prim if needed)
CharacterUtil.load_default_biped_to_stage()

# Step 2 — Load character USD into stage
char_prim = CharacterUtil.load_character_usd_to_stage(
    character_usd_path="/path/to/F_Business_02.usd",
    spawn_location=(0.0, 0.0, 0.0),
    spawn_rotation=0.0,                  # degrees, Z-axis
    character_stage_name="Character",    # prim name = token used in command strings
)

# Step 3 — Get SkelRoot list (behavior scripts attach here, not on Xform root)
skelroot_list = CharacterUtil.get_characters_in_stage()

# Step 4 — Attach BehaviorScript
CharacterUtil.setup_python_scripts_to_character(skelroot_list, behavior_script_path)

# Step 5 — Attach AnimationGraph (copy from Biped_Setup)
anim_graph = CharacterUtil.get_anim_graph_from_character(
    CharacterUtil.get_default_biped_character()
)
CharacterUtil.setup_animation_graph_to_character(skelroot_list, anim_graph)
```

**AnimGraphSchema plugin registration** (required in script mode, pip install):

```python
import os
from pxr import Plug
import omni.kit.app

mgr = omni.kit.app.get_app().get_extension_manager()
ext_path = mgr.get_extension_path_by_module("omni.anim.graph.schema")
Plug.Registry().RegisterPlugins(
    os.path.join(ext_path, "plugins", "AnimGraphSchema", "resources")
)
# Without this, AnimationGraph schema is not found in script mode
```

---

## All `carb.settings` Key Paths (verified)

### omni.anim.people (settings.py)
| Path | Constant | Default |
|---|---|---|
| `/exts/omni.anim.people/command_settings/command_file_path` | `PeopleSettings.COMMAND_FILE_PATH` | — |
| `/exts/omni.anim.people/command_settings/number_of_loop` | `PeopleSettings.NUMBER_OF_LOOP` | — |
| `/exts/omni.anim.people/navigation_settings/navmesh_enabled` | `PeopleSettings.NAVMESH_ENABLED` | — |
| `/exts/omni.anim.people/navigation_settings/dynamic_avoidance_enabled` | `PeopleSettings.DYNAMIC_AVOIDANCE_ENABLED` | — |
| `/persistent/exts/omni.anim.people/character_prim_path` | `PeopleSettings.CHARACTER_PRIM_PATH` | `/World/Characters` |

### isaacsim.replicator.agent (settings.py)
| Path | Constant | Default / Notes |
|---|---|---|
| `/exts/isaacsim.replicator.agent/asset_settings/default_biped_assets_path` | `AssetPaths.DEFAULT_BIPED_ASSET_PATH` | `<nucleus_root>/Isaac/People/Characters/Biped_Setup.usd` |
| `/exts/isaacsim.replicator.agent/asset_settings/default_character_asset_path` | `AssetPaths.DEFAULT_CHARACTER_PATH` | `<nucleus_root>/Isaac/People/Characters/` |
| `/exts/isaacsim.replicator.agent/characters_parent_prim_path` | `PrimPaths.CHARACTERS_PARENT_PATH` | `/World/Characters` |

### isaacsim.replicator.agent — camera placement (persistent, from official docs)
| Path | Default | Notes |
|---|---|---|
| `/persistent/exts/isaacsim.replicator.agent/aim_camera_to_character` | `True` | Camera tracks character |
| `/persistent/exts/isaacsim.replicator.agent/character_focus_height` | `0.7` | Focus height offset (m) |
| `/persistent/exts/isaacsim.replicator.agent/min_camera_distance` | `6.5` | Min distance to character (m) |
| `/persistent/exts/isaacsim.replicator.agent/max_camera_distance` | `14.0` | Max distance to character (m) |
| `/persistent/exts/isaacsim.replicator.agent/min_camera_height` | `2.0` | Must be > `character_focus_height` |
| `/persistent/exts/isaacsim.replicator.agent/max_camera_height` | `3.0` | Must be < `max_camera_distance` |
| `/persistent/exts/isaacsim.replicator.agent/min_camera_look_down_angle` | `0` | Degrees |
| `/persistent/exts/isaacsim.replicator.agent/max_camera_look_down_angle` | `60` | Degrees |
| `/persistent/exts/isaacsim.replicator.agent/min_camera_focallength` | `13` | mm |
| `/persistent/exts/isaacsim.replicator.agent/max_camera_focallength` | `23` | mm |
| `/persistent/exts/isaacsim.replicator.agent/randomize_camera_info` | `True` | Randomizes focal length |

---

## Minimal Working Script Template

```python
from isaacsim import SimulationApp
simulation_app = SimulationApp({"headless": False})

from isaacsim.core.utils.extensions import enable_extension
enable_extension("isaacsim.replicator.agent.core")
enable_extension("omni.anim.people")

import carb
import carb.eventdispatcher
from omni.isaac.core import World
from omni.anim.people.settings import AgentEvent
from isaacsim.replicator.agent.core.agent_manager import AgentManager
from isaacsim.replicator.agent.core.stage_util import CharacterUtil

world = World(physics_dt=0.005, rendering_dt=0.02)
world.scene.add_default_ground_plane()

# Register AnimGraphSchema plugin
import os
from pxr import Plug
import omni.kit.app
mgr = omni.kit.app.get_app().get_extension_manager()
ext_path = mgr.get_extension_path_by_module("omni.anim.graph.schema")
Plug.Registry().RegisterPlugins(
    os.path.join(ext_path, "plugins", "AnimGraphSchema", "resources")
)

# Configure navigation
s = carb.settings.get_settings()
s.set("/exts/omni.anim.people/navigation_settings/navmesh_enabled", False)
s.set("/exts/omni.anim.people/navigation_settings/dynamic_avoidance_enabled", False)

# Spawn character
CharacterUtil.load_default_biped_to_stage()
char_prim = CharacterUtil.load_character_usd_to_stage(
    character_usd_path="assets/characters/F_Business_02.usd",
    spawn_location=(0.0, 0.0, 0.0),
    spawn_rotation=0.0,
    character_stage_name="Character",
)
skelroot_list = CharacterUtil.get_characters_in_stage()
behavior_script_path = mgr.get_extension_path_by_module("omni.anim.people") \
    + "/omni/anim/people/scripts/character_behavior.py"
CharacterUtil.setup_python_scripts_to_character(skelroot_list, behavior_script_path)
anim_graph = CharacterUtil.get_anim_graph_from_character(CharacterUtil.get_default_biped_character())
CharacterUtil.setup_animation_graph_to_character(skelroot_list, anim_graph)

# Wait for AgentRegistered, then inject command
def on_agent_ready(event):
    name = event.payload["agent_name"]
    AgentManager.get_instance().inject_command(
        agent_name=name,
        command_list=[f"{name} GoTo 3.0 0.0 0.0 _"],
        instant=True,
    )

sub = carb.eventdispatcher.get_eventdispatcher().observe_event(
    event_name=AgentEvent.AgentRegistered,
    on_event=on_agent_ready,
    observer_name="my_agent_ready_observer",
)

world.reset()
while simulation_app.is_running():
    world.step(render=True)

simulation_app.close()
```

---

## CommandResponse — Runtime Event Triggers (from official docs)

Characters can be configured to react to runtime events (time, carb events, or physical incidents) using `CommandResponse`. This is configured in the IRA YAML config or injected programmatically.

```yaml
# In IRA YAML config under `response:` section
CommandResponse:
  name: "AlertResponse"
  priority: 1                        # higher = takes precedence when multiple fire simultaneously
  pick_agent: nearest                # all | first_available | nearest | furthest
  resume: true                       # resume prior task after response completes
  position: [0.0, 0.0, 0.0]         # optional: reference position for nearest/furthest selection
  trigger:
    type: time                       # time | carb_event | incident
    time: 5.0                        # seconds into simulation
  commands:
    - "Character GoTo 0.0 0.0 0.0 _"
    - "Character LookAround 5"
```

**Trigger types:**
| Type | Config | When fires |
|---|---|---|
| `time` | `{type: time, time: 5.0}` | At N seconds into simulation |
| `carb_event` | `{type: carb_event, event_name: "my_event"}` | When that carb event is dispatched |
| `incident` | `{type: incident, incident_name: "fire_starts"}` | When an IRI physical event triggers |

---

## IRA YAML Configuration (full SDG pipeline)

When running IRA as a full SDG pipeline (not just character simulation), configure via a YAML file.

```yaml
isaacsim.replicator.agent:
  version: 0.7.1          # must match extension minor version (0.7.x)

  global:
    seed: 42
    simulation_length: 300  # frames at 30 FPS → 300 = 10 seconds

  scene:
    asset_path: /path/to/environment.usd

  sensor:
    num: 4                  # number of cameras; reduce if VRAM errors occur

  character:
    num: 5
    asset_path: /path/to/characters/
    command_file: /path/to/commands.txt
    spawn_area: NavMeshAreaName
    navigation_area: NavMeshAreaName

  robot:
    nova_carter_num: 1
    iw_hub_num: 0
    write_data: true         # capture from robot cameras

  replicator:
    writer: IRABasicWriter
    output_path: /path/to/output/
```

> **pip install note**: `tools/actor_sdg/sdg_scheduler.py` does NOT exist in pip installs (standalone only). Drive the pipeline from your own Python script using `SimulationApp` + IRA APIs directly.

**Writer options:**
| Writer | Key feature |
|---|---|
| `IRABasicWriter` | Default; RGB + bounding boxes + skeleton data |
| `TaoWriter` | Adds occlusion filtering (shoulder/width/height thresholds) |
| `StereoWriter` | Stereo camera pairs; outputs PFM depth + intrinsics JSON |
| `RTSPWriter` | Real-time RTSP video stream; requires FFmpeg |

---

## Common Pitfalls

| Pitfall | Root Cause | Fix |
|---|---|---|
| `ag.get_character()` returns None | Called before simulation starts | Only call after `AgentRegistered` event fires |
| Commands ignored silently | `inject_command` called before `AgentRegistered` | Subscribe to event; inject inside callback |
| AnimGraphSchema not found | USD plugin not registered in script mode | Call `Plug.Registry().RegisterPlugins(...)` before spawning |
| Character name mismatch | `character_stage_name` ≠ token in command string | They must be identical (e.g., both `"Character"`) |
| `python.sh` not found | pip install has no standalone launcher | Use `conda activate isaaclab && python script.py` |
| `on_finished` never fires | `instant=True` inserts at queue[1]; if queue empty, at [0] — works fine; but if agent never registered, callback never added | Ensure agent is registered before injecting |
| `COMMAND_CALLBCAK_CHECKPOINT` typo | Source code typo (`CALLBCAK` not `CALLBACK`) | Use the typo'd string if referencing the constant directly |
