# github-common

GitHub Actions 기반의 재사용 가능한 릴리즈 자동화 워크플로우

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](https://docs.github.com/en/actions)
[![Bash](https://img.shields.io/badge/Bash-4.0+-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## 목차

- [개요](#개요)
- [주요 기능](#주요-기능)
- [시스템 구조](#시스템-구조)
- [프로젝트 구조](#프로젝트-구조)
- [빠른 시작](#빠른-시작)
- [사용법](#사용법)
- [설정](#설정)
- [커밋 타입 분류표](#커밋-타입-분류표)
- [라이선스](#라이선스)
- [Maintainer](#maintainer)

---

## 개요

`github-common`은 여러 저장소에서 공통으로 사용할 수 있는 GitHub Actions 워크플로우와 Composite Action을 제공하는 공용 저장소이다.

**목적**

- 릴리즈 노트 생성과 GitHub Release 생성을 자동화
- 커밋 메시지 기반으로 변경사항을 자동 분류하여 일관된 릴리즈 노트 제공
- 하나의 저장소에서 릴리즈 로직을 관리하여 여러 프로젝트에 동일한 동작 보장

**주요 구성요소**

- **Reusable Workflow** (YAML): 태그 푸시 시 릴리즈 생성을 오케스트레이션
- **Composite Action** (YAML + Bash): 커밋 기반 릴리즈 노트 생성

**적용 영역**

- 태그 기반 릴리즈를 사용하는 모든 GitHub 저장소

---

## 주요 기능

- **자동 릴리즈 노트 생성**: 이전 태그부터 현재 태그까지의 커밋을 분석하여 카테고리별로 분류된 릴리즈 노트를 자동 생성
- **GitHub Release 자동 생성**: 생성된 릴리즈 노트를 기반으로 GitHub Release를 자동 생성
- **Pre-release 자동 감지**: 태그에 `-beta` 또는 `-rc`가 포함되면 자동으로 pre-release로 처리
- **커밋 타입 분류**: `[type] Subject` 또는 `type: Subject` 형식의 커밋 메시지를 24개 타입으로 자동 분류
- **공개/내부 분리**: 사용자에게 의미 있는 변경사항(기능, 수정, 개선)만 공개 릴리즈 노트에 포함하고, 내부 변경사항(빌드, 스타일, 테스트 등)은 제외
- **Runner 커스터마이징**: 호출 측에서 실행 환경(runner)을 지정 가능

---

## 시스템 구조

```
┌─────────────────────────────────┐
│       Calling Repository        │
│   (tag push -> workflow_call)   │
└────────────────┬────────────────┘
                 │
                 v
┌─────────────────────────────────┐
│     release-reusable.yml        │
│     (Reusable Workflow)         │
│                                 │
│  1. Checkout (full history)     │
│  2. Extract tag name            │
│  3. Generate release notes ─────┼──┐
│  4. Create GitHub Release       │  │
└─────────────────────────────────┘  │
                                     │
                 ┌───────────────────┘
                 v
┌─────────────────────────────────┐
│     generate-release-notes      │
│     (Composite Action)          │
│                                 │
│  action.yml                     │
│    └─ generate_release_         │
│       notes.sh                  │
│       - Find previous tag       │
│       - Collect commits         │
│       - Classify by type        │
│       - Build RELEASE_NOTES.md  │
└─────────────────────────────────┘
```

---

## 프로젝트 구조

```
github-common/
├── .github/
│   ├── actions/
│   │   └── generate-release-notes/
│   │       ├── action.yml                  # Composite Action 정의
│   │       └── generate_release_notes.sh   # 릴리즈 노트 생성 스크립트
│   └── workflows/
│       └── release-reusable.yml            # 재사용 가능한 릴리즈 워크플로우
└── README.md
```

---

## 빠른 시작

호출할 저장소에 워크플로우 파일을 추가한다.

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    uses: hhanoo/github-common/.github/workflows/release-reusable.yml@main
```

태그를 푸시하면 자동으로 릴리즈가 생성된다.

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## 사용법

### 1. 커밋 컨벤션

릴리즈 노트가 정확하게 분류되려면 커밋 메시지가 다음 형식 중 하나를 따라야 한다.

```
[type] Subject
```

```
type: Subject
```

예시:

```
[feature] 사용자 인증 기능 추가
fix: 로그인 시 토큰 만료 오류 수정
[!hotfix] 결제 금액 계산 오류 긴급 수정
```

### 2. 워크플로우 호출

다른 저장소에서 `workflow_call`로 호출한다.

```yaml
jobs:
  release:
    uses: hhanoo/github-common/.github/workflows/release-reusable.yml@main
    with:
      runner: ubuntu-22.04 # 선택사항 (기본값: ubuntu-22.04)
```

### 3. 릴리즈 노트 출력 구조

생성되는 `RELEASE_NOTES.md`는 다음 구조를 따른다.

```markdown
## v1.2.0

Changes since `v1.1.0`.

### Breaking Changes

- 기존 API 응답 형식 변경

### Hotfix

- 결제 금액 계산 오류 긴급 수정

### Features

- 사용자 인증 기능 추가

### Fixes

- 로그인 시 토큰 만료 오류 수정

### Improvements

- 데이터베이스 쿼리 최적화

### Documentation

- API 문서 업데이트

---

Full Changelog: `v1.1.0...v1.2.0`
```

공개 섹션에 해당하는 변경사항이 없으면 "No user-facing changes in this release."가 출력된다.

---

## 설정

### Runner 커스터마이징

호출 측에서 `runner` 입력값으로 실행 환경을 지정할 수 있다.

```yaml
jobs:
  release:
    uses: hhanoo/github-common/.github/workflows/release-reusable.yml@main
    with:
      runner: ubuntu-24.04
```

### Pre-release 자동 감지

태그에 `-beta` 또는 `-rc`가 포함되면 GitHub Release가 pre-release로 생성된다.

```bash
git tag v1.0.0-beta.1   # pre-release
git tag v1.0.0-rc.1     # pre-release
git tag v1.0.0          # 정식 release
```

---

## 커밋 타입 분류표

| 커밋 타입                      | 릴리즈 노트 섹션 | 공개 여부 |
| ------------------------------ | ---------------- | --------- |
| `feature`, `feat`              | Features         | 공개      |
| `fix`                          | Fixes            | 공개      |
| `perf`                         | Improvements     | 공개      |
| `refactor`                     | Improvements     | 공개      |
| `cleanup`                      | Improvements     | 공개      |
| `docs`, `doc`                  | Documentation    | 공개      |
| `!breaking change`, `breaking` | Breaking Changes | 공개      |
| `!hotfix`, `hotfix`            | Hotfix           | 공개      |
| `build`                        | --               | 내부      |
| `design`                       | --               | 내부      |
| `style`                        | --               | 내부      |
| `comment`                      | --               | 내부      |
| `test`, `tests`                | --               | 내부      |
| `chore`                        | --               | 내부      |
| `rename`                       | --               | 내부      |
| `remove`                       | --               | 내부      |
| `setting`, `settings`          | --               | 내부      |
| `merge`                        | --               | 내부      |

---

## 라이선스

MIT License

---

## Maintainer

hhanoo (woo980711@gmail.com)
