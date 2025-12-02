# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2025-12-02

### Fixed

- Documentation for Claude skill file

## [0.7.0] - 2025-11-25

### Fixed

- Support returning 3+ :ok/:error tuples from run/ok_then/error_then function callbacks

## [0.6.0] - 2025-11-23

### Added

- `tap_ok` and `tap_error` functions

## [0.5.0] - 2025-11-21

### Changed

- Renamed `then!/1` and `then/1` to `run!/1` and `run/1`
- Renamed `then!/2` and `then/2` to `ok_then!/2` and `ok_then/2`
- Renamed `handle/2` to `error_then/2`

### Added

- `retries` option for `run!/2`,`run/2`, `ok_then!/3`, and `ok_then/3`

## [0.4.4] - 2025-11-19

### Added

- "Interesting Examples" headers

## [0.4.3] - 2025-11-19

### Added

- More examples in "Interesting Examples" guide

## [0.4.2] - 2025-11-19

### Changed

- Claude `SKILL.md` file in docs

### Changed

- Docs

## [0.4.1] - 2025-11-15

### Changed

- "Interesting Examples" guide

## [0.4.0] - 2025-11-13

### Changed

- Add support for Ecto.Changeset in `user_message`

## [0.3.6] - 2025-11-12

### Changed

- Docs

## [0.3.5] - 2025-11-12

### Changed

- Docs

## [0.3.4] - 2025-11-11

### Changed

- Docs

## [0.3.3] - 2025-11-10

### Changed

- Docs

## [0.3.2] - 2025-11-10

### Changed

- Docs

## [0.3.1] - 2025-11-04

### Changed

- Docs

## [0.3.0] - 2025-11-04

### Changed

- `map_unless` renamed to `map_if`
- Docs

## [0.2.6] - 2025-11-04

### Changed

- Docs

## [0.2.5] - 2025-11-04

### Changed

- Docs

## [0.2.4] - 2025-11-03

### Changed

- Docs

## [0.2.3] - 2025-10-31

### Changed

- Docs

## [0.2.2] - 2025-10-31

### Changed

- Docs

## [0.2.1] - 2025-10-31

### Changed

- Docs

## [0.2.0] - 2025-10-31

### Changed

- Rename module to `Triage`

### Added

- Documentation improvements

## [0.1.0] - 2025-10-31

### Added

- Previous work under a different name, pushed as `triage` to reserve package
