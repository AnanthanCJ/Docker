# Docker Learnings

Notes on the concepts used in this project's `Dockerfile`. This is a multi-stage build for a Python app.

```dockerfile
FROM python:3.15-slim-trixie AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install -r requirements.txt

FROM python:3.15-slim-trixie

WORKDIR /app

COPY --from=builder /usr/local/lib/python3.15/site-packages /usr/local/lib/python3.15/site-packages

COPY . .

RUN useradd --create-home appuser
USER appuser

EXPOSE 5000

ENTRYPOINT ["python"]

CMD ["app.py"]
```

## Line by line

**`FROM python:3.15-slim-trixie AS builder`**
Starts the first build stage, named `builder`, from the official Python 3.15 image built on the `slim-trixie` (Debian Trixie, slim variant) base. "Slim" images strip out docs, build tools, and other extras to stay smaller than the full image. Naming the stage `builder` with `AS` lets later stages reference it with `COPY --from=builder`. This is the "builder" half of a multi-stage build, its only job is to install dependencies; it gets discarded from the final image.

**`WORKDIR /app`**
Sets `/app` as the working directory inside the image. Any relative paths in subsequent `COPY`, `RUN`, `CMD`, etc. are resolved against it. It also creates the directory if it doesn't exist.

**`COPY requirements.txt .`**
Copies only `requirements.txt` from the build context into `/app` in the image. Copying just this file before the rest of the source code is a deliberate layer-caching trick: Docker caches each instruction as a layer, so as long as `requirements.txt` doesn't change, Docker can reuse the cached `pip install` layer below instead of re-running it every time application code changes.

**`RUN pip install -r requirements.txt`**
Installs all Python dependencies listed in `requirements.txt` into this builder stage's filesystem (under the Python install's `site-packages`). This is the expensive, slow step that the caching trick above is designed to protect.

**`FROM python:3.15-slim-trixie`**
Starts the second, final stage from a fresh copy of the same base image. Because no `AS` name is given, this becomes the last stage and therefore the one that produces the final image. Everything from the `builder` stage (build caches, pip's own temp files, any compilers pulled in as dependencies) is left behind, only what's explicitly copied forward survives. This keeps the final image smaller and reduces its attack surface.

**`WORKDIR /app`**
Sets the working directory again, since this is a separate, fresh stage that doesn't inherit anything from `builder`.

**`COPY --from=builder /usr/local/lib/python3.15/site-packages /usr/local/lib/python3.15/site-packages`**
Copies only the installed Python packages from the `builder` stage into the final stage, at the same path so Python can find them. This is the payoff of the multi-stage setup: you get the installed dependencies without carrying over the build tools or layers used to install them.

**`COPY . .`**
Copies the rest of the build context (the application source code, e.g. `app.py`) into `/app` in the final image. This runs after the dependency install step so that code changes don't invalidate the dependency-install cache layer.

**`RUN useradd --create-home appuser`**
Creates a new non-root user named `appuser`, with a home directory (`--create-home`). Running containers as root is a security risk, if an attacker breaks out of the app, they'd have root inside the container (and potentially leverage that further). Creating a dedicated low-privilege user is a standard hardening step.

**`USER appuser`**
Switches the active user for all subsequent instructions (and for the running container) from root to `appuser`. From this point on, the container process runs unprivileged.

**`EXPOSE 5000`**
Documents that the container listens on port 5000. This is metadata only, it does not actually publish the port. You still need `-p 5000:5000` (or equivalent) on `docker run` or a `ports:` entry in Compose to make it reachable from the host. Its real value is as documentation and for tools that inspect the image.

**`ENTRYPOINT ["python"]`**
Sets the fixed, non-overridable (easily) part of the container's startup command to `python`. Using the exec form (JSON array) instead of the shell form (`ENTRYPOINT python`) avoids wrapping the process in `/bin/sh -c`, so `python` becomes PID 1 directly and correctly receives signals like `SIGTERM` for graceful shutdown.

**`CMD ["app.py"]`**
Supplies the default argument(s) appended to `ENTRYPOINT`, so the container runs `python app.py` by default. Unlike `ENTRYPOINT`, `CMD` is meant to be easily overridden, e.g. `docker run <image> other_script.py` would run `python other_script.py` instead.

## Key concepts recap

- **Multi-stage builds**: use one stage to build/compile/install, and a clean final stage to only copy over the runtime artifacts. Shrinks image size and reduces attack surface.
- **Layer caching**: order instructions from least-to-most frequently changing (dependencies before source code) so Docker can reuse cached layers and speed up rebuilds.
- **Non-root user**: always drop privileges with `useradd` + `USER` rather than running the app as root.
- **EXPOSE vs. publish**: `EXPOSE` is documentation; actual port publishing happens at `docker run`/Compose time.
- **ENTRYPOINT vs. CMD**: `ENTRYPOINT` is the fixed command, `CMD` is the default (overridable) arguments to it. Prefer exec form (`["..."]`) over shell form for proper signal handling.

*Note: this file was reconstructed after the original `LEARNINGS.md` was accidentally deleted via `rm`. The Dockerfile content itself was recovered from VSCode's Local History. Anything the original file covered beyond what's reflected in this Dockerfile (e.g. notes on `app.py` or `requirements.txt`, which could not be recovered) is not included here.*
