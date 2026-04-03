# github-common

GitHub Actions 기반의 재사용 가능한 공용 워크플로우

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](https://docs.github.com/en/actions)
[![Bash](https://img.shields.io/badge/Bash-4.0+-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow?logo=opensourceinitiative&logoColor=white)](LICENSE)

---

## 목차

- [개요](#개요)
- [프로젝트 구조](#프로젝트-구조)
- [워크플로우](#워크플로우)
  - [Docker Build](#docker-build)
  - [Release](#release)
- [라이선스](#라이선스)
- [Maintainer](#maintainer)

---

## 개요

### 목적

`github-common`은 여러 저장소에서 공통으로 사용할 수 있는 GitHub Actions 워크플로우와 Composite Action을 제공하는 공용 저장소입니다.

- Docker 이미지 빌드 및 Docker Hub 푸시를 자동화
- 릴리즈 노트 생성과 GitHub Release 생성을 자동화
- 하나의 저장소에서 CI/CD 로직을 관리하여 여러 프로젝트에 동일한 동작 보장

### 주요 구성요소

- **Reusable Workflow** (YAML): Docker 빌드/푸시, 릴리즈 생성을 오케스트레이션
- **Composite Action** (YAML + Bash): 커밋 기반 릴리즈 노트 생성

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
│       ├── docker-build-reusable.yml       # Docker 빌드/푸시 워크플로우
│       └── release-reusable.yml            # 릴리즈 생성 워크플로우
└── README.md
```

---

## 워크플로우

| 워크플로우   | 파일                        | 용도                                  |
| ------------ | --------------------------- | ------------------------------------- |
| Docker Build | `docker-build-reusable.yml` | Docker 이미지 빌드 및 Docker Hub 푸시 |
| Release      | `release-reusable.yml`      | 태그 기반 GitHub Release 생성         |

---

### Docker Build

Docker 이미지를 빌드하고 Docker Hub에 푸시하는 재사용 워크플로우입니다.

```
┌──────────────────────────────────┐
│       Calling Repository         │
│  (Dockerfile change → workflow)  │
└────────────────┬─────────────────┘
                 │
                 v
┌──────────────────────────────────┐
│    docker-build-reusable.yml     │
│                                  │
│  1. Checkout source              │
│  2. Set up Docker Buildx         │
│  3. Login to Docker Hub          │
│  4. Build & Push (matrix)        │
└──────────────────────────────────┘
```

<details>
<summary><b>사전 준비</b></summary>

#### 1. GitHub Secrets 등록

호출할 저장소의 **Settings > Secrets and variables > Actions**에 등록합니다.

| Secret               | 값                                                                                                    |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `DOCKERHUB_USERNAME` | Docker Hub 사용자명                                                                                   |
| `DOCKERHUB_TOKEN`    | Docker Hub Access Token ([생성 방법](https://docs.docker.com/security/for-developers/access-tokens/)) |

#### 2. 이미지 설정 파일 생성

호출할 저장소에 `.github/docker-images.json` 파일을 생성합니다.

```json
[
  {
    "tag": "my-image",
    "repo": "username/my-repo",
    "path": "path/to/dockerfile/dir"
  }
]
```

| 필드      | 설명                                    |
| --------- | --------------------------------------- |
| `tag`     | Docker Hub 이미지 태그                  |
| `repo`    | Docker Hub 레지스트리 (`username/repo`) |
| `path`    | Dockerfile이 위치한 디렉토리 경로 (변경 감지 및 빌드 컨텍스트로 사용) |

</details>

<details>
<summary><b>호출 워크플로우 예시</b></summary>

호출할 저장소에 `.github/workflows/docker-build.yml` 파일을 추가합니다.

```yaml
name: Docker Build

on:
  push:
    branches: [main]
    paths: ["path/to/**"]

  workflow_dispatch:
    inputs:
      images:
        description: 'Image tags to build (comma-separated or "all")'
        required: false
        default: "all"

concurrency:
  group: docker-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  detect-changes:
    runs-on: ubuntu-22.04
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
      has_images: ${{ steps.matrix.outputs.has_images }}

    steps:
      - uses: actions/checkout@v4

      - name: Detect changes and build matrix
        id: matrix
        env:
          EVENT: ${{ github.event_name }}
          INPUT: ${{ github.event.inputs.images }}
        run: |
          DEFS=$(cat .github/docker-images.json)

          if [[ "${EVENT}" == "workflow_dispatch" ]]; then
            if [[ "${INPUT}" == "all" ]]; then
              SELECTED="${DEFS}"
            else
              TAGS=$(echo "${INPUT}" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -sc .)
              SELECTED=$(echo "${DEFS}" | jq --argjson t "${TAGS}" \
                '[.[] | select(.tag as $t | $ARGS.named.t | index($t))]' --jsonargs)
            fi
          else
            CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD)
            SELECTED=$(echo "${DEFS}" | jq --arg files "${CHANGED_FILES}" '
              ($files | split("\n") | map(select(length > 0))) as $f |
              [.[] | select(.path as $p | $f | any(startswith($p)))]')
          fi

          MATRIX=$(echo "${SELECTED}" | jq -c .)
          echo "matrix=${MATRIX}" >> $GITHUB_OUTPUT
          echo "has_images=$(echo "${MATRIX}" | jq -r 'if length > 0 then "true" else "false" end')" >> $GITHUB_OUTPUT

  build:
    needs: detect-changes
    if: needs.detect-changes.outputs.has_images == 'true'
    uses: hhanoo/github-common/.github/workflows/docker-build-reusable.yml@main
    with:
      images: ${{ needs.detect-changes.outputs.matrix }}
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
```

</details>

<details>
<summary><b>사용법</b></summary>

#### 자동 빌드

Dockerfile을 수정하고 main에 push하면 변경된 이미지만 자동으로 빌드/푸시됩니다.

```bash
git add .
git commit -m "[build] Docker 이미지 업데이트"
git push origin main
```

#### 수동 빌드

GitHub Actions 탭에서 **Run workflow**로 실행합니다.

- **전체 빌드**: `all` (기본값)
- **특정 이미지만**: 쉼표로 구분 (예: `my-image,other-image`)

#### 이미지 추가

`.github/docker-images.json`에 항목만 추가하면 됩니다. 워크플로우 파일은 수정할 필요 없습니다.

```json
{
  "tag": "new-image",
  "repo": "username/my-repo",
  "path": "path/to/new-image"
}
```

#### Runner 커스터마이징

```yaml
build:
  uses: hhanoo/github-common/.github/workflows/docker-build-reusable.yml@main
  with:
    images: ${{ needs.detect-changes.outputs.matrix }}
    runner: ubuntu-24.04
  secrets:
    DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
    DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
```

</details>

---

### Release

태그 푸시 시 커밋 메시지를 분석하여 GitHub Release를 자동 생성하는 재사용 워크플로우입니다.

```
┌──────────────────────────────────┐
│       Calling Repository         │
│    (tag push → workflow_call)    │
└────────────────┬─────────────────┘
                 │
                 v
┌──────────────────────────────────┐
│      release-reusable.yml        │
│                                  │
│  1. Checkout (full history)      │
│  2. Extract tag name             │
│  3. Generate release notes ──────┼──┐
│  4. Create GitHub Release        │  │
└──────────────────────────────────┘  │
                                      │
                  ┌───────────────────┘
                  v
┌──────────────────────────────────┐
│     generate-release-notes       │
│     (Composite Action)           │
│                                  │
│  - Find previous tag             │
│  - Collect commits               │
│  - Classify by type              │
│  - Build RELEASE_NOTES.md        │
└──────────────────────────────────┘
```

<details>
<summary><b>호출 워크플로우 예시</b></summary>

호출할 저장소에 `.github/workflows/release.yml` 파일을 추가합니다.

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: write

jobs:
  release:
    uses: hhanoo/github-common/.github/workflows/release-reusable.yml@main
    with:
      runner: ubuntu-22.04 # 선택사항 (기본값: ubuntu-22.04)
```

태그를 푸시하면 자동으로 릴리즈가 생성됩니다.

```bash
git tag v1.0.0
git push origin v1.0.0
```

</details>

<details>
<summary><b>커밋 컨벤션</b></summary>

릴리즈 노트가 정확하게 분류되려면 커밋 메시지가 다음 형식 중 하나를 따라야 합니다.

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

#### 커밋 타입 분류표

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

</details>

<details>
<summary><b>릴리즈 노트 출력 구조</b></summary>

생성되는 `RELEASE_NOTES.md`는 다음 구조를 따릅니다.

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

공개 섹션에 해당하는 변경사항이 없으면 "No user-facing changes in this release."가 출력됩니다.

</details>

<details>
<summary><b>설정</b></summary>

#### Runner 커스터마이징

호출 측에서 `runner` 입력값으로 실행 환경을 지정할 수 있습니다.

```yaml
jobs:
  release:
    uses: hhanoo/github-common/.github/workflows/release-reusable.yml@main
    with:
      runner: ubuntu-24.04
```

#### Pre-release 자동 감지

태그에 `-beta` 또는 `-rc`가 포함되면 GitHub Release가 pre-release로 생성됩니다.

```bash
git tag v1.0.0-beta.1   # pre-release
git tag v1.0.0-rc.1     # pre-release
git tag v1.0.0          # 정식 release
```

</details>

---

## 라이선스

이 프로젝트는 MIT 라이선스로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

---

## Maintainer

hhanoo (woo980711@gmail.com)
