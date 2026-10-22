# Frontend Development Guidelines

> Best practices for frontend development in this project.

---

## Overview

This directory contains guidelines for frontend development. Fill in each file with your project's specific conventions.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Module organization and file layout | To fill |
| [Component Guidelines](./component-guidelines.md) | Component patterns, props, composition | To fill |
| [Hook Guidelines](./hook-guidelines.md) | Custom hooks, data fetching patterns | To fill |
| [State Management](./state-management.md) | Local state, global state, server state | To fill |
| [Quality Guidelines](./quality-guidelines.md) | Code standards, forbidden patterns | To fill |
| [Type Safety](./type-safety.md) | Type patterns, validation | To fill |
| [SQL Workbench](./sql-workbench.md) | App-local workspace, selection and dialog contracts | Documented |
| [Tutorial Imports](./tutorial-code-import.md) | MD3 content lists, custom source imports, backup and editor activation | Documented |
| [SQL Content Repository](./sql-content-repository.md) | App-local SQL curriculum assets, shared-catalog loading, authoring/validation pipeline | Documented |
| [SQL Terminal and Offline](./sql-terminal-offline.md) | Shared terminal delegate, project database identity and offline cloud refusal | Documented |
| [SQL Diagnostics](../backend/sql-diagnostics.md) | Unsaved-buffer adapter and honest engine/lexical diagnostic limits | Documented |

---

## Quality Check

- Run `flutter analyze --no-pub lib test integration_test` and the complete
  `flutter test --no-pub` suite with the compatible project SDK. Record explicit
  unavailable-runtime skips separately from passes.
- Follow the SQL workbench, terminal/offline and content repository contracts
  above. Validate five-page swiping, retained state, phone/desktop widths and
  large text; exercise the same SQL delegate through both terminal surfaces.
- Run both curriculum validators against authoring source and shipped assets.
  Native MySQL-only lessons require the separate platform integration target.
- Record the shared-core revision and pending source changes. Never modify
  other products or merge SQL home destinations in the shared package.

## How to Fill These Guidelines

For each guideline file:

1. Document your project's **actual conventions** (not ideals)
2. Include **code examples** from your codebase
3. List **forbidden patterns** and why
4. Add **common mistakes** your team has made

The goal is to help AI assistants and new team members understand how YOUR project works.

---

**Language**: All documentation should be written in **English**.
