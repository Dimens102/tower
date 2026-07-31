# Design Documents

This directory contains the design specifications for the major architectural components of the RadioTower project.

Unlike implementation documentation, these documents describe **why** a subsystem exists, **what responsibilities it has**, and **how it fits into the overall architecture** before or alongside implementation.

These documents act as design contracts that guide future development and help maintain a consistent architecture as the project grows.

---

# Current Design Documents

# Current Design Documents

| Document | Status | Description |
|----------|--------|-------------|
| Controller.md | Implemented | Local ADS1115 controller and Wi-Fi-connected Tower Pico remote controller. |

---

# Planned Design Documents

The following design documents are expected to be added as the project evolves:

- Sensor.md
- RemoteSource.md
- RF.md
- IR.md
- DeviceManager.md
- Scheduler.md
- Configuration.md
- PluginSystem.md *(future)*

---

# Design Philosophy

Each design document should answer the following questions:

- What problem does this subsystem solve?
- What are its responsibilities?
- What are its non-responsibilities?
- How does it fit into the overall architecture?
- Who owns it?
- Which classes belong to it?
- What future extensions are anticipated?

The goal is to make architectural decisions explicit before implementation whenever possible.

---

# Relationship to Other Documentation

| Document | Purpose |
|----------|---------|
| Architecture.md | Overall system architecture and component relationships |
| Changelog.md | History of completed changes |
| Roadmap.md | Planned future work |
| design/*.md | Detailed architectural design for individual subsystems |

---

# Status

This directory will grow alongside the project and serve as the primary reference for subsystem architecture.

Each major architectural milestone should introduce or update a corresponding design document before implementation whenever practical. This helps keep architectural decisions documented separately from implementation details.
