---
name: isaac-sim-sdg
description: Reference guide for Synthetic Data Generation (SDG) in Isaac Sim 5.1+ using the full Action and Event Data Generation platform. Covers IRA (actor simulation), IRO (object randomization), IRC (VLM captioning), IRI (physical events), and RTX sensor placement. Use when designing SDG pipelines, writing YAML configs, setting up writers, or configuring data output for Vision AI training.
---

# Isaac Sim SDG (Synthetic Data Generation)

## Platform Overview

Isaac Sim's **Action and Event Data Generation** platform generates training datasets for Vision AI models by simulating complex indoor scenarios. All extensions run on top of NVIDIA Replicator.

| Extension | Full name | Role |
|---|---|---|
| IRA | `isaacsim.replicator.agent` | Human characters + robots simulation and data capture |
| IRO | `isaacsim.replicator.object` | Object placement with domain randomization |
| IRC | `isaacsim.replicator.caption` | VLM image-caption pair generation |
| IRI | `isaacsim.replicator.incident` | Physical events (fire, spill, topple) |
| — | `isaacsim.sensors.rtx.placement` | Optimal camera placement + calibration export |

> **pip install note**: All extensions live under `site-packages/isaacsim/extscache/`. There is no `python.sh` — launch with `conda activate isaaclab && python script.py`. The `tools/actor_sdg/sdg_scheduler.py` batch runner does NOT exist in pip installs (standalone only); drive everything from your own `SimulationApp` script.

---

## IRA — Actor Simulation SDG

### YAML Configuration Structure

```yaml
isaacsim.replicator.agent:
  version: 0.7.1          # must match extension minor version (0.7.x compatible with 0.7.y)

  global:
    seed: 42
    simulation_length: 300  # frames at 30 FPS (300 = 10 seconds)

  scene:
    asset_path: /path/to/environment.usd
    # Environment must have a NavMesh for actor spawning and pathfinding
    # Disable NavMesh auto-bake for performance; pre-bake manually

  sensor:
    num: 4                  # camera count; reduce if "cuda external memory" errors occur

  character:
    num: 5
    asset_path: /path/to/characters/
    command_file: /path/to/commands.txt
    filters: []             # subset from filter.json labels
    spawn_area: NavMeshZoneName
    navigation_area: NavMeshZoneName

  robot:
    nova_carter_num: 1
    iw_hub_num: 0
    write_data: true        # capture data from robot onboard cameras

  response:                 # optional: actor reactions to events
    - CommandResponse:
        name: "AlertResponse"
        priority: 1
        pick_agent: nearest
        resume: true
        trigger: {type: time, time: 5.0}
        commands:
          - "Character GoTo 0.0 0.0 0.0 _"
          - "Character LookAround 5"

  incident:                 # optional: physical events (requires IRI)
    - ToppleEvent:
        name: box_falls
        topple_item:
          item: $random_loose_item$
          topple_nearby_radius: 1.5
        trigger: {type: time, time: 3.0}

  replicator:
    writer: IRABasicWriter   # see Writer Options below
    output_path: /path/to/output/
```

### Character Command File Format

```
# One command per line; first token = character prim name
Character GoTo 3.0 0.0 0.0 _          # GoTo x y z angle|_
Character Idle 10                       # stand still for 10 seconds
Character LookAround 5                  # head sway for 5 seconds
Character GoTo -3.0 0.0 0.0 90
Character Sit /World/Chair 5            # walk to seat prim, sit 5 seconds
# lines starting with # are ignored
```

### Command Randomization (transition map)

Place `character_command_transition_map.json` in the character asset directory to control random behavior sequences:

```json
{
  "Idle":      { "weight": 0.3, "transitions": { "GoTo": 0.6, "LookAround": 0.4 } },
  "GoTo":      { "weight": 0.5, "transitions": { "Idle": 0.5, "Sit": 0.3, "LookAround": 0.2 } },
  "LookAround":{ "weight": 0.2, "transitions": { "GoTo": 0.7, "Idle": 0.3 } }
}
```

Built-in randomization defaults: Idle 2–6 s, LookAround 2–4 s, GoTo 5–20 m, Sit 4–8 s.

### Actor CommandResponse (runtime event triggers)

```yaml
CommandResponse:
  name: "MyResponse"
  priority: 1               # higher priority preempts lower when simultaneous
  pick_agent: nearest       # all | first_available | nearest | furthest
  resume: true              # resume prior task after response
  position: [0, 0, 0]       # reference point for nearest/furthest selection
  trigger:
    type: time              # time | carb_event | incident
    time: 5.0
  commands:
    - "Character GoTo 0 0 0 _"
    - "Character LookAround 5"
```

Trigger types:

| Type | Config example | Fires when |
|---|---|---|
| `time` | `{type: time, time: 5.0}` | N seconds into simulation |
| `carb_event` | `{type: carb_event, event_name: "my_event"}` | carb event dispatched |
| `incident` | `{type: incident, incident_name: "fire_starts"}` | IRI physical event triggers |

### Camera Placement Settings

All paths are under `/persistent/exts/isaacsim.replicator.agent/`:

```python
s = carb.settings.get_settings()
s.set("/persistent/exts/isaacsim.replicator.agent/aim_camera_to_character", True)
s.set("/persistent/exts/isaacsim.replicator.agent/character_focus_height",  0.7)   # m
s.set("/persistent/exts/isaacsim.replicator.agent/min_camera_distance",     6.5)   # m
s.set("/persistent/exts/isaacsim.replicator.agent/max_camera_distance",    14.0)   # m
s.set("/persistent/exts/isaacsim.replicator.agent/min_camera_height",       2.0)   # must > focus_height
s.set("/persistent/exts/isaacsim.replicator.agent/max_camera_height",       3.0)   # must < max_distance
s.set("/persistent/exts/isaacsim.replicator.agent/min_camera_look_down_angle", 0)  # degrees
s.set("/persistent/exts/isaacsim.replicator.agent/max_camera_look_down_angle", 60) # degrees
s.set("/persistent/exts/isaacsim.replicator.agent/min_camera_focallength",  13)    # mm
s.set("/persistent/exts/isaacsim.replicator.agent/max_camera_focallength",  23)    # mm
s.set("/persistent/exts/isaacsim.replicator.agent/randomize_camera_info",  True)
```

---

## IRA — Writer Options

Writers control output format. All extend `IRABasicWriter`, which itself extends Replicator `BasicWriter`.

### Annotator name overrides (IRA-specific)

| Standard Replicator name | IRA override |
|---|---|
| `bounding_box_2d_tight` | `object_info_bounding_box_2d_tight` |
| `bounding_box_2d_loose` | `object_info_bounding_box_2d_loose` |
| `bounding_box_3d` | `object_info_bounding_box_3d` |
| `skeleton_data` | `agent_info_skeleton_data` |

Output is organized per-annotator into separate subdirectories.

### IRABasicWriter

Default writer. Enabled outputs:
- `object_info_bounding_box_2d_tight/loose` — 2D bounding boxes
- `object_info_bounding_box_3d` — 3D bounding boxes
- `agent_info_skeleton_data` — skeleton keypoints
- RGB images and camera parameters (always on)

### TaoWriter

Extends IRABasicWriter with occlusion filtering:

```yaml
replicator:
  writer: TaoWriter
  writer_params:
    shoulder_height_ratio: 0.25         # min upper-body visibility fraction
    valid_width_unoccluded_threshold: 0.6
    valid_height_unoccluded_threshold: 0.6
```

Logic: occluded characters require BOTH height AND width above threshold; truncated/mixed cases require EITHER.

### StereoWriter

For stereo camera pairs. Camera naming convention: left = `Camera_01`, right = `Camera_01_R`.

```yaml
replicator:
  writer: StereoWriter
  writer_params:
    customized_camera_params: true      # exports fx, fy, cx, cy + stereo baseline
    customized_distance_to_image_plane: true  # PFM format depth
    depth_format: PNG                   # PNG | NPM alternative
```

### RTSPWriter

Real-time video streaming. Requires FFmpeg. Initial frames may have artifacts.

```yaml
replicator:
  writer: RTSPWriter
  writer_params:
    rtsp_stream_url: "rtsp://localhost:8554"
    # URL per camera: {base_url}/RTSPWriter{camera_path_underscores}_{annotator}
```

Supports: RGB, semantic segmentation, instance ID segmentation, normals, distance. GPU-accelerated via NVENC when available.

### Custom Writers

Register a custom writer following Replicator's custom writer spec, then reference by name in the YAML `writer` field.

---

## IRI — Physical Event Generation

Generates physical events with automatic semantic labeling. Requires scene items tagged via the **Event Scene Tagger** (`Tools > Action and Event Data Generation > Event Scene Tagger`).

### Tag types
- **Loose items** → eligible for topple events
- **Spillable items** → eligible for spill events
- **Flammable items** → eligible for fire events

### Event types

```yaml
# Topple: apply force to knock over loose items
ToppleEvent:
  name: box_falls
  topple_item:
    item: $random_loose_item$     # or specific prim path
    topple_nearby_radius: 1.5     # radius (m) of nearby items that also topple
  force_direction: random         # random | navmesh | closest_waypoint
  trigger: {type: time, time: 3.0}
# Semantic label added: incident_toppled_item

# Fire: ignite a flammable item
FireEvent:
  name: fire_starts
  flammable_item:
    item: $random_flammable_item$
  trigger: {type: time, time: 6.0}
# Semantic label added: incident_flaming_item

# Spill: liquid spillage from a spillable item
SpillEvent:
  name: liquid_spill
  leakable_item:
    item: $random_leakable_item$
    target_size: 1.5              # spill radius (m)
    leak_duration: 5.0            # seconds
  trigger: {type: time, time: 9.0}
# Semantic labels added: incident_leaking_item, incident_liquid_spill
```

Event log (YAML) is written to the output directory alongside image data.

---

## IRO — Object Randomization SDG

No-code domain randomization for object detection datasets. Configured via YAML description files.

### Minimal config

```yaml
isaacsim.replicator.object:
  version: 0.4.x
  num_frames: 100
  output_path: /path/to/output
  screen_height: 1080
  screen_width: 1920
  seed: 0
  gravity: true
  friction: 0.5
  simulation_time: 0.5          # physics settle time per frame (seconds)
```

### Output

- RGB images (JPEG)
- Segmentation masks (PNG)
- 2D bounding box annotations: `x_min x_max y_min y_max` per object per line

> All USD models must be in USD format. Convert OBJ/FBX with the Isaac Sim asset converter.

### Key concepts

- **Mutable**: a randomized object with configurable position, rotation, scale, material distributions
- **Harmonizer**: constraint between mutables (e.g. "object A must be on top of object B")
- **Macro**: reusable mutable group template

### Docker headless run

```bash
docker run --gpus device=0 --entrypoint /bin/bash \
  -v LOCAL_PATH:/tmp --network host -it ISAAC_SIM_DOCKER_URL

# Inside container:
bash isaac-sim.sh --no-window \
  --enable isaacsim.replicator.object \
  --allow-root \
  --config/file=PATH_TO_CONFIG.yaml
```

---

## IRC — VLM Scene Captioning

Generates image + caption pairs for vision-language model training. Uses 3D scene graph to produce spatially-grounded natural language descriptions.

### Enable and configure

```python
# Enable extension
from isaacsim.core.utils.extensions import enable_extension
enable_extension("isaacsim.replicator.caption.core")
```

### Key config parameters

| Parameter | Purpose |
|---|---|
| `camera_prim_path` | Camera to capture from |
| `scene_path` | USD scene file |
| `output_path` | Output directory |
| `pruning_ratio` | Scene graph complexity (0.0–1.0); lower = simpler graph |
| `max_object_capacity` | Max objects included in scene graph |

### Integration with IRA

Add `SceneGraphWriter` to the IRA replicator config to generate captions per frame during character simulation.

### Integration with IRO

Use `CombinedIROSceneGraphWriter` to combine domain randomization outputs with captions.

### Output files

| File | Format |
|---|---|
| Full scene graph | JSON |
| Pruned scene graph | JSON |
| Captions | JSON |
| Visualized scene graph | JPEG |
| Point clouds / depth | Optional |

---

## RTX Sensor Placement

Automates camera positioning for surveillance/monitoring scenarios (warehouses, retail).

### Two components

**Camera Placement**: Finds optimal camera locations given scene geometry and coverage requirements. Balances coverage vs. deployment cost.

**Camera Calibration**: Exports per-camera metadata (position, orientation, FOV polygon) to JSON for downstream integration.

Enable via Extension Manager: `isaacsim.sensors.rtx.placement`. Two separate UI windows appear after enabling.

---

## Custom Environment Requirements

For any environment to work with IRA:

- **Format**: USD with proper root layer attributes
- **Units**: meters (`metersPerUnit = 1`)
- **Axes**: Z-up, -Y forward
- **NavMesh**: required for actor spawning and pathfinding
  ```
  Stage panel → right-click → Create > Navigation > NavMesh Include Volume
  Scale volume to cover walkable area → Navigation window → Bake
  ```
- **Lighting**: start with a Dome Light as base

### Import tip for non-USD assets

> "Open the Isaac Sim default empty stage. Drag your asset into the Stage panel. Isaac Sim automatically creates a new Xform for it and converts it to the right config."

---

## Custom Character Requirements

- Retargeted to **NVIDIA biped skeleton**
- Meters, Z-up, -Y forward
- One character per subdirectory under the `asset_path` folder
- Unreal Engine characters: export as USD → scale by 0.01 (cm→m) → retarget animations

---

## SDG Pipeline Decision Guide

| Goal | Use |
|---|---|
| People / robot detection training data | IRA |
| Object detection with heavy randomization | IRO |
| Image-text pairs for VLM training | IRC (standalone or with IRA/IRO) |
| Anomaly / incident detection datasets | IRA + IRI |
| Optimal surveillance camera layout | RTX Sensor Placement |
| Stereo depth training data | IRA + StereoWriter |
| Real-time streaming annotation | IRA + RTSPWriter |

---

## Common Pitfalls

| Pitfall | Cause | Fix |
|---|---|---|
| `cuda external memory` error | Too many cameras for VRAM | Reduce `sensor.num` in config |
| Actors don't spawn | No NavMesh or wrong spawn area name | Bake NavMesh; check `spawn_area` matches volume name |
| `sdg_scheduler.py` not found | pip install lacks standalone scripts | Drive pipeline from `SimulationApp` Python script |
| Config version mismatch | `version: 0.7.1` vs extension `0.7.28` | Only minor version must match (0.7.x = 0.7.y) |
| Environment Z-axis wrong | Asset not in Z-up | Drag into empty Isaac Sim stage to auto-convert |
| RTSP stream artifacts on first frames | Stream initialization latency | Normal; discard first N frames in postprocessing |
| Character animations not found | Custom anim not retargeted to NVIDIA biped | Use `CreateRetargetAnimationsCommand` before import |
