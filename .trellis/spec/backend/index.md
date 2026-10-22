# Backend Development Guidelines

> Best practices for backend development in this project.

---

## Overview

This directory contains guidelines for backend development. Fill in each file with your project's specific conventions.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Module organization and file layout | To fill |
| [Database Guidelines](./database-guidelines.md) | ORM patterns, queries, migrations | To fill |
| [Error Handling](./error-handling.md) | Error types, handling strategies | To fill |
| [Quality Guidelines](./quality-guidelines.md) | Code standards, forbidden patterns | To fill |
| [Logging Guidelines](./logging-guidelines.md) | Structured logging, log levels | To fill |
| [SQL Query Library](./sql-query-library.md) | Query persistence and filesystem failure behavior | Documented |
| [SQLite Workspace](./sql-workspace.md) | Stable grid identity and fixed-offset paging | Documented |
| [SQLite Native Runtime](./sqlite-native-runtime.md) | Multi-platform C packaging, FFI, queries and real runtime evidence | Implemented |
| [SQL Diagnostics](./sql-diagnostics.md) | Exact snapshots, isolated prepare-only validation, UTF-16 ranges and incomplete coverage | Implemented; target acceptance separate |
| [OHOS Audit Packaging](./ohos-audit-packaging.md) | Real ABI staging, separate audit bundle, SDK test signing and final archive provenance | Build verified; device acceptance separate |
| [Oracle MySQL Workspace](./mysql-workspace.md) | Oracle metadata, primary keys, binary values, and native client | Documented |
| [Oracle Desktop Runtime](./mysql-desktop-runtime.md) | Windows/Linux private server lifecycle, FFI and bundle contract | Implemented |
| [Oracle Android Runtime](./mysql-android-runtime.md) | Bionic build, installed code/data layout and private server lifecycle | Implemented; x86_64 device verified |

---

## Pre-Development Checklist

- Read SQLite Native Runtime for SQLite engine, FFI and packaging changes.
- Read Oracle Desktop Runtime for local MySQL client, lifecycle or desktop packaging changes.
- Read Oracle Android Runtime for Android Oracle build, installation and lifecycle changes.

## Quality Check

- Run the native engine and existing SQL tests; see SQLite Native Runtime for
  platform verification requirements and explicit environment skips.
- For local Oracle changes, run the real lifecycle checks and typed adapter tests
  described in Oracle Desktop Runtime. Preserve OHOS C++ symbols.

## How to Fill These Guidelines

For each guideline file:

1. Document your project's **actual conventions** (not ideals)
2. Include **code examples** from your codebase
3. List **forbidden patterns** and why
4. Add **common mistakes** your team has made

The goal is to help AI assistants and new team members understand how YOUR project works.

---

**Language**: All documentation should be written in **English**.
