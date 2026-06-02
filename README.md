# isaacsim-skills

A collection of [Claude Code](https://claude.ai/code) skills for **NVIDIA Isaac Sim** development.

Each skill is a reusable reference guide that Claude loads on demand — covering verified APIs, architecture notes, common pitfalls, and ready-to-run code templates.
All skills are verified against Isaac Sim **5.1.0.0** installed via **pip** (conda env).

---

## Available Skills

| Skill | Trigger command | Description |
|---|---|---|
| [isaac-sim-person-simulation](skills/isaac-sim-person-simulation/SKILL.md) | `/isaac-sim-person-simulation` | Spawn and control human characters using `omni.anim.people` + IRA (`isaacsim.replicator.agent`). Covers AnimGraph variables, command injection, navigation, and the full spawn flow. |

> More skills coming: robot locomotion, SDG pipeline, sensor setup, multi-agent coordination.

---

## Requirements

- [Claude Code](https://claude.ai/code) installed
- Isaac Sim **5.1+** installed via **pip** in a conda environment
  ```bash
  conda activate isaaclab   # or your env name
  python -c "import isaacsim; print('ok')"
  ```

> If you use a standalone Isaac Sim installer, extension paths will differ from what these skills document. The skills explicitly target the pip-install layout (`site-packages/isaacsim/extscache/`).

---

## Installation

### Install all skills

```bash
git clone https://github.com/liuquangao/isaacsim-skills.git
cd isaacsim-skills
./install.sh
```

### Install a single skill

```bash
./install.sh isaac-sim-person-simulation
```

### Update

```bash
git pull
./install.sh        # re-runs install, overwrites existing skills
```

After installing, **restart Claude Code** (or reload the VS Code window) to activate the new skills.

---

## Usage

Once installed, invoke a skill inside Claude Code by typing the trigger command:

```
/isaac-sim-person-simulation
```

Claude will load the skill's reference guide and use it to answer questions, write scripts, or debug issues — with accurate API details for your Isaac Sim version.

---

## Skill Format

Each skill lives in `skills/<skill-name>/SKILL.md` with a YAML frontmatter header:

```markdown
---
name: skill-name
description: One-line description used by Claude to decide when to load this skill.
---

# Skill content ...
```

Skills can also include a `references/` subdirectory for supporting documents loaded on demand.

---

## Contributing

Contributions are welcome — especially skills that cover:

- Robot locomotion (Go2, Spot, H1 ...)
- Sensor setup (cameras, LiDAR, IMU)
- SDG (Synthetic Data Generation) pipelines
- Multi-agent coordination
- ROS2 bridge integration

### Steps

1. Fork this repo
2. Create `skills/<your-skill-name>/SKILL.md`
3. Verify all API details against actual Isaac Sim source files in `extscache/`
4. Open a PR with a short description of what was verified and how

**Accuracy first**: every API claim should be traceable to a source file in `extscache/`. If something is unverified, mark it explicitly.

---

## License

MIT
